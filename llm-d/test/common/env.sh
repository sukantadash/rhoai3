#!/usr/bin/env bash
# Shared environment for llm-d feature tests.

LLM_NAMESPACE="${LLM_NAMESPACE:-demo-llm}"
LLM_MODEL="${LLM_MODEL:-RedHatAI/Qwen3-8B-FP8-dynamic}"
# Set CLEANUP_LLM=true or pass --cleanup to remove LLMInferenceService after a run.
CLEANUP_LLM="${CLEANUP_LLM:-false}"

scenario_llm_model() {
  echo "${LLM_MODEL}"
}
MONITORING_NS="${MONITORING_NS:-llm-d-monitoring}"
GUIDELLM_IMAGE="${GUIDELLM_IMAGE:-ghcr.io/vllm-project/guidellm@sha256:e3ad2371bfa8e42f2c3d1251b62d0d9c9706c27ae2143c8c048eb5fc6aebb558}"

detect_gateway_host() {
  oc get gateway openshift-ai-inference -n openshift-ingress \
    -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null || true
}

GATEWAY_HOST="${GATEWAY_HOST:-$(detect_gateway_host)}"

llm_url() {
  local service="${1:?service name required}"
  echo "https://${GATEWAY_HOST}/${LLM_NAMESPACE}/${service}"
}

# Portable template renderer (macOS lacks envsubst).
render_template() {
  local src="${1:?source file required}"
  local dst="${2:?destination file required}"
  sed \
    -e "s|\${GUIDELLM_IMAGE}|${GUIDELLM_IMAGE}|g" \
    -e "s|\${LLM_URL}|${LLM_URL}|g" \
    -e "s|\${LLM_MODEL}|${LLM_MODEL}|g" \
    "${src}" > "${dst}"
}

scenario_llm_service() {
  case "$1" in
    00-baseline|01a-prefix-cache-routing|01b-precise-prefix-cache-routing|\
    01c-queue-kv-scheduling|01d-round-robin-control|02a-global-cache-indexing|\
    04a-data-parallelism)
      echo "qwen"
      ;;
    03a-pd-separation|03b-pd-kv-transfer|03c-heterogeneous-pd)
      echo "qwen-pd"
      ;;
    *)
      return 1
      ;;
  esac
}

scenario_job_name() {
  case "$1" in
    00-baseline) echo "guidellm-00-baseline" ;;
    01a-prefix-cache-routing) echo "guidellm-01a-prefix-cache" ;;
    01b-precise-prefix-cache-routing) echo "guidellm-01b-precise-prefix-cache" ;;
    01c-queue-kv-scheduling) echo "guidellm-01c-queue-kv" ;;
    01d-round-robin-control) echo "guidellm-01d-round-robin" ;;
    02a-global-cache-indexing) echo "guidellm-02a-global-cache" ;;
    03a-pd-separation) echo "guidellm-03a-pd-separation" ;;
    03b-pd-kv-transfer) echo "guidellm-03b-pd-kv-transfer" ;;
    03c-heterogeneous-pd) echo "guidellm-03c-heterogeneous-pd" ;;
    04a-data-parallelism) echo "guidellm-04a-data-parallelism" ;;
    *) return 1 ;;
  esac
}

# Returns 0 if deploy is needed, 1 if deploy should be skipped.
scenario_needs_deploy() {
  case "$1" in
    01c-queue-kv-scheduling|03b-pd-kv-transfer|03c-heterogeneous-pd)
      return 1
      ;;
    00-baseline|01a-prefix-cache-routing|01b-precise-prefix-cache-routing|\
    01d-round-robin-control|02a-global-cache-indexing|03a-pd-separation|\
    04a-data-parallelism)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Base deployment to apply when a reuse scenario runs without its service present.
scenario_deploy_prerequisite() {
  case "$1" in
    01c-queue-kv-scheduling) echo "01a-prefix-cache-routing" ;;
    03b-pd-kv-transfer|03c-heterogeneous-pd) echo "03a-pd-separation" ;;
    *) return 1 ;;
  esac
}

RUN_ALL_SCENARIOS=(
  00-baseline
  01a-prefix-cache-routing
  01c-queue-kv-scheduling
  01d-round-robin-control
  01b-precise-prefix-cache-routing
  02a-global-cache-indexing
  03a-pd-separation
  03b-pd-kv-transfer
  03c-heterogeneous-pd
  04a-data-parallelism
)
