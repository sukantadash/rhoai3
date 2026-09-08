#!/usr/bin/env bash
# llm-d feature validation test orchestrator.
#
# Usage:
#   ./test-script.sh setup
#   ./test-script.sh run <scenario> [scenario ...] [--cleanup]
#   ./test-script.sh run-all [--cleanup]
#   ./test-script.sh deploy <scenario> [scenario ...]
#   ./test-script.sh benchmark <scenario> [scenario ...]
#   ./test-script.sh collect <scenario> [scenario ...]
#   ./test-script.sh cleanup <scenario> [scenario ...]
#   ./test-script.sh cleanup-all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/env.sh
source "${SCRIPT_DIR}/common/env.sh"
# shellcheck source=common/collect-results.sh
source "${SCRIPT_DIR}/common/collect-results.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <command> [scenario ...]

Options:
  --cleanup          Remove LLMInferenceService after run / run-all (default: keep running)

Commands:
  setup              Verify cluster access, gateway, and monitoring
  run <scenario>...  Deploy model, run benchmark, collect results, delete job
  run-all            Run all scenarios in order
  deploy <scenario>...  Apply llminferenceservice.yaml and wait for Ready
  benchmark <scenario>...  Apply guidellm-job.yaml and wait for completion
  collect <scenario>...  Copy benchmark results to scenario/results/
  cleanup <scenario>...  Delete guidellm job for scenario
  cleanup-all        Delete all test jobs; add --cleanup to also remove LLMInferenceServices

Scenarios accept short IDs (00, 01a, 04a) or full directory names (00-baseline).

By default, run keeps the LLMInferenceService running so follow-on scenarios
(e.g. 01c reusing 01a) can proceed without redeploying.

Examples:
  $(basename "$0") run 00-baseline
  $(basename "$0") run 00 01a 04a
  $(basename "$0") run 00-baseline --cleanup
  $(basename "$0") --cleanup run-all
  CLEANUP_LLM=true $(basename "$0") run 01a-prefix-cache-routing

Scenarios:
  00-baseline
  01a-prefix-cache-routing
  01b-precise-prefix-cache-routing
  01c-queue-kv-scheduling
  01d-round-robin-control
  02a-global-cache-indexing
  03a-pd-separation
  03b-pd-kv-transfer
  03c-heterogeneous-pd
  04a-data-parallelism
EOF
}

resolve_scenario() {
  local input="${1:-}"
  if [[ -z "${input}" ]]; then
    echo "ERROR: Missing scenario" >&2
    return 1
  fi

  if [[ -d "${SCRIPT_DIR}/${input}" ]]; then
    echo "${input}"
    return 0
  fi

  local -a matches=()
  local scenario
  for scenario in "${RUN_ALL_SCENARIOS[@]}"; do
    if [[ "${scenario}" == "${input}" || "${scenario}" == "${input}-"* ]]; then
      matches+=("${scenario}")
    fi
  done

  if [[ ${#matches[@]} -eq 1 ]]; then
    echo "${matches[0]}"
    return 0
  fi

  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "ERROR: Ambiguous scenario '${input}': ${matches[*]}" >&2
    return 1
  fi

  echo "ERROR: Unknown scenario: ${input}" >&2
  return 1
}

require_scenario() {
  local scenario="${1:-}"
  resolve_scenario "${scenario}" >/dev/null || {
    usage
    exit 1
  }
}

resolve_scenarios() {
  local -a resolved=()
  local input scenario
  for input in "$@"; do
    scenario="$(resolve_scenario "${input}")" || return 1
    resolved+=("${scenario}")
  done
  printf '%s\n' "${resolved[@]}"
}

require_scenarios() {
  if [[ $# -eq 0 ]]; then
    echo "ERROR: At least one scenario is required" >&2
    usage
    exit 1
  fi
  resolve_scenarios "$@" || {
    usage
    exit 1
  }
}

print_scenario_banner() {
  local scenario="${1}"
  echo ""
  echo "=========================================="
  echo " Running scenario: ${scenario}"
  echo "=========================================="
}

cleanup_llm_services() {
  if [[ "${CLEANUP_LLM}" == "true" ]]; then
    undeploy_llm_service qwen || true
    undeploy_llm_service qwen-pd || true
  else
    echo "==> Keeping LLMInferenceServices running (pass --cleanup to remove)"
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

llm_service_exists() {
  local service="${1}"
  oc get llminferenceservice "${service}" -n "${LLM_NAMESPACE}" >/dev/null 2>&1
}

deploy_scenario() {
  local scenario="${1}"
  local scenario_dir="${SCRIPT_DIR}/${scenario}"
  local service
  service="$(scenario_llm_service "${scenario}")"

  if ! scenario_needs_deploy "${scenario}"; then
    if llm_service_exists "${service}"; then
      echo "==> Skipping deploy for ${scenario} (reuses existing ${service})"
      oc wait --for=condition=Ready "llminferenceservice/${service}" \
        -n "${LLM_NAMESPACE}" --timeout=600s
      return 0
    fi

    local prereq
    if ! prereq="$(scenario_deploy_prerequisite "${scenario}")"; then
      echo "ERROR: ${scenario} reuses ${service}, but ${service} is not deployed." >&2
      echo "Run the prerequisite scenario first (see TESTPLAN.md)." >&2
      exit 1
    fi

    echo "==> ${service} not found; deploying prerequisite ${prereq} for ${scenario}..."
    deploy_scenario "${prereq}"
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
  LLM_MODEL="$(scenario_llm_model "${scenario}")"

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
  local defer_llm_cleanup="${2:-false}"
  require_scenario "${scenario}"

  deploy_scenario "${scenario}"
  smoke_test "$(scenario_llm_service "${scenario}")"
  benchmark_scenario "${scenario}"
  collect_results "${SCRIPT_DIR}/${scenario}" "$(scenario_job_name "${scenario}")" "${LLM_NAMESPACE}"
  cleanup_scenario "${scenario}"

  if [[ "${CLEANUP_LLM}" == "true" && "${defer_llm_cleanup}" != "true" ]]; then
    undeploy_scenario "${scenario}"
  else
    echo "==> Keeping LLMInferenceService $(scenario_llm_service "${scenario}") running (pass --cleanup to remove)"
  fi
}

run_scenarios() {
  local -a scenarios=("$@")
  local scenario
  local defer_llm_cleanup="false"
  if [[ ${#scenarios[@]} -gt 1 && "${CLEANUP_LLM}" == "true" ]]; then
    defer_llm_cleanup="true"
  fi

  for scenario in "${scenarios[@]}"; do
    print_scenario_banner "${scenario}"
    run_scenario "${scenario}" "${defer_llm_cleanup}"
  done

  if [[ "${defer_llm_cleanup}" == "true" ]]; then
    cleanup_llm_services
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
  cleanup_llm_services
}

parse_args() {
  local -a remaining=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cleanup)
        CLEANUP_LLM=true
        shift
        ;;
      -h|--help|help)
        remaining=("help")
        shift
        ;;
      *)
        remaining+=("$1")
        shift
        ;;
    esac
  done
  printf '%s\n' "${remaining[@]}"
}

main() {
  local -a args=()
  local -a scenarios=()
  local cmd scenario line

  while IFS= read -r line; do
    args+=("${line}")
  done < <(parse_args "$@")

  cmd="${args[0]:-}"
  if ((${#args[@]} > 1)); then
    scenarios=("${args[@]:1}")
  fi

  case "${cmd}" in
    setup) setup ;;
    run)
      scenarios=($(require_scenarios "${scenarios[@]}"))
      run_scenarios "${scenarios[@]}"
      ;;
    run-all)
      setup
      run_scenarios "${RUN_ALL_SCENARIOS[@]}"
      ;;
    deploy)
      scenarios=($(require_scenarios "${scenarios[@]}"))
      for scenario in "${scenarios[@]}"; do
        print_scenario_banner "${scenario}"
        deploy_scenario "${scenario}"
      done
      ;;
    benchmark)
      scenarios=($(require_scenarios "${scenarios[@]}"))
      for scenario in "${scenarios[@]}"; do
        print_scenario_banner "${scenario}"
        benchmark_scenario "${scenario}"
      done
      ;;
    collect)
      scenarios=($(require_scenarios "${scenarios[@]}"))
      for scenario in "${scenarios[@]}"; do
        print_scenario_banner "${scenario}"
        collect_results "${SCRIPT_DIR}/${scenario}" "$(scenario_job_name "${scenario}")" "${LLM_NAMESPACE}"
      done
      ;;
    cleanup)
      scenarios=($(require_scenarios "${scenarios[@]}"))
      for scenario in "${scenarios[@]}"; do
        print_scenario_banner "${scenario}"
        cleanup_scenario "${scenario}"
      done
      ;;
    cleanup-all) cleanup_all ;;
    help|"") usage ;;
    *) echo "ERROR: Unknown command: ${cmd}" >&2; usage; exit 1 ;;
  esac
}

main "$@"
