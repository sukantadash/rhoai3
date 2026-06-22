#!/usr/bin/env bash
# llm-d deployment — kustomize overlay flow (mirrors maas-script.sh pattern).
# Prerequisites: ./ocp-gpu-setup/README.md (NFD + NVIDIA GPU Operator)

set -euo pipefail

cd "$(dirname "$0")/llm-d"

oc apply -k ./overlays/01-operators/
oc apply -k ./overlays/02-operator-instances/
oc apply -k ./overlays/03-rhoai/

# Update hostname in instances/gateway/gateway.yaml and issuer in tlspolicy.yaml before applying.
#the issuer in the tlspolicy.yaml should be the same as cluster issuer (oc get clusterissuer

oc apply -k ./overlays/04-gateway/

#verify certificate is created: (oc get certificate -n openshift-ingress)

# Annotate Authorino service for TLS (required once after Authorino operator creates the svc).
oc annotate svc/authorino-authorino-authorization \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
  -n kuadrant-system --overwrite || true

oc apply -k ./overlays/05-authorino/
oc apply -k ./overlays/06-hardware-profile/
oc apply -k ./overlays/07-demo-llm/
oc apply -k ./overlays/08-llm-models/

# --- Verify LLM deployment ---
# Defaults match instances/llm-models/kustomization.yaml (qwen).
# For gpt-oss-20b: LLM_NAME=gpt-oss-20b LLM_MODEL=openai/gpt-oss-20b ./llmd-script.sh
LLM_NAMESPACE="${LLM_NAMESPACE:-demo-llm}"
LLM_NAME="${LLM_NAME:-qwen}"
LLM_MODEL="${LLM_MODEL:-Qwen/Qwen3-0.6B}"
LLM_PORT="${LLM_PORT:-18080}"

echo "Waiting for LLMInferenceService/${LLM_NAME} to become Ready..."
oc wait --for=condition=Ready "llminferenceservice/${LLM_NAME}" -n "${LLM_NAMESPACE}" --timeout=600s

export TEST_TOKEN
TEST_TOKEN="$(oc create token test-user -n "${LLM_NAMESPACE}")"
export LLM_URL="https://127.0.0.1:${LLM_PORT}"

echo "Port-forwarding svc/${LLM_NAME}-kserve-workload-svc to localhost:${LLM_PORT}..."
oc port-forward -n "${LLM_NAMESPACE}" "svc/${LLM_NAME}-kserve-workload-svc" "${LLM_PORT}:8000" &
PF_PID=$!
cleanup() { kill "${PF_PID}" 2>/dev/null || true; }
trap cleanup EXIT
sleep 5

echo "Listing models..."
curl -sk "${LLM_URL}/v1/models" \
  -H "Authorization: Bearer ${TEST_TOKEN}"
echo

echo "Running completion test..."
curl -sk "${LLM_URL}/v1/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEST_TOKEN}" \
  -d "{
    \"model\": \"${LLM_MODEL}\",
    \"prompt\": \"what is the capital of France?\"
  }"
echo


#update guidellm-benchmark-job.yaml with the correct LLM_URL and LLM_MODEL

oc apply -k ./overlays/09-guidellm-benchmark/

oc logs -n demo-llm job/guidellm-benchmark -f