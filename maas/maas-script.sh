followed ./ocp-gpu-setup/README.md

cd rhoai3

oc apply -k ./maas/base/operators/servicemesh/
oc apply -k ./maas/base/instances/servicemesh/

#check if  (oc get OperatorGroup -n cert-manager-operator) already there
#then delete the group (oc delete OperatorGroup cert-manager-operator-og -n cert-manager-operator)

# Phase 1: operators (OSM 3.2 before RHCL)
oc apply -k ./maas/overlays/01-operators/

#approve installplan for rhcl-operator.v1.3.3
#oc get installplan -n rh-connectivity-link 
#oc patch installplan install-7bmx9 -n rh-connectivity-link \
#  --type merge -p '{"spec":{"approved":true}}'


oc apply -k ./maas/overlays/02-operator-instances/

# Phase 3: gateway — update hostname in maas-default-gateway.yaml before applying
oc apply -k ./maas/overlays/03-gateway/


# Authorino must trust the OpenShift service CA for outbound HTTPS to maas-api
oc set env deployment/authorino -n rh-connectivity-link \
  SSL_CERT_FILE=/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt \
  REQUESTS_CA_BUNDLE=/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt

oc rollout status deployment/authorino -n rh-connectivity-link --timeout=120s

oc patch networkpolicy maas-authorino-allow -n redhat-ods-applications --type='json' -p='[{"op": "replace", "path": "/spec/ingress/0/from/0/namespaceSelector/matchExpressions/0/values", "value": ["rh-connectivity-link", "kuadrant-system", "openshift-operators"]}]'

oc apply -k ./maas/overlays/04-postgres/
oc apply -k ./maas/overlays/05-rhoai/
oc apply -k ./maas/overlays/07-odhdashboard/


oc apply -k ./maas/overlays/08-simulated-models/
oc apply -k ./maas/overlays/08-external-models/
oc apply -k ./maas/overlays/09-maas-subscriptions/
oc apply -k ./maas/overlays/10-observability-dashboard-rhoai/

#approve the installplan for cluster-observability-operator.v1.4.0
#oc get installplan -n openshift-cluster-observability-operator
#oc patch installplan install-cmp68 -n openshift-cluster-observability-operator \
#  --type merge -p '{"spec":{"approved":true}}'

# MaaS usage metrics: TelemetryPolicy labels + Limitador scrape for Usage dashboard
# Apply after observability platform (overlay 10) and MaaS subscriptions (overlay 09)
oc apply -k ./maas/overlays/11-maas-observability/

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
oc get kuadrant -n rh-connectivity-link
oc get maassubscription -A
oc get externalmodel,maasmodelref -n ai-models
oc get httproute,serviceentry,destinationrule -n ai-models
oc get telemetrypolicy -n openshift-ingress
oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}{"\n"}'
oc get pods -n openshift-user-workload-monitoring
oc get podmonitor,servicemonitor -n rh-connectivity-link | grep -iE 'limitador|kuadrant|authorino' || true
oc get kuadrant kuadrant -n rh-connectivity-link -o jsonpath='observability.enable={.spec.observability.enable}{"\n"}'
# Usage dashboard queries cluster Thanos (NOT data-science-monitoringstack Prometheus):
# oc run curl-thanos --rm -i --restart=Never --image=curlimages/curl -- \
#   curl -s "http://thanos-querier.openshift-monitoring.svc:9091/api/v1/query?query=authorized_hits"


#clean up:

oc delete -k ./maas/overlays/11-maas-observability/
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


oc port-forward -n openshift-ingress svc/maas-default-gateway-openshift-default 18080:80

export GATEWAY_HOST="maas.apps.cluster-prdfw.prdfw.sandbox2719.opentlc.com"
export HOST="http://127.0.0.1:18080"

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


#Inference Model

curl -sS -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"facebook/opt-125m","messages":[{"role":"user","content":"Hello"}]}' \
  "${HOST}/ai-models/simulated-free/v1/chat/completions" | jq .

#Inference External Model

curl -sS -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"llama-scout-17b","messages":[{"role":"user","content":"Hello"}]}' \
  "${HOST}/ai-models/my-external-model/v1/chat/completions" | jq .
