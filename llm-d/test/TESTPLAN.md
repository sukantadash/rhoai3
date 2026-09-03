# llm-d Feature Validation Test Plan

Performance validation of llm-d features using **GuideLLM** for traffic generation and **Prometheus/Grafana** for observability.

## Prerequisites

1. Base cluster deployed via `[../llmd-script.sh](../llmd-script.sh)` (GPU operators, RHOAI, gateway, `demo-llm` namespace, `test-user` RBAC).
2. Monitoring overlay applied: `oc apply -k ../overlays/09-llm-d-monitoring/`
3. `ghcr-pull-secret` in `demo-llm` namespace (for GuideLLM image).
4. Logged in to cluster: `oc whoami`
5. GPU capacity per scenario (see table below).

## How to Run

```bash
cd rhoai3/llm-d/test

# Verify cluster and gateway
./test-script.sh setup

# Run a single scenario (deploy + benchmark + collect results)
./test-script.sh run 00-baseline

# Run all scenarios in order
./test-script.sh run-all

# Individual steps
./test-script.sh deploy 01a-prefix-cache-routing
./test-script.sh benchmark 01a-prefix-cache-routing
./test-script.sh collect 01a-prefix-cache-routing
./test-script.sh cleanup 01a-prefix-cache-routing
```

Results are saved to `<scenario>/results/` (`benchmark.json`, `benchmark.csv`, `run-metadata.txt`).

Open Grafana during each run and set the time range to the `start_time` / `end_time` recorded in `run-metadata.txt`:

```bash
oc get route grafana-secure -n llm-d-monitoring -o jsonpath='{.spec.host}'
```



## Scenario Summary


| ID  | Scenario                    | Feature                        | GPUs | Service   | Deploy?         |
| --- | --------------------------- | ------------------------------ | ---- | --------- | --------------- |
| 00  | `00-baseline`               | Baseline throughput            | 2    | `qwen`    | Yes             |
| 01a | `01a-prefix-cache-routing`  | Prefix-cache aware routing     | 2    | `qwen`    | Yes             |
| 01b | `01b-queue-kv-scheduling`   | Queue + KV utilization scorers | 2    | `qwen`    | No (reuses 01a) |
| 01c | `01c-round-robin-control`   | Round-robin control (A/B)      | 2    | `qwen`    | Yes             |
| 02a | `02a-global-cache-indexing` | Global cache indexing          | 2    | `qwen`    | Yes             |
| 03a | `03a-pd-separation`         | Prefill/decode separation      | 2    | `qwen-pd` | Yes             |
| 03b | `03b-pd-kv-transfer`        | KV direct transfer (NIXL)      | 2    | `qwen-pd` | No (reuses 03a) |
| 03c | `03c-heterogeneous-pd`      | Heterogeneous P/D workload     | 2    | `qwen-pd` | No (reuses 03a) |
| 04a | `04a-data-parallelism`      | 4-replica data parallelism     | 4    | `qwen`    | Yes             |


---



## Test 00 — Baseline Throughput

**Objective:** Establish baseline TTFT, ITL, RPS, and TPS before feature-specific tests.

**Steps:**

1. `./test-script.sh run 00-baseline`
2. Open Grafana LLM Performance dashboard for the benchmark time window.

**Expected results:**

- Gateway returns HTTP 200; GuideLLM error rate < 1%
- Both `qwen` pods receive traffic
- `up{job="llm-d-epp-metrics"} == 1`
- No `EPPNoReadyPods` alert

**Pass criteria:** Benchmark completes; baseline metrics recorded in `00-baseline/results/benchmark.json`.

---



## Test 01a — Prefix-Cache Aware Routing

**Objective:** Prove EPP routes shared-prefix requests to the pod holding the KV cache.

**Deployment:** Qwen 2-replica with intelligent EPP (`precise-prefix-cache-scorer` weight 3).

**GuideLLM:** Constant rate=5, 1 shared prefix × 2048 tokens, 120s duration.

**Steps:**

1. `./test-script.sh run 01a-prefix-cache-routing`
2. In Grafana, watch **KV Cache Hit Rate**, **Per-Pod Cache Hit Rates**, **Per-Pod GPU Cache Usage**.

**Expected results:**

- TTFT p50 (warm) < 20% of TTFT p50 (cold)
- One pod dominates cache hits and GPU cache usage
- **EPP KV Cache Pool Utilization** rises during the run

**Pass criteria:** Warm-prefix TTFT at least 5× faster than cold-start TTFT; one pod receives > 70% of cache hits.

---



## Test 01b — Queue + KV Utilization Scheduling

**Objective:** When the cache-affine pod saturates, EPP spills traffic to the second replica.

**Deployment:** Reuses 01a deployment (no redeploy).

**GuideLLM:** Same prefix data as 01a, concurrency=80, 120s duration.

**Steps:**

1. `./test-script.sh run 01b-queue-kv-scheduling`
2. Watch **Per-Pod Queue Sizes (EPP View)** and **Request Queue Status**.

**Expected results:**

- Both pods show queue activity
- Secondary pod GPU cache % increases under overload
- Error rate < 1%

**Pass criteria:** Queue depth distributed across both pods; no single-pod bottleneck.

---



## Test 01c — Round-Robin Control (A/B)

**Objective:** Quantify llm-d routing benefit vs naive random balancing.

**Deployment:** Qwen 2-replica with `random-picker` EPP only (no prefix/queue/kv scorers).

**GuideLLM:** Identical traffic to 01a.

**Steps:**

1. `./test-script.sh run 01c-round-robin-control`
2. Compare `01c/results/benchmark.json` TTFT against `01a/results/benchmark.json`.

**Expected results:**

- Higher warm-prefix TTFT than 01a
- Lower cache hit rate than 01a
- More even traffic split across pods

**Pass criteria:** 01a warm TTFT at least 3× better than 01c.

---



## Test 02a — Global Cache Indexing

**Objective:** Validate EPP tracks cache state across the inference pool.

**Deployment:** Qwen 2-replica with intelligent EPP (restored after 01c).

**GuideLLM:** 50 unique prefixes × 1024 tokens, sweep profile, 180s.

**Steps:**

1. `./test-script.sh run 02a-global-cache-indexing`
2. Watch `inference_pool_average_kv_cache_utilization` and **Per-Pod GPU Cache Usage**.

**Expected results:**

- Pool KV utilization rises as unique prompts fill caches
- Both pods accumulate GPU cache
- Hit rate increases when prefixes repeat within sweep

**Pass criteria:** EPP pool KV metric correlates with per-pod GPU cache growth.

---



## Test 03a — Prefill/Decode Separation

**Objective:** Validate P/D disaggregation with separate prefill and decode pools.

**Deployment:** `qwen-pd` with `pd-profile-handler`, `prefill-filter`, `decode-filter`, NixlConnector KV transfer. Requires 2 GPUs.

**GuideLLM:** Sweep, 1024 prompt / 1024 output tokens, 120s.

**Steps:**

1. `./test-script.sh run 03a-pd-separation`
2. Check vLLM pod logs for `kv_transfer_params.do_remote_prefill` / `do_remote_decode`.

**Expected results:**

- Prefill and decode pods both active
- vLLM logs confirm cross-pod KV handoff
- Benchmark completes without timeout

**Pass criteria:** Both pools healthy; KV transfer visible in logs.

---



## Test 03b — KV Direct Transfer

**Objective:** Stress KV transfer between prefill and decode under high concurrency.

**Deployment:** Reuses `qwen-pd` from 03a.

**GuideLLM:** 1024/1024 tokens, concurrency=50, 120s.

**Steps:**

1. `./test-script.sh run 03b-pd-kv-transfer`
2. Monitor network I/O on RDMA/IB interfaces if available.

**Expected results:**

- p95 E2E latency stable under load
- No head-of-line blocking or pod crashes

**Pass criteria:** Error rate < 1%; both pools remain Ready.

---



## Test 03c — Heterogeneous P/D Workload

**Objective:** Validate P/D under mixed prompt/output sizes.

**Deployment:** Reuses `qwen-pd` from 03a.

**GuideLLM:** Mixed prefix buckets (256/512/1024 tokens), sweep, 180s.

**Steps:**

1. `./test-script.sh run 03c-heterogeneous-pd`

**Expected results:**

- All request size classes complete successfully
- Error rate < 1%

**Pass criteria:** Benchmark completes; no pod restarts during run.

---



## Test 04a — Data Parallelism (4 Replicas)

**Objective:** Validate throughput scaling with 4-replica intelligent routing.

**Deployment:** Qwen 4-replica with intelligent EPP. Requires 4 GPUs.

**GuideLLM:** Throughput sweep, max_concurrency=40, 120s.

**Steps:**

1. `./test-script.sh run 04a-data-parallelism`
2. Verify `inference_pool_ready_pods == 4` in Grafana.

**Expected results:**

- All 4 pods in inference pool
- RPS roughly 1.5–2× baseline (Test 00)
- Per-pod request counters roughly balanced under random traffic

**Pass criteria:** 4 ready pods; throughput scales vs baseline.

---



## Deferred Scenarios

See `[deferred/README.md](deferred/README.md)` for features not yet configured in this repo:

- 01D — Predicted latency routing
- 02B — Hierarchical KV offloading
- 04B — Multi-node LWS + TP/EP
- 04C — LoRA adapters
- 05A — Workload Variant Autoscaler
- 05B — Async Batch API

---



## Results Template

After each run, fill in:

```
Test ID:
Date / Cluster:
Gateway URL:
Duration:

GuideLLM Results:
  - TTFT p50 (cold): ___ ms
  - TTFT p50 (warm): ___ ms
  - ITL p50: ___ ms
  - RPS: ___
  - Error rate: ___%

Prometheus/Grafana:
  - KV cache hit rate peak: ___%
  - EPP pool ready pods: ___
  - Alerts fired: ___

PASS / FAIL: ___
Notes: ___
```



## Troubleshooting


| Symptom                         | Check                                                     |
| ------------------------------- | --------------------------------------------------------- |
| `LLMInferenceService` not Ready | `oc describe llminferenceservice -n demo-llm`             |
| Gateway 401                     | `oc create token test-user -n demo-llm`                   |
| GuideLLM job fails              | `oc logs -n demo-llm job/<job-name>`                      |
| No Grafana metrics              | Prometheus scrape config; pod labels `llm-d.ai/role=both` |
| P/D deploy fails                | Ensure 2 free GPUs; check NixlConnector compatibility     |


