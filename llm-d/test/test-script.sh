#!/usr/bin/env bash
# llm-d feature validation test orchestrator.
#
# Usage:
#   ./test-script.sh setup
#   ./test-script.sh run <scenario>
#   ./test-script.sh run-all
#   ./test-script.sh deploy <scenario>
#   ./test-script.sh benchmark <scenario>
#   ./test-script.sh collect <scenario>
#   ./test-script.sh cleanup <scenario>
#   ./test-script.sh cleanup-all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/env.sh
source "${SCRIPT_DIR}/common/env.sh"
# shellcheck source=common/collect-results.sh
source "${SCRIPT_DIR}/common/collect-results.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [scenario]

Commands:
  setup              Verify cluster access, gateway, and monitoring
  run <scenario>     Deploy model, run benchmark, collect results, cleanup job and LLMInferenceService
  run-all            Run all scenarios (undeploy LLMInferenceService only at the end)
  deploy <scenario>  Apply llminferenceservice.yaml and wait for Ready
  benchmark <scenario>  Apply guidellm-job.yaml and wait for completion
  collect <scenario> Copy benchmark results to scenario/results/
  cleanup <scenario> Delete guidellm job for scenario
  cleanup-all        Delete all test jobs and LLMInferenceServices

Scenarios:
  00-baseline
  01a-prefix-cache-routing
  01b-queue-kv-scheduling
  01c-round-robin-control
  02a-global-cache-indexing
  03a-pd-separation
  03b-pd-kv-transfer
  03c-heterogeneous-pd
  04a-data-parallelism
EOF
}

require_scenario() {
  local scenario="${1:-}"
  if [[ -z "${scenario}" || ! -d "${SCRIPT_DIR}/${scenario}" ]]; then
    echo "ERROR: Unknown or missing scenario: ${scenario}" >&2
    usage
    exit 1
  fi
}

setup() {
  echo "==> Verifying cluster access..."
  oc whoami

  if [[ -z "${GATEWAY_HOST}" ]]; then
    echo "ERROR: Could not detect gateway hostname. Set GATEWAY_HOST manually." >&2
    exit 1
  fi
  echo "Gateway host: ${GATEWAY_HOST}"

  echo "==> Checking namespace ${LLM_NAMESPACE}..."
  oc get namespace "${LLM_NAMESPACE}" >/dev/null

  echo "==> Checking monitoring namespace ${MONITORING_NS}..."
  if oc get namespace "${MONITORING_NS}" >/dev/null 2>&1; then
    oc get pods -n "${MONITORING_NS}" -l app=prometheus 2>/dev/null || true
    echo "Grafana route: $(oc get route grafana-secure -n "${MONITORING_NS}" -o jsonpath='{.spec.host}' 2>/dev/null || echo 'not found')"
  else
    echo "WARN: Monitoring namespace ${MONITORING_NS} not found. Apply overlays/09-llm-d-monitoring first."
  fi

  echo "Setup complete."
}

undeploy_conflicting_llm() {
  local scenario="${1}"
  local service
  service="$(scenario_llm_service "${scenario}")"

  if [[ "${service}" == "qwen-pd" ]]; then
    undeploy_llm_service qwen
  elif [[ "${service}" == "qwen" ]]; then
    undeploy_llm_service qwen-pd
  fi
}

undeploy_llm_service() {
  local service="${1}"
  if ! oc get llminferenceservice "${service}" -n "${LLM_NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  echo "==> Removing LLMInferenceService ${service}..."
  oc delete llminferenceservice "${service}" -n "${LLM_NAMESPACE}" --wait=true --timeout=600s

  echo "==> Waiting for ${service} pods to terminate..."
  local deadline=$((SECONDS + 600))
  while (( SECONDS < deadline )); do
    local remaining
    remaining="$(oc get pods -n "${LLM_NAMESPACE}" \
      -l "serving.kserve.io/inferenceservice=${service}" \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${remaining}" == "0" ]]; then
      echo "==> ${service} fully removed"
      return 0
    fi
    sleep 5
  done

  echo "WARN: Timed out waiting for ${service} pods to terminate" >&2
  oc get pods -n "${LLM_NAMESPACE}" -l "serving.kserve.io/inferenceservice=${service}" || true
  return 1
}

undeploy_scenario() {
  local scenario="${1}"
  if ! scenario_needs_deploy "${scenario}"; then
    echo "==> Skipping LLMInferenceService cleanup for ${scenario} (reused existing deployment)"
    return 0
  fi

  local service
  service="$(scenario_llm_service "${scenario}")"
  undeploy_llm_service "${service}"
}

deploy_scenario() {
  local scenario="${1}"
  local scenario_dir="${SCRIPT_DIR}/${scenario}"
  local service
  service="$(scenario_llm_service "${scenario}")"

  if ! scenario_needs_deploy "${scenario}"; then
    echo "==> Skipping deploy for ${scenario} (reuses existing ${service})"
    oc wait --for=condition=Ready "llminferenceservice/${service}" \
      -n "${LLM_NAMESPACE}" --timeout=600s
    return 0
  fi

  undeploy_conflicting_llm "${scenario}"
  undeploy_llm_service "${service}"

  echo "==> Deploying ${service} for scenario ${scenario}..."
  oc apply -f "${scenario_dir}/llminferenceservice.yaml"
  oc wait --for=condition=Ready "llminferenceservice/${service}" \
    -n "${LLM_NAMESPACE}" --timeout=600s
  echo "==> ${service} is Ready"
}

smoke_test() {
  local service="${1}"
  LLM_URL="$(llm_url "${service}")"
  local token
  token="$(oc create token test-user -n "${LLM_NAMESPACE}")"

  echo "==> Smoke test: ${LLM_URL}/v1/models"
  curl -sf "${LLM_URL}/v1/models" -H "Authorization: Bearer ${token}" | head -c 200
  echo ""
}

render_guidellm_job() {
  local scenario="${1}"
  local scenario_dir="${SCRIPT_DIR}/${scenario}"
  local service
  service="$(scenario_llm_service "${scenario}")"
  local rendered="${scenario_dir}/.guidellm-job.rendered.yaml"

  LLM_URL="$(llm_url "${service}")"

  render_template "${scenario_dir}/guidellm-job.yaml" "${rendered}"
  echo "${rendered}"
}

benchmark_scenario() {
  local scenario="${1}"
  local job_name
  job_name="$(scenario_job_name "${scenario}")"
  local rendered
  rendered="$(render_guidellm_job "${scenario}")"

  echo "==> Deleting previous job ${job_name} if exists..."
  oc delete job "${job_name}" -n "${LLM_NAMESPACE}" --ignore-not-found=true
  sleep 2

  echo "==> Running benchmark job ${job_name}..."
  START_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  oc apply -f "${rendered}"
  oc wait --for=condition=complete "job/${job_name}" \
    -n "${LLM_NAMESPACE}" --timeout=1800s
  END_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Benchmark completed: ${START_TIME} -> ${END_TIME}"
  echo "Open Grafana and set time range to this window for metric correlation."
}

run_scenario() {
  local scenario="${1}"
  local skip_undeploy="${2:-false}"
  require_scenario "${scenario}"

  deploy_scenario "${scenario}"
  smoke_test "$(scenario_llm_service "${scenario}")"
  benchmark_scenario "${scenario}"
  collect_results "${SCRIPT_DIR}/${scenario}" "$(scenario_job_name "${scenario}")" "${LLM_NAMESPACE}"
  cleanup_scenario "${scenario}"

  if [[ "${skip_undeploy}" != "true" ]]; then
    undeploy_scenario "${scenario}"
  fi
}

cleanup_scenario() {
  local scenario="${1}"
  require_scenario "${scenario}"
  local job_name
  job_name="$(scenario_job_name "${scenario}")"
  echo "==> Deleting job ${job_name}..."
  oc delete job "${job_name}" -n "${LLM_NAMESPACE}" --ignore-not-found=true
  rm -f "${SCRIPT_DIR}/${scenario}/.guidellm-job.rendered.yaml"
}

cleanup_all() {
  for scenario in "${RUN_ALL_SCENARIOS[@]}"; do
    cleanup_scenario "${scenario}" || true
  done
  undeploy_llm_service qwen || true
  undeploy_llm_service qwen-pd || true
}

main() {
  local cmd="${1:-}"
  local scenario="${2:-}"

  case "${cmd}" in
    setup) setup ;;
    run) require_scenario "${scenario}"; run_scenario "${scenario}" ;;
    run-all)
      setup
      for s in "${RUN_ALL_SCENARIOS[@]}"; do
        echo ""
        echo "=========================================="
        echo " Running scenario: ${s}"
        echo "=========================================="
        run_scenario "${s}" "true"
      done
      undeploy_llm_service qwen || true
      undeploy_llm_service qwen-pd || true
      ;;
    deploy) require_scenario "${scenario}"; deploy_scenario "${scenario}" ;;
    benchmark) require_scenario "${scenario}"; benchmark_scenario "${scenario}" ;;
    collect) require_scenario "${scenario}"; collect_results "${SCRIPT_DIR}/${scenario}" "$(scenario_job_name "${scenario}")" "${LLM_NAMESPACE}" ;;
    cleanup) require_scenario "${scenario}"; cleanup_scenario "${scenario}" ;;
    cleanup-all) cleanup_all ;;
    -h|--help|help|"") usage ;;
    *) echo "ERROR: Unknown command: ${cmd}" >&2; usage; exit 1 ;;
  esac
}

main "$@"
