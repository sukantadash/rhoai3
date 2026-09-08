# Test 01d — Round-Robin Control (A/B) Results

**Status:** PARTIAL PASS  
**Date:** 2026-09-05  
**Scenario:** `01d-round-robin-control`  
**Model:** `RedHatAI/Qwen3-8B-FP8-dynamic`  
**Replicas:** 2  
**Gateway:** `https://inference-gateway.apps.cluster-nqcv7.nqcv7.sandbox340.opentlc.com/demo-llm/qwen`

## Summary

GuideLLM completed **596 successful requests** at constant rate=5 over a 120-second measurement window with **0% errors** (4 incomplete at `max_duration` cutoff). Identical traffic to 01a (1 × 2048-token shared prefix), but EPP uses **`random-picker` only** with **no `--enable-prefix-caching`**.

The control run completed cleanly and shows a clear **routing difference vs 01a**: per-pod cache hits are **balanced (96.7% on both pods)** instead of skewed to one replica. However, **server-side TTFT is not 3× worse than 01a** — Grafana P50 **~45–48 ms** vs 01a's **50 ms**, and GuideLLM p50 **54 ms** vs 01a's **57 ms**. At rate=5, each pod receives ~2.5 req/s and warms a **local** prefix cache independently, masking the routing penalty. The A/B TTFT criterion from [TESTPLAN.md](../../TESTPLAN.md) is **not met**; the cache-skew criterion **is met**.

**Prometheus retrieval:** Metrics below were queried directly from Prometheus (`llm-d-monitoring`) for the **GuideLLM measure window only** (`2026-09-05T07:23:35Z` → `07:25:35Z`). An earlier manual Grafana export used a wider range (`00:23:17` → `00:40:35` local) and included contaminated E2E/token series from Test 01c — those values are replaced here.

## Test Configuration

| Parameter | Value |
|---|---|
| GuideLLM profile | `constant`, `rate=5` |
| Duration | 120 seconds (`max_duration` constraint) |
| Data | `synthetic_text`, 50 prompt / 50 output tokens |
| Prefix buckets | 1 × 2048-token shared prefix (100% weight) |
| EPP plugins | `random-picker` only |
| vLLM | No `VLLM_ADDITIONAL_ARGS` (prefix caching disabled in manifest) |

Source: `guidellm-job.yaml`, `llminferenceservice.yaml`, `benchmark.csv`.

## Run Window

From `run-metadata.txt` and `benchmark.csv`:

| | Timestamp (UTC) |
|---|---|
| Job start | 2026-09-05T07:23:17Z |
| GuideLLM measure window | 2026-09-05T07:23:35Z → 07:25:35Z (120 s) |
| Job end | 2026-09-05T07:40:35Z |
| Results collected | 2026-09-05T07:41:16Z |
| Grafana range | 2026-09-05 00:23:17 → 00:40:35 (local, aligns with UTC job window) |
| Job pod | `guidellm-01d-round-robin-gf5mk` |
| Namespace | `demo-llm` |
| Inference pods | `qwen-kserve-6cccd699cd-lc5jp`, `qwen-kserve-6cccd699cd-4d4zn` |

## GuideLLM Results

From `benchmark.csv` summary:

| Metric | Value |
|---|---|
| Requests successful | 596 |
| Requests incomplete | 4 (stopped at max_duration) |
| Requests errored | 0 |
| Error rate | **0%** |
| Throughput (RPS) | **5.0 req/s** (mean), 4.0 (median concurrency) |
| Concurrency | 4.0 (mean), 4.0 (median) |
| TTFT p50 | **54.0 ms** (client-side) |
| TTFT p95 | **78.7 ms** (client-side) |
| TTFT mean | 54.1 ms |
| ITL p50 | **15.4 ms** |
| ITL mean | 15.4 ms |
| E2E latency mean | **810 ms** |
| Input tokens / request | 2,111 |
| Output tokens / request | 50 |
| Input tokens/s | 10,586 (mean) |
| Output tokens/s | 249 (mean) |

## Grafana / Prometheus Data

**Source:** Prometheus `query_range` API (same PromQL as [`grafana-dashboard-llm-performance.json`](../../instances/llm-d-monitoring/grafana-dashboard-llm-performance.json))  
**Window:** `2026-09-05T07:23:35Z` → `07:25:35Z` (epoch 1788593015–1788593135)  
**Filters:** `model_name=RedHatAI/Qwen3-8B-FP8-dynamic`, `kubernetes_namespace=demo-llm`

### Page 1 — TTFT, Cache Hit Rate, Throughput

| Panel | Pod / Series | Last | Mean |
|---|---|---|---|
| **P50 TTFT** | aggregate | **47.8 ms** | **47.8 ms** |
| **P50 TTFT** | `lc5jp` | **47.7 ms** | **48.1 ms** |
| **P50 TTFT** | `4d4zn` | **47.9 ms** | **47.4 ms** |
| **P95 TTFT** | aggregate | **58.8 ms** | **59.0 ms** |
| **P99 TTFT** | aggregate | **59.8 ms** | **89.1 ms** |
| **KV Cache Hit Rate** | aggregate | **96.7%** | **96.0%** |
| **Per-Pod Cache Hit Rates** | `lc5jp` | **96.7%** | **96.1%** |
| **Per-Pod Cache Hit Rates** | `4d4zn` | **96.7%** | **96.0%** |
| **GPU Cache Usage %** | `lc5jp` | **1.01%** | **0.89%** |
| **GPU Cache Usage %** | `4d4zn` | **0.96%** | **0.89%** |
| **Request Throughput** | aggregate | **5.05 req/s** | **3.51 req/s** |
| **Request Throughput** | `lc5jp` | **2.35 req/s** | **1.75 req/s** |
| **Request Throughput** | `4d4zn` | **2.71 req/s** | **1.76 req/s** |
| **Request Queue Status** | running / waiting | **3 / 0** | **3.3 / 0** |

### Page 2 — Token Rate, E2E Latency, EPP Health

| Panel | Pod / Series | Last | Mean |
|---|---|---|---|
| **Prompt Tokens/sec** | aggregate | **10,670 tps** | **7,481 tps** |
| **Prompt Tokens/sec** | `lc5jp` | **4,951 tps** | **3,731 tps** |
| **Prompt Tokens/sec** | `4d4zn` | **5,719 tps** | **3,750 tps** |
| **Generated Tokens/sec** | aggregate | **252 tps** | **176 tps** |
| **Generated Tokens/sec** | `lc5jp` | **117 tps** | **88 tps** |
| **Generated Tokens/sec** | `4d4zn` | **135 tps** | **88 tps** |
| **E2E P50** | aggregate | **812 ms** | **826 ms** |
| **E2E P95** | aggregate | **981 ms** | **983 ms** |
| **E2E Average** | aggregate | **799 ms** | **801 ms** |
| **EPP Ready Pods** | `qwen-inference-pool` | **2** | **2** |
| **EPP Average Queue Size** | `qwen-inference-pool` | **0** | **0** |
| **EPP KV Cache Pool Utilization** | `qwen-inference-pool` | **1%** | **0.9%** |
| **Per-Pod Queue Sizes (EPP)** | both ranks | **0** | **0** |

Save screenshots as `grafana-page1.png` and `grafana-page2.png` in this directory for archival.

## A/B Comparison vs Test 01a

Identical GuideLLM traffic; only EPP and vLLM prefix-caching config differ.

| Metric | **01a** (prefix-cache-scorer) | **01d** (random-picker) | Expected for control |
|---|---|---|---|
| EPP | `prefix-cache-scorer` + queue/kv/lru | `random-picker` only | Different |
| Prefix caching | `--enable-prefix-caching` | disabled | Different |
| KV cache hit rate | **96.9%** | **96.7%** | 01d lower or more fragmented — **not observed** |
| Per-pod cache skew | One pod **~97%**, other **~0%** | **Both 96.7%** | 01a more skewed — **observed** |
| TTFT P50 (Prometheus) | **50 ms** | **47.8 ms** | 01d ≥3× slower — **not observed** |
| TTFT p50 (GuideLLM) | **57.0 ms** | **54.0 ms** | 01d slower — **not observed** |
| E2E mean (GuideLLM) | **827 ms** | **810 ms** | 01d slower — **not observed** |
| Error rate | 0% | **0%** | Both stable — **observed** |

### Why TTFT did not diverge at rate=5

With `random-picker`, traffic splits roughly **50/50** across two pods (~2.5 req/s each). Each pod independently processes the same shared prefix often enough to build a **local** KV cache, yielding **96.7% hit rate per pod** without intelligent global routing. Under this light load, local caching compensates for random placement — so TTFT stays comparable to 01a.

The meaningful A/B signal in this run is **routing topology**, not latency:

```
01a (intelligent routing):          01d (random-picker):
┌─────────┐  ┌─────────┐            ┌─────────┐  ┌─────────┐
│ Pod A   │  │ Pod B   │            │ Pod A   │  │ Pod B   │
│ ~97%    │  │ ~0%     │            │ 96.7%   │  96.7%  │
│ hits    │  │ hits    │            │ hits    │  hits   │
│ ~all    │  │ idle    │            │ ~half   │  ~half  │
│ traffic │  │         │            │ traffic │ traffic │
└─────────┘  └─────────┘            └─────────┘  └─────────┘
```

Intelligent routing consolidates cache on one GPU; random routing duplicates cache work across both GPUs while achieving similar latency at low RPS.

## TESTPLAN Validation

Per [TESTPLAN.md](../../TESTPLAN.md) — Test 01d Round-Robin Control (A/B):

| Pass criterion | Evidence | Result |
|---|---|---|
| 01a server-side warm TTFT ≥3× better than 01d | Prometheus: 01a **50 ms** vs 01d **47.8 ms** → **~1.0×** (no improvement) | **FAIL** |
| 01a shows stronger per-pod cache hit skew than 01d | 01a: **97% / ~0%**; 01d: **96.7% / 96.7%** (balanced) | **PASS** |
| Benchmark completes; error rate < 1% | 596 successful, 0 errored = **0%** | **PASS** |

**Overall:** Control run is **valid for comparison** (routing skew confirmed) but the **3× TTFT separation criterion is not met** at rate=5. Consider re-running A/B at higher concurrency (e.g. 01c-style streams=80) where random placement should cause more cache misses and higher TTFT on 01d.

## Analysis

**Routing control confirmed:** `random-picker` distributes load evenly — both pods show equal cache hit rates (**96.7%** each) and balanced throughput (**~1.75 req/s** mean per pod, **~3.5 req/s** aggregate). This contrasts sharply with 01a where one pod monopolized cache-affine traffic.

**High cache hit rate without intelligent routing:** **96.7%** aggregate hits on 01d show that at **5 req/s**, local per-pod prefix reuse is sufficient even without `prefix-cache-scorer` or explicit `--enable-prefix-caching` in the manifest. vLLM may still cache repeated prefixes within a pod session. The A/B value of 01d is therefore **operational efficiency** (one warm GPU vs two partially warm GPUs), not raw TTFT at this load level.

**Latency parity:** Prometheus TTFT P50 **47.8 ms** and E2E P50 **812 ms** align with GuideLLM E2E **810 ms** — on par with 01a. The TESTPLAN 3× TTFT threshold likely targets scenarios where random routing sends requests to cold pods — not observable at rate=5 with a single shared prefix.

**GPU cache on both pods:** Retrieved metrics show **~0.9–1.0%** GPU cache usage on **both** `lc5jp` and `4d4zn` (not 0%), consistent with each pod warming its own local prefix cache under random routing.

## Artifacts

| File | Description |
|---|---|
| `benchmark.csv` | GuideLLM summary metrics |
| `benchmark.json` | Full GuideLLM run record |
| `benchmark.log` | Complete GuideLLM stdout |
| `run-metadata.txt` | Gateway URL and time window |
| `prompt.txt` | LLM analysis prompt template |
| `grafana-page1.png` | *(add manually)* TTFT, cache hit, throughput panels |
| `grafana-page2.png` | *(add manually)* EPP health panels |
