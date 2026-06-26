followed ./ocp-gpu-setup/README.md

cd rhoai3

oc apply -k ./maas/base/operators/servicemesh/
oc apply -k ./maas/base/instances/servicemesh/

#check if  (oc get OperatorGroup -n cert-manager-operator) already there
#then delete the group (oc delete OperatorGroup cert-manager-operator-og -n cert-manager-operator)

# Phase 1: operators (OSM 3.2 before RHCL)
oc apply -k ./maas/overlays/01-operators/

#approve installplan for rhcl-operator.v1.3.3
#oc get installplan -n kuadrant-system 
#oc patch installplan install-m2wm7 -n kuadrant-system \
#  --type merge -p '{"spec":{"approved":true}}'


oc apply -k ./maas/overlays/02-operator-instances/


# Phase 3: gateway — update hostname in maas-default-gateway.yaml before applying
oc apply -k ./maas/overlays/03-gateway/
#oc get gateway -n openshift-ingress

# Authorino must trust the OpenShift service CA for outbound HTTPS to maas-api
oc set env deployment/authorino -n kuadrant-system \
  SSL_CERT_FILE=/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt \
  REQUESTS_CA_BUNDLE=/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt

oc rollout status deployment/authorino -n kuadrant-system --timeout=120s

oc patch networkpolicy maas-authorino-allow -n redhat-ods-applications --type='json' -p='[{"op": "replace", "path": "/spec/ingress/0/from/0/namespaceSelector/matchExpressions/0/values", "value": ["kuadrant-system", "openshift-operators"]}]'


oc apply -k ./maas/overlays/04-postgres/
oc apply -k ./maas/overlays/05-rhoai/
oc apply -k ./maas/overlays/07-odhdashboard/


oc apply -k ./maas/overlays/08-simulated-models/
oc apply -k ./maas/overlays/08-external-models/
oc apply -k ./maas/overlays/09-maas-subscriptions/
oc apply -k ./maas/overlays/10-observability-dashboard-rhoai/
oc apply -k ./maas/overlays/11-maas-telemetry/

#approve the installplan for cluster-observability-operator.v1.4.0
#oc get installplan -n openshift-cluster-observability-operator
#oc patch installplan install-chmct -n openshift-cluster-observability-operator \
#  --type merge -p '{"spec":{"approved":true}}'




# Verification
echo "--- Verification ---"
oc get csv -n openshift-operators -l operators.coreos.com/operator.servicemeshoperator3 \
  -o custom-columns=NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase
oc get istio default -n istio-system \
  -o custom-columns=NAME:.metadata.name,VERSION:.spec.version,IN_USE:.status.revisions.inUse
oc get istio openshift-gateway -n openshift-ingress \
  -o custom-columns=NAME:.metadata.name,VERSION:.spec.version,NOTE:.metadata.name
oc get pods -n openshift-ingress -l 'gateway.networking.k8s.io/gateway-name in (maas-default-gateway-istio,data-science-gateway-data-science-gateway-class)'

oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'

oc get kuadrant -n kuadrant-system
oc get maassubscription -A
oc get externalmodel,maasmodelref -n ai-models
oc get httproute,serviceentry,destinationrule -n ai-models
oc get tenant default-tenant -n models-as-a-service -o jsonpath='telemetry.enabled={.spec.telemetry.enabled}{"\n"}'
oc get telemetrypolicy maas-telemetry -n openshift-ingress
oc get telemetry latency-per-subscription -n openshift-ingress
oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}{"\n"}'
oc get pods -n openshift-user-workload-monitoring
oc get podmonitor,servicemonitor -n kuadrant-system | grep -iE 'limitador|kuadrant|authorino' || true
oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='observability.enable={.spec.observability.enable}{"\n"}'
# Usage dashboard queries cluster Thanos (NOT data-science-monitoringstack Prometheus):
# oc run curl-thanos --rm -i --restart=Never --image=curlimages/curl -- \
#   curl -s "http://thanos-querier.openshift-monitoring.svc:9091/api/v1/query?query=authorized_hits"


#clean up:

oc delete -k ./maas/overlays/11-maas-telemetry/
oc delete -k ./maas/overlays/10-observability-dashboard-rhoai/
oc delete -k ./maas/overlays/09-maas-subscriptions/
oc delete -k ./maas/overlays/08-external-models/
oc delete -k ./maas/overlays/08-simulated-models/
oc delete -k ./maas/overlays/07-odhdashboard/
oc delete -k ./maas/overlays/05-rhoai/
oc delete -k ./maas/overlays/04-postgres/
oc delete -k ./maas/overlays/03-gateway/
oc delete -k ./maas/overlays/02-operator-instances/
oc delete -k ./maas/overlays/01-operators/


#test:


export GATEWAY_HOST=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
export HOST="https://${GATEWAY_HOST}"

#list models:
curl -sS -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  "${HOST}/v1/models" | jq .

#Create API Key

API_KEY=$(curl -sS \
  -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"name": "test-key", "expiration": "1h"}' \
  "${HOST}/maas-api/v1/api-keys" | jq -r .key)
echo "${API_KEY:0:30}..."



curl -sS -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"simulated-free","messages":[{"role":"user","content":"What is the capital of France?"}]}' \
  "${HOST}/ai-models/simulated-free/v1/chat/completions" | jq .

#Inference External Model

curl -sS -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"llama-scout-17b","messages":[{"role":"user","content":"What is the capital of India?"}]}' \
  "${HOST}/ai-models/my-external-model/v1/chat/completions" | jq .





#maas to access models from external clusters ---------

# Login to llm-d cluster; deploy qwen per llmd-script.sh.

# Update placeholders in base/instances/reverse-proxy-llminference/configmap-nginx.yaml
# and route.yaml (<cluster-domain>, <llm-namespace>, <llm-name>) using DOMAIN below, then apply:

DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')
UPSTREAM_HOST="inference-gateway.${DOMAIN}"
PROXY_HOST="qwen-maas.${DOMAIN}"
echo "DOMAIN=$DOMAIN"
echo "UPSTREAM_HOST=$UPSTREAM_HOST"
echo "PROXY_HOST=$PROXY_HOST"

oc apply -k ./maas/overlays/13-reverse-proxy-llminference/
oc rollout status deployment/qwen-maas-proxy -n qwen-maas-proxy --timeout=120s

# verification reverse-proxy to access the model from external cluster

export TEST_TOKEN="$(oc create token test-user -n demo-llm)"
echo "TEST_TOKEN=$TEST_TOKEN"
echo "PROXY_HOST=$PROXY_HOST"

# Must be 200 — this is what MaaS/BBR will hit
curl -sS -w "\nHTTP:%{http_code}\n" \
  "https://${PROXY_HOST}/v1/chat/completions" \
  -H "Authorization: Bearer ${TEST_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen3-0.6B","messages":[{"role":"user","content":"What is the capital of France?"}]}'

# Streaming check (optional)
curl -sS -N -w "\nHTTP:%{http_code}\n" \
  "https://${PROXY_HOST}/v1/chat/completions" \
  -H "Authorization: Bearer ${TEST_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen3-0.6B","messages":[{"role":"user","content":"Count to 5"}],"stream":true}'


# Login to MaaS cluster, then register remote llm-d model (see base/instances/external-cluster-llminference/).
# Update qwen-remote-external-model.yaml endpoint if PROXY_HOST differs from the llm-d cluster domain.
#update the secret with the token TEST_TOKEN from the llm-d cluster (export TEST_TOKEN="$(oc create token test-user -n demo-llm)")

oc apply -k ./maas/overlays/12-external-cluster-llminference/


#verification: maas url to access the external cluster model

MAAS_DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')
MAAS_HOST="maas.${MAAS_DOMAIN}"
echo "MAAS_HOST=$MAAS_HOST"

# Create MaaS API key
API_KEY=$(curl -sS -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" -X POST \
  -d '{"name":"qwen-remote-test","expiration":"1h"}' \
  "https://${MAAS_HOST}/maas-api/v1/api-keys" | jq -r .key)
echo "${API_KEY:0:30}..."


# Inference through MaaS → ExternalModel → llm-d cluster
curl -sS "https://${MAAS_HOST}/ai-models/qwen-remote/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen3-0.6B","messages":[{"role":"user","content":"What is the capital of France?"}]}' | jq .

