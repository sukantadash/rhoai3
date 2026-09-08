# llm-d Feature Validation Test Plan

Performance validation of llm-d features using **GuideLLM** for traffic generation and **Prometheus/Grafana** for observability.

Aligned with the [RHOAI 3.5 Deploy models using Distributed Inference with llm-d guide](docs/Red_Hat_OpenShift_AI_Self-Managed-3.5-Deploy_models_using_Distributed_Inference_with_llm-d-en-US.pdf) ([online PDF](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/pdf/deploy_models_using_distributed_inference_with_llm-d/Red_Hat_OpenShift_AI_Self-Managed-3.5-Deploy_models_using_Distributed_Inference_with_llm-d-en-US.pdf)).

## Standard Model

All scenarios deploy the same model (RHOAI 3.5 guide Ch.1 example):

| Field | Value |
| --- | --- |
| `spec.model.uri` | `hf://RedHatAI/Qwen3-8B-FP8-dynamic` |
| `spec.model.name` | `RedHatAI/Qwen3-8B-FP8-dynamic` |
| GPU memory (per replica) | 32Gi limit / 16Gi request |
| GPUs per replica | 1 |

GuideLLM jobs resolve the model via `common/env.sh` (`LLM_MODEL` defaults to the same value).

## Feature Coverage & References

| PDF chapter | Feature | Test coverage |
| --- | --- | --- |
| 1.1 | Default `LLMInferenceService` deployment (no custom scheduler) | **00** |
| 5.6.3 / 6.x / 10.x | Intelligent scheduler + KV cache routing | **01a**, **01b**, **01c**, **01d**, **02a**, **04a** |
| 7.x | Flow control / priority queuing | **deferred/07A** |
| 8.x | Batch inference (`/v1/batches`) | **deferred/05B** |
| 9.x | Workload Variant Autoscaler (WVA) | **deferred/05A** |
| 5.6.2 / 9.7 | Multi-node LWS + large-model parallelism | **deferred/04B** |
| 10.x plugins | `latency-scorer` + `predicted-latency-producer` | **deferred/01E** |
| RHOAI Inference 3.5 Ch.3 | WideEP / DP-aware rank-level routing | **deferred/04D** |
| WVA 9.3.2 / observability 10.x | Prefill/decode disaggregation + NIXL KV transfer | **03a**, **03b**, **03c** |

**Technology Preview** (per RHOAI 3.5 guide — not production-ready on OCP):

- Prefill/decode disaggregation (Tests 03a–03c)
- Batch inference (deferred 05B)
- Flow control / priority queuing (deferred 07A)

Grafana panels referenced below come from [`../instances/llm-d-monitoring/grafana-dashboard-llm-performance.json`](../instances/llm-d-monitoring/grafana-dashboard-llm-performance.json).

## Prerequisites

1. Base cluster deployed via [`../llmd-script.sh`](../llmd-script.sh) (GPU operators, RHOAI, gateway, `demo-llm` namespace, `test-user` RBAC).
2. Monitoring overlay applied: `oc apply -k ../overlays/09-llm-d-monitoring/`
3. `ghcr-pull-secret` in `demo-llm` namespace (for GuideLLM image).
4. Logged in to cluster: `oc whoami`
5. GPU capacity per scenario (see table below). Each 8B replica needs 1 GPU with ≥32Gi memory.

## How to Run

```bash
cd rhoai3/llm-d/test

./test-script.sh setup
./test-script.sh run 00-baseline
./test-script.sh run-all
./test-script.sh run-all --cleanup
```

Results are saved to `<scenario>/results/` (`benchmark.json`, `benchmark.csv`, `run-metadata.txt`).

Open Grafana and set the time range to `start_time` / `end_time` from `run-metadata.txt`:

```bash
oc get route grafana-secure -n llm-d-monitoring -o jsonpath='{.spec.host}'
```

## Run Order & Deploy Reuse

`./test-script.sh run-all` order (from `common/env.sh`):

```
00 → 01a → 01c → 01d → 01b → 02a → 03a → 03b → 03c → 04a
```

| Scenario | Deploy? | Prerequisite |
| --- | --- | --- |
| 01c | No | 01a `qwen` deployment still running |
| 03b, 03c | No | 03a `qwen-pd` deployment still running |
| All others | Yes | Conflicting service torn down by `test-script.sh` |

## Scenario Summary

| ID | Scenario | Feature under test | GPUs | Service | Deploy? |
| --- | --- | --- | --- | --- | --- |
| 00 | `00-baseline` | Default deployment (no custom llm-d config) | 2 | `qwen` | Yes |
| 01a | `01a-prefix-cache-routing` | Prefix-cache aware routing (`prefix-cache-scorer`) | 2 | `qwen` | Yes |
| 01b | `01b-precise-prefix-cache-routing` | Precise prefix-cache routing | 2 | `qwen` | Yes |
| 01c | `01c-queue-kv-scheduling` | Queue + KV utilization scorers | 2 | `qwen` | No (reuses 01a) |
| 01d | `01d-round-robin-control` | Round-robin control (A/B vs 01a) | 2 | `qwen` | Yes |
| 02a | `02a-global-cache-indexing` | Global cache indexing | 2 | `qwen` | Yes |
| 03a | `03a-pd-separation` | Prefill/decode separation | 2 | `qwen-pd` | Yes |
| 03b | `03b-pd-kv-transfer` | KV direct transfer (NIXL) | 2 | `qwen-pd` | No (reuses 03a) |
| 03c | `03c-heterogeneous-pd` | Heterogeneous P/D workload | 2 | `qwen-pd` | No (reuses 03a) |
| 04a | `04a-data-parallelism` | 4-replica throughput scaling | 4 | `qwen` | Yes |

`prompt.txt` templates exist for **00**, **01a**, and **01b**. Use the [Results Template](#results-template) for other scenarios.

## Manifest & GuideLLM Reference

Each scenario directory contains the authoritative manifests. The table below is the verification checklist against this test plan.

| ID | `llminferenceservice.yaml` | `guidellm-job.yaml` | Deploy? |
| --- | --- | --- | --- |
| 00 | Default `router.scheduler: {}`, 8B model, 2 replicas | `throughput`, concurrency=20, 100/50 tokens, 60s | Yes |
| 01a | `prefix-cache-scorer` (3) + queue/kv/lru (2), `--enable-prefix-caching` | `constant`, rate=5, 1×2048 prefix, 120s | Yes |
| 01b | `precise-prefix-cache-scorer` (3) + queue/kv/lru (2), `--enable-prefix-caching` | Same as 01a | Yes |
| 01c | Reference copy of 01a (not deployed) | `concurrent`, streams=80, same prefix as 01a, 120s | No |
| 01d | `random-picker` only, no `VLLM_ADDITIONAL_ARGS` | Same traffic as 01a | Yes |
| 02a | queue/kv (2) + `precise-prefix-cache-scorer` (3), `--enable-prefix-caching` | `sweep`, 50×1024 prefixes, 180s | Yes |
| 03a | `qwen-pd`, P/D + NixlConnector, 8B model | `sweep`, 1024/1024 tokens, 120s | Yes |
| 03b | Reference copy of 03a (not deployed) | `concurrent`, streams=50, 1024/1024, 120s | No |
| 03c | Reference copy of 03a (not deployed) | `sweep`, mixed 256/512/1024 buckets, 180s | No |
| 04a | 4 replicas, queue/kv (2) + `precise-prefix-cache-scorer` (3) | `throughput`, concurrency=40, 100/50 tokens, 120s | Yes |

---

## Test 00 — Default Baseline (No Custom llm-d Config)

**Objective:** Establish baseline TTFT, ITL, RPS, and TPS using a standard `LLMInferenceService` before enabling feature-specific scheduler configuration. This is the RHOAI 3.5 Ch.1 default deployment pattern.

**PDF reference:** Ch.1.1 — `router.route`, `router.gateway`, and `router.scheduler` left empty; no inline `EndpointPickerConfig`.

**Deployment:** `RedHatAI/Qwen3-8B-FP8-dynamic`, 2 replicas. Manifest: [`00-baseline/llminferenceservice.yaml`](00-baseline/llminferenceservice.yaml).

```yaml
router:
  route: {}
  gateway: {}
  scheduler: {}
```

No custom EPP plugins are declared. RHOAI applies the platform default 4-scorer profile (`queue-scorer`, `kv-cache-utilization-scorer`, `prefix-cache-scorer`, `no-hit-lru-scorer` at weights 2:2:3:2) automatically per Ch.6/10.

**GuideLLM:** Throughput profile, `max_concurrency=20`, random synthetic 100 prompt / 50 output tokens (no shared prefixes), 60s. Manifest: [`00-baseline/guidellm-job.yaml`](00-baseline/guidellm-job.yaml).

**Steps:**

1. `./test-script.sh run 00-baseline`
2. Open Grafana LLM Performance dashboard for the benchmark time window.

**Expected results:**

- Gateway returns HTTP 200; GuideLLM error rate < 1%
- Both `qwen` pods receive traffic
- `up{job="llm-d-epp-metrics"} == 1`
- No `EPPNoReadyPods` alert
- KV cache hit rate ~0% under random traffic with no shared prefixes

**Pass criteria:** Benchmark completes; baseline metrics recorded in `00-baseline/results/benchmark.json`.

---

## Test 01a — Prefix-Cache Aware Routing

**Objective:** Prove EPP routes shared-prefix requests to the pod holding the KV cache using the `prefix-cache-scorer` plugin.

**PDF reference:** Ch.6/10 — prefix-cache-scorer with weights 2:2:3:2 alongside queue, kv-cache-utilization, and no-hit-lru scorers.

**Deployment:** Frozen manifest at [`01a-prefix-cache-routing/llminferenceservice.yaml`](01a-prefix-cache-routing/llminferenceservice.yaml) — do not modify.

| Setting | Value |
| --- | --- |
| Model | `RedHatAI/Qwen3-8B-FP8-dynamic` |
| Replicas | 2 |
| EPP plugins | `queue-scorer` (2), `kv-cache-utilization-scorer` (2), `prefix-cache-scorer` (3), `no-hit-lru-scorer` (2) |
| vLLM | `--enable-prefix-caching` |

**GuideLLM:** Constant rate=5, 1 shared prefix × 2048 tokens, 120s. Manifest: [`01a-prefix-cache-routing/guidellm-job.yaml`](01a-prefix-cache-routing/guidellm-job.yaml).

**Steps:**

1. `./test-script.sh run 01a-prefix-cache-routing`
2. In Grafana, watch **KV Cache Hit Rate**, **Per-Pod Cache Hit Rates**, **Per-Pod GPU Cache Usage**.

**Expected results:**

- Aggregate **KV Cache Hit Rate** high (e.g. >90%) after warmup
- **Per-Pod Cache Hit Rates** skewed: one pod high (e.g. ~97%), the other near **0%**
- Server-side **TTFT P50** drops after initial cold-start spike
- **EPP KV Cache Pool Utilization** rises during the run
- Benchmark completes; GuideLLM error rate < 1%

**Note:** **Per-Pod GPU Cache Usage** may report 0% even when KV cache hits are high; use per-pod cache hit skew as the primary routing signal. Validate TTFT from Grafana **Time to First Token**, not client-side GuideLLM alone.

**Pass criteria:**

- One pod receives >70% of cache hits (dominant pod high, other ~0%)
- Server-side warm TTFT (Grafana) at least 5× faster than the cold-start spike
- EPP KV Cache Pool Utilization rises
- Error rate < 1%

Reference run: [`01a-prefix-cache-routing/results/RESULTS.md`](01a-prefix-cache-routing/results/RESULTS.md).

---

## Test 01b — Precise Prefix-Cache Aware Routing

**Objective:** Compare `precise-prefix-cache-scorer` (token-level matching) against `prefix-cache-scorer` (hash-based) from Test 01a.

**PDF reference:** Ch.10 — precise-prefix-cache-scorer upgrade path; requires UDS Tokenizer sidecar in connected environments.

**Deployment:** `RedHatAI/Qwen3-8B-FP8-dynamic`, 2 replicas. EPP: `precise-prefix-cache-scorer` (3), `no-hit-lru-scorer` (2), `queue-scorer` (2), `kv-cache-utilization-scorer` (2). vLLM: `--enable-prefix-caching`. Manifest: [`01b-precise-prefix-cache-routing/llminferenceservice.yaml`](01b-precise-prefix-cache-routing/llminferenceservice.yaml).

**GuideLLM:** Identical to 01a — constant rate=5, 1 shared prefix × 2048 tokens, 120s. Manifest: [`01b-precise-prefix-cache-routing/guidellm-job.yaml`](01b-precise-prefix-cache-routing/guidellm-job.yaml).

**Steps:**

1. `./test-script.sh run 01b-precise-prefix-cache-routing`
2. Compare Grafana panels and `benchmark.json` against 01a.

**Pass criteria:** Same as 01a. Document any divergence in `01b-precise-prefix-cache-routing/results/RESULTS.md`.

---

## Test 01c — Queue + KV Utilization Scheduling

**Objective:** When the cache-affine pod saturates, EPP spills traffic to the second replica via queue and KV utilization scorers.

**Prerequisite:** Run 01a first; this scenario does not redeploy.

**Deployment:** Reuses 01a (`prefix-cache-scorer`, `--enable-prefix-caching`). Reference manifest: [`01c-queue-kv-scheduling/llminferenceservice.yaml`](01c-queue-kv-scheduling/llminferenceservice.yaml) (identical to 01a; not deployed).

**GuideLLM:** Same prefix data as 01a (50/50 tokens, 1 × 2048-token prefix), `concurrent,streams=80`, 120s. Manifest: [`01c-queue-kv-scheduling/guidellm-job.yaml`](01c-queue-kv-scheduling/guidellm-job.yaml).

**Steps:**

1. `./test-script.sh run 01c-queue-kv-scheduling`
2. Watch **Per-Pod Queue Sizes (EPP View)** and **Request Queue Status**.

**Pass criteria:** Queue depth distributed across both pods; error rate < 1%.

---

## Test 01d — Round-Robin Control (A/B)

**Objective:** Quantify llm-d prefix-cache routing benefit vs naive random balancing on the **same model**.

**Deployment:** `RedHatAI/Qwen3-8B-FP8-dynamic`, 2 replicas. EPP: `random-picker` only. No `VLLM_ADDITIONAL_ARGS` (prefix caching disabled). Manifest: [`01d-round-robin-control/llminferenceservice.yaml`](01d-round-robin-control/llminferenceservice.yaml).

**A/B design:** GuideLLM traffic is identical to 01a. Only the EPP configuration differs:

| | 01a | 01d |
| --- | --- | --- |
| Model | `RedHatAI/Qwen3-8B-FP8-dynamic` | `RedHatAI/Qwen3-8B-FP8-dynamic` |
| EPP | `prefix-cache-scorer` + queue/kv/lru | `random-picker` only |
| Prefix caching | `--enable-prefix-caching` | disabled |

**GuideLLM:** Constant rate=5, 1 shared prefix × 2048 tokens, 120s. Manifest: [`01d-round-robin-control/guidellm-job.yaml`](01d-round-robin-control/guidellm-job.yaml).

**Steps:**

1. `./test-script.sh run 01d-round-robin-control`
2. Compare Grafana **Per-Pod Cache Hit Rates** and server TTFT against 01a.

**Pass criteria:** 01a server-side warm TTFT at least 3× better than 01d; 01a shows stronger per-pod cache hit skew than 01d.

---

## Test 02a — Global Cache Indexing

**Objective:** Validate EPP tracks cache state across the inference pool under many unique prefixes.

**Deployment:** `RedHatAI/Qwen3-8B-FP8-dynamic`, 2 replicas. EPP: `queue-scorer` (2), `kv-cache-utilization-scorer` (2), `precise-prefix-cache-scorer` (3). vLLM: `--enable-prefix-caching`. Manifest: [`02a-global-cache-indexing/llminferenceservice.yaml`](02a-global-cache-indexing/llminferenceservice.yaml).

**GuideLLM:** 50 unique prefixes × 1024 tokens, sweep profile, 180s. Manifest: [`02a-global-cache-indexing/guidellm-job.yaml`](02a-global-cache-indexing/guidellm-job.yaml).

**Steps:**

1. `./test-script.sh run 02a-global-cache-indexing`
2. Watch `inference_pool_average_kv_cache_utilization` and **Per-Pod GPU Cache Usage**.

**Pass criteria:** EPP pool KV metric correlates with per-pod GPU cache growth.

---

## Test 03a — Prefill/Decode Separation

**Objective:** Validate P/D disaggregation with separate prefill and decode pools.

**Technology Preview** on OCP per RHOAI 3.5 guide.

**Deployment:** `qwen-pd`, `RedHatAI/Qwen3-8B-FP8-dynamic`. `pd-profile-handler`, `prefill-filter`, `decode-filter`, NixlConnector (`kv_role: kv_both`). 1 decode + 1 prefill replica. Manifest: [`03a-pd-separation/llminferenceservice.yaml`](03a-pd-separation/llminferenceservice.yaml).

**GuideLLM:** Sweep, 1024 prompt / 1024 output tokens, 120s. Manifest: [`03a-pd-separation/guidellm-job.yaml`](03a-pd-separation/guidellm-job.yaml).

**Steps:**

1. `./test-script.sh run 03a-pd-separation`
2. Check vLLM logs for `kv_transfer_params.do_remote_prefill` / `do_remote_decode`.

**Pass criteria:** Both pools healthy; KV transfer visible in logs.

---

## Test 03b — KV Direct Transfer

**Objective:** Stress KV transfer between prefill and decode under high concurrency.

**Deployment:** Reuses `qwen-pd` from 03a. Reference manifest: [`03b-pd-kv-transfer/llminferenceservice.yaml`](03b-pd-kv-transfer/llminferenceservice.yaml).

**GuideLLM:** 1024/1024 tokens, `concurrent,streams=50`, 120s. Manifest: [`03b-pd-kv-transfer/guidellm-job.yaml`](03b-pd-kv-transfer/guidellm-job.yaml).

**Pass criteria:** Error rate < 1%; both pools remain Ready.

---

## Test 03c — Heterogeneous P/D Workload

**Objective:** Validate P/D under mixed prompt/output sizes.

**Deployment:** Reuses `qwen-pd` from 03a. Reference manifest: [`03c-heterogeneous-pd/llminferenceservice.yaml`](03c-heterogeneous-pd/llminferenceservice.yaml).

**GuideLLM:** Mixed prefix buckets (256/512/1024 tokens, 10 each), sweep, 180s. Manifest: [`03c-heterogeneous-pd/guidellm-job.yaml`](03c-heterogeneous-pd/guidellm-job.yaml).

**Pass criteria:** Benchmark completes; no pod restarts; error rate < 1%.

---

## Test 04a — 4-Replica Throughput Scaling

**Objective:** Validate throughput scaling with 4-replica intelligent routing. This is multi-replica deployment scaling, not vLLM DP mode or WideEP rank routing (see deferred 04D).

**Deployment:** `RedHatAI/Qwen3-8B-FP8-dynamic`, 4 replicas. EPP: `queue-scorer` (2), `kv-cache-utilization-scorer` (2), `precise-prefix-cache-scorer` (3). Requires 4 GPUs. Manifest: [`04a-data-parallelism/llminferenceservice.yaml`](04a-data-parallelism/llminferenceservice.yaml).

**GuideLLM:** Throughput profile, `max_concurrency=40`, random 100/50 tokens (same pattern as 00), 120s. Manifest: [`04a-data-parallelism/guidellm-job.yaml`](04a-data-parallelism/guidellm-job.yaml).

**Steps:**

1. `./test-script.sh run 04a-data-parallelism`
2. Verify `inference_pool_ready_pods == 4` in Grafana.
3. Compare RPS against Test 00 (concurrency 40 vs 20).

**Pass criteria:** 4 ready pods; RPS roughly 1.5–2× baseline (Test 00).

---

## Deferred Scenarios

See [`deferred/README.md`](deferred/README.md):

- **01E** — Predicted latency routing (`latency-scorer`)
- **02B** — Hierarchical KV offloading
- **04B** — Multi-node LWS + TP/EP
- **04C** — LoRA adapters
- **04D** — WideEP / DP-aware rank routing
- **05A** — Workload Variant Autoscaler
- **05B** — Async batch API (`/v1/batches`)
- **07A** — Flow control + priority queuing

---

## Results Template

```
Test ID:
Date / Cluster:
Model: RedHatAI/Qwen3-8B-FP8-dynamic
Gateway URL:
Duration:

GuideLLM Results:
  - TTFT p50 (cold): ___ ms
  - TTFT p50 (warm): ___ ms
  - ITL p50: ___ ms
  - RPS: ___
  - Error rate: ___%

Prometheus/Grafana:
  - KV cache hit rate (aggregate): ___%
  - Per-pod cache hit rates: pod1 ___% / pod2 ___%
  - Server TTFT P50 cold spike / warm steady: ___ ms / ___ ms
  - EPP KV pool utilization peak: ___%
  - EPP pool ready pods: ___
  - Alerts fired: ___

PASS / FAIL: ___
Notes: ___
```

---

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `LLMInferenceService` not Ready | `oc describe llminferenceservice -n demo-llm` |
| Gateway 401 | `oc create token test-user -n demo-llm` |
| GuideLLM job fails | `oc logs -n demo-llm job/<job-name>` |
| No Grafana metrics | Prometheus scrape config; pod labels `llm-d.ai/role=both` |
| P/D deploy fails | Ensure 2 free GPUs; check NixlConnector compatibility |
| 01c fails immediately | Ensure 01a deployment is still Ready |
| 8B model OOM | Verify 32Gi memory limit per pod; check GPU has sufficient VRAM |
| precise-prefix-cache-scorer won't start | Connected environment required for UDS tokenizer sidecar |
