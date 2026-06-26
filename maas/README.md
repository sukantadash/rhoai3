# MaaS Control-Plane Deployment

Deploy a **Models-as-a-Service (MaaS)** control-plane cluster on OpenShift using kustomize overlays and `maas-script.sh`. This cluster exposes a unified API gateway for model catalog, API keys, subscriptions, rate limiting, and routing to simulated or external models.

| Architecture guide | Description |
|---------------------|-------------|
| [architecture/multicluster-maas-llmd.md](architecture/multicluster-maas-llmd.md) | **PoC:** MaaS on CPU cluster + remote llm-d on GPU cluster (overlays 12–13, Route vs MetalLB) |
| [architecture/maas.md](architecture/maas.md) | **HA:** MaaS + multiple GPU clusters behind a shared load balancer |

## Prerequisites

| Requirement | Notes |
|---|---|
| OpenShift cluster | OCP 4.19.9+ recommended; OSM 3.2 / RHCL 1.4 |
| GPU setup (optional on MaaS cluster) | Overlay 01 includes NFD + GPU operators; MaaS itself does not run inference pods |
| cert-manager Operator | Installed via overlay 01; required for gateway TLS |
| Cluster admin `oc` access | Some steps patch NetworkPolicy and Authorino deployment |

## Quick start

`maas-script.sh` is a **phased runbook** — run commands section by section from the `rhoai3` directory. It is not a single executable script (no shebang); copy/paste or run each phase manually.

```bash
cd rhoai3

# 1. Edit cluster-specific values (see Configuration below)
# 2. Follow maas-script.sh phases in order
```

## Configuration (before running)

Update hostnames and cluster-specific values:

| File | What to change |
|---|---|
| `base/instances/gateway/maas-default-gateway.yaml` | `hostname` for HTTP and HTTPS listeners |
| Test commands in `maas-script.sh` | `GATEWAY_HOST` to match your gateway hostname |

Example hostname pattern: `maas.apps.<cluster>.<domain>`

## Deployment phases

### Phase 0 — Service Mesh bootstrap

Applied before overlay 01 (from `rhoai3/`):

```bash
oc apply -k ./maas/base/operators/servicemesh/
oc apply -k ./maas/base/instances/servicemesh/
```

### Phase 1 — Operators (`overlays/01-operators`)

Installs NFD, NVIDIA GPU Operator, cert-manager, RHCL, Leader Worker Set, and RHOAI.

```bash
oc apply -k ./maas/overlays/01-operators/
```

If cert-manager OperatorGroup already exists from a prior install, delete the conflicting group before applying (see comment in `maas-script.sh`).

### Phase 2 — Operator instances (`overlays/02-operator-instances`)

Service Mesh, Kuadrant, and Leader Worker Set instances.

```bash
oc apply -k ./maas/overlays/02-operator-instances/
```

Some clusters require manual InstallPlan approval for RHCL:

```bash
oc get installplan -n kuadrant-system
oc patch installplan <name> -n kuadrant-system \
  --type merge -p '{"spec":{"approved":true}}'
```

### Phase 3 — Gateway (`overlays/03-gateway`)

MaaS default gateway (GatewayClass, Gateway, TLSPolicy).

```bash
oc apply -k ./maas/overlays/03-gateway/
oc get gateway maas-default-gateway -n openshift-ingress
```

### Phase 3b — Authorino TLS + NetworkPolicy

Required so Authorino trusts the OpenShift service CA when calling `maas-api`:

```bash
oc set env deployment/authorino -n kuadrant-system \
  SSL_CERT_FILE=/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt \
  REQUESTS_CA_BUNDLE=/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt

oc rollout status deployment/authorino -n kuadrant-system --timeout=120s

oc patch networkpolicy maas-authorino-allow -n redhat-ods-applications --type='json' \
  -p='[{"op": "replace", "path": "/spec/ingress/0/from/0/namespaceSelector/matchExpressions/0/values", "value": ["kuadrant-system", "openshift-operators"]}]'
```

### Phase 4 — Platform (`overlays/04`–`07`)

| Overlay | Purpose |
|---|---|
| `04-postgres` | PostgreSQL for MaaS API |
| `05-rhoai` | DataScienceCluster (MaaS components enabled) |
| `07-odhdashboard` | OdhDashboardConfig (apply after DSC is Ready) |

```bash
oc apply -k ./maas/overlays/04-postgres/
oc apply -k ./maas/overlays/05-rhoai/
# Wait for DSC Ready before dashboard
oc wait --for=jsonpath='{.status.phase}'=Ready datasciencecluster/default-dsc --timeout=600s
oc apply -k ./maas/overlays/07-odhdashboard/
```

### Phase 5 — Models (`overlays/08`)

```bash
oc apply -k ./maas/overlays/08-simulated-models/
oc apply -k ./maas/overlays/08-external-models/
```

Simulated models are for local testing. External models register remote endpoints (e.g. llm-d clusters behind a load balancer).

### Phase 6 — Subscriptions and observability (`overlays/09`–`11`)

```bash
oc apply -k ./maas/overlays/09-maas-subscriptions/
oc apply -k ./maas/overlays/10-observability-dashboard-rhoai/
oc apply -k ./maas/overlays/11-maas-telemetry/
```

Overlay `11-maas-telemetry` enables operator-managed observability via the Tenant CR ([MaaS observability setup — Option 1](https://opendatahub-io.github.io/models-as-a-service/dev/observability/setup/)). The operator creates `maas-telemetry` and `latency-per-subscription`.

If migrating from the old manual TelemetryPolicy overlay, delete the previous resources first:

```bash
oc delete telemetrypolicy maas-usage-telemetry -n openshift-ingress --ignore-not-found
oc delete telemetry maas-gateway-latency-per-tier -n openshift-ingress --ignore-not-found
```

Cluster Observability Operator may require manual InstallPlan approval (see comments in `maas-script.sh`).

## Verification

`maas-script.sh` includes a verification block. Key checks:

```bash
oc get csv -n openshift-operators -l operators.coreos.com/operator.servicemeshoperator3
oc get gateway maas-default-gateway -n openshift-ingress
oc get kuadrant -n kuadrant-system
oc get maassubscription -A
oc get externalmodel,maasmodelref -n ai-models
oc get tenant default-tenant -n models-as-a-service
oc get telemetrypolicy maas-telemetry -n openshift-ingress
oc get telemetry latency-per-subscription -n openshift-ingress
```

## Testing inference

Port-forward the gateway and use the cluster hostname in the `Host` header:

```bash
oc port-forward -n openshift-ingress svc/maas-default-gateway-openshift-default 18080:80

export GATEWAY_HOST="maas.apps.<cluster>.<domain>"
export HOST="http://127.0.0.1:18080"

# List models
curl -sS -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  "${HOST}/v1/models" | jq .

# Create API key
API_KEY=$(curl -sS \
  -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"name": "test-key", "expiration": "1h"}' \
  "${HOST}/maas-api/v1/api-keys" | jq -r .key)

# Simulated model
curl -sS -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"simulated-free","messages":[{"role":"user","content":"What is the capital of France?"}]}' \
  "${HOST}/ai-models/simulated-free/v1/chat/completions" | jq .

# External model
curl -sS -H "Host: ${GATEWAY_HOST}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"llama-scout-17b","messages":[{"role":"user","content":"What is the capital of India?"}]}' \
  "${HOST}/ai-models/my-external-model/v1/chat/completions" | jq .
```

## Cleanup

`maas-script.sh` includes teardown commands (reverse overlay order):

```bash
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
```

## Connecting llm-d model clusters

Register llm-d inference endpoints as `ExternalModel` resources in `base/instances/external-ai-models/`. The MaaS gateway routes consumer traffic through Authorino and Limitador before forwarding to the external endpoint. See [architecture/maas.md](architecture/maas.md) for the full request flow.

Deploy model clusters with [../llm-d/README.md](../llm-d/README.md).

## Troubleshooting

**RHCL InstallPlan pending** — Approve manually (see Phase 2).

**Authorino cannot reach maas-api** — Confirm the TLS env vars and NetworkPolicy patch in Phase 3b.

**OdhDashboardConfig fails on first apply** — Wait for `datasciencecluster/default-dsc` Ready, then apply overlay 07 separately.

**Gateway not programmed** — Check TLSPolicy, cert-manager Certificate in `openshift-ingress`, and RHCL operator health.

**Usage dashboard empty** — MaaS observability metrics flow through cluster Thanos, not the data-science monitoring stack. See verification comments in `maas-script.sh`.

## Directory layout

```
maas/
├── maas-script.sh              # Phased deployment runbook
├── architecture/maas.md        # Multi-cluster topology
├── base/
│   ├── operators/              # Operator subscriptions
│   └── instances/              # Gateway, RHOAI, models, observability CRs
└── overlays/                   # Ordered kustomize overlays (01–11)
```
