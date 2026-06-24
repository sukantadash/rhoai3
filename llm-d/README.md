# llm-d Model Cluster Deployment

Deploy a GPU-backed **llm-d** inference stack on OpenShift using kustomize overlays and `llmd-script.sh`. This cluster runs `LLMInferenceService` workloads (vLLM + llm-d router) behind an inference gateway with RHOAI, Service Mesh, and Red Hat Connectivity Link (RHCL/Kuadrant).

For multi-cluster topology with MaaS, see [../maas/architecture/maas.md](../maas/architecture/maas.md).

## Prerequisites

| Requirement | Notes |
|---|---|
| OpenShift cluster | OLM enabled; logged in with `oc` |
| GPU worker nodes | Provision per [../../ocp-gpu-setup/README.md](../../ocp-gpu-setup/README.md) step 1 |
| cert-manager Operator | Required for gateway TLS (`oc get clusterissuer`) |
| `ghcr-pull-secret` | In `demo-llm` namespace for GuideLLM image (if running benchmark overlay) |

## Quick start

```bash
cd rhoai3/llm-d

# 1. Edit cluster-specific values (see Configuration below)
# 2. Run the full deployment
./llmd-script.sh
```

## Configuration (before running)

Update these files for your cluster:

| File | What to change |
|---|---|
| `instances/gateway/gateway.yaml` | `hostname` and allowed namespace list under `listeners` |
| `instances/gateway/tlspolicy.yaml` | `issuerRef.name` — must match an existing ClusterIssuer |
| `instances/guidellm-benchmark/guidellm-benchmark-job.yaml` | `GUIDELLM_TARGET` URL and model (if using overlay 09) |

Verify your ClusterIssuer:

```bash
oc get clusterissuer
```

## Deployment phases

`llmd-script.sh` applies overlays in order and waits at critical points.

| Overlay | Purpose |
|---|---|
| `00-gpu-operators` | NFD + NVIDIA GPU Operator subscriptions |
| `00-gpu-instances` | NFD + GPU Operator CRs (cluster policy, driver) |
| `01-operators` | Service Mesh, RHCL, Leader Worker Set, RHOAI operator |
| `02-operator-instances` | Service Mesh, Kuadrant, Leader Worker Set instances |
| `03-rhoai` | DSCInitialization + DataScienceCluster |
| `03-rhoai-dashboard` | OdhDashboardConfig (after DSC is Ready) |
| `04-gateway` | GatewayClass, Gateway, TLSPolicy |
| `05-authorino` | Authorino CR for gateway auth |
| `06-hardware-profile` | GPU hardware profile for model scheduling |
| `07-demo-llm` | `demo-llm` namespace + `test-user` ServiceAccount/RBAC |
| `08-llm-models` | LLMInferenceService deployment (default: qwen) |
| `09-guidellm-benchmark` | GuideLLM throughput benchmark Job |

### RHOAI two-stage apply

`OdhDashboardConfig` CRD is created only after the DataScienceCluster reconciles. The script applies `03-rhoai` first, waits for DSC/DSCI Ready, waits for the CRD, then applies `03-rhoai-dashboard`. Do not combine these into a single apply on a fresh install.

## Model selection

Default model is **Qwen/Qwen3-0.6B** (`instances/llm-models/qwen-llm-infra.yaml`).

To deploy a different model, edit `instances/llm-models/kustomization.yaml` (uncomment the desired resource) and set environment variables when running the script:

```bash
# gpt-oss-20b example
LLM_NAME=gpt-oss-20b LLM_MODEL=openai/gpt-oss-20b ./llmd-script.sh
```

| Variable | Default | Description |
|---|---|---|
| `LLM_NAMESPACE` | `demo-llm` | Namespace for the LLMInferenceService |
| `LLM_NAME` | `qwen` | LLMInferenceService metadata name |
| `LLM_MODEL` | `Qwen/Qwen3-0.6B` | Model ID used in completion test |
| `LLM_PORT` | `18080` | Local port-forward port |

## Manual overlay apply

Run overlays individually from `rhoai3/llm-d/`:

```bash
oc apply -k ./overlays/00-gpu-operators/
oc wait --for=condition=Available subscription/nfd -n openshift-nfd --timeout=600s
oc wait --for=condition=Available subscription/gpu-operator-certified -n nvidia-gpu-operator --timeout=600s
oc apply -k ./overlays/00-gpu-instances/
# ... continue through 09
```

## Verification

### GPU

```bash
oc get nodes -l nvidia.com/gpu.present=true
oc get pods -n nvidia-gpu-operator
```

### RHOAI

```bash
oc get csv -n redhat-ods-operator | grep rhods-operator
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}{"\n"}'
```

### Gateway TLS

```bash
oc get certificate -n openshift-ingress
oc get gateway openshift-ai-inference -n openshift-ingress
```

### LLM inference

The script port-forwards the workload service and runs smoke tests. To test manually:

```bash
export TEST_TOKEN=$(oc create token test-user -n demo-llm)
oc port-forward -n demo-llm svc/qwen-kserve-workload-svc 18080:8000

curl -sk https://127.0.0.1:18080/v1/models \
  -H "Authorization: Bearer ${TEST_TOKEN}"
```

### Gateway endpoint

```bash
export TEST_TOKEN=$(oc create token test-user -n demo-llm)
curl -sk "https://<gateway-hostname>/demo-llm/qwen/v1/models" \
  -H "Authorization: Bearer ${TEST_TOKEN}"
```

Replace `<gateway-hostname>` with the value from `instances/gateway/gateway.yaml`.

### GuideLLM benchmark

```bash
oc logs -n demo-llm job/guidellm-benchmark -f
```

Re-run after config changes:

```bash
oc delete job guidellm-benchmark -n demo-llm --ignore-not-found
oc apply -k ./overlays/09-guidellm-benchmark/
```

## Troubleshooting

**`OdhDashboardConfig` CRD not found** — DSC is not Ready yet. Wait and apply dashboard overlay separately:

```bash
oc wait --for=jsonpath='{.status.phase}'=Ready datasciencecluster/default-dsc --timeout=600s
oc wait --for=condition=Established crd/odhdashboardconfigs.opendatahub.io --timeout=600s
oc apply -k ./overlays/03-rhoai-dashboard/
```

**InstallPlan requires manual approval** — Some operators need an explicit patch. Uncomment and adapt the installplan block in `llmd-script.sh` for your cluster.

**GuideLLM `ThroughputProfile requires a rate parameter`** — GuideLLM ≥0.5 requires `GUIDELLM_RATE` when using the `throughput` profile. This is already set in `guidellm-benchmark-job.yaml`.

**Certificate not issued** — Confirm TLSPolicy issuer matches `oc get clusterissuer` and allow up to 5 minutes for cert-manager to reconcile.

## Directory layout

```
llm-d/
├── llmd-script.sh          # Main deployment script
├── operators/              # Operator subscriptions (NFD, GPU, SM, RHCL, LWS, RHOAI)
├── instances/              # CRs and workload manifests
│   ├── gateway/            # Inference gateway + TLS
│   ├── rhoai/              # DSC + DSCI
│   ├── rhoai-dashboard/    # OdhDashboardConfig
│   ├── llm-models/         # LLMInferenceService definitions
│   └── guidellm-benchmark/ # Benchmark Job
└── overlays/               # Ordered kustomize overlays (00–09)
```
