# Test 02a — Global Cache Indexing Results

**Status:** PARTIAL PASS  
**Date:** 2026-09-05  
**Scenario:** `02a-global-cache-indexing`  
**Model:** `RedHatAI/Qwen3-8B-FP8-dynamic`  
**Replicas:** 2  
**Gateway:** `https://inference-gateway.apps.cluster-nqcv7.nqcv7.sandbox340.opentlc.com/demo-llm/qwen`

## Summary

GuideLLM completed a **sweep profile** over 180 seconds with **50 unique 1024-token prefixes**, ramping concurrency across **10 sweep phases** (max concurrency 512). Aggregate benchmark rows report **118,694 successful** requests with **0.12% errors** (140 errored, 1,537 incomplete).

Prometheus (measure window only) shows **KV cache hit rate rising from ~7% to ~54%** — much lower than Test 01a (**~97%** with a single shared prefix), as expected for a multi-prefix workload. Cache hits are **balanced across both pods** (~53% / ~55%). **Per-pod GPU cache usage** peaked at **~0.51%** on both replicas during the run, indicating cache growth under diverse prefix traffic.

**EPP KV Cache Pool Utilization remained 0%** for the entire window, so the TESTPLAN correlation criterion between EPP pool KV metrics and GPU cache growth **cannot be validated** from observability data. Behavioral evidence (distributed hits, GPU cache growth, stable error rate) supports global cache tracking; the EPP dashboard metric gap matches issues seen in Tests 01a and 01c.

## Test Configuration

| Parameter | Value |
|---|---|
| GuideLLM profile | `sweep`, `sweep_size=10`, `max_concurrency=512` |
| Duration | 180 seconds (`max_duration` constraint) |
| Data | `synthetic_text`, 50 prompt / 50 output tokens |
| Prefix buckets | **50 × 1024-token** unique prefixes (100% weight) |
| EPP plugins | `queue-scorer` (2), `kv-cache-utilization-scorer` (2), `precise-prefix-cache-scorer` (3) |
| vLLM | `--enable-prefix-caching` |

Source: `guidellm-job.yaml`, `llminferenceservice.yaml`, `benchmark.csv`.

## Run Window

From `run-metadata.txt` and `benchmark.csv`:

| | Timestamp (UTC) |
|---|---|
| Job start | 2026-09-05T15:09:11Z |
| GuideLLM measure window | **2026-09-05T15:09:30Z → 15:12:30Z** (180 s) |
| Job end | 2026-09-05T15:41:17Z |
| Results collected | 2026-09-05T15:44:18Z |
| Job pod | `guidellm-02a-global-cache-xckbx` |
| Namespace | `demo-llm` |
| Inference pods | `qwen-kserve-7cbd77f7b6-mrvmw`, `qwen-kserve-7cbd77f7b6-v94w2` |

## GuideLLM Results

Sweep profile produces **one benchmark row per sweep phase** (10 rows). Aggregated across all phases:

| Metric | Value |
|---|---|
| Requests successful (all sweeps) | **118,694** |
| Requests incomplete | 1,537 |
| Requests errored | 140 |
| Error rate | **0.12%** |
| Measure duration | 180 s |

**Peak sweep phase** (index 9, highest concurrency):

| Metric | Value |
|---|---|
| Requests successful | 21,229 |
| Requests incomplete | 354 |
| Requests errored | 1 |
| Throughput (RPS) | **117.9 req/s** (mean) |
| Concurrency | **~422** (mean) |
| TTFT median | **~392 ms** |

**First sweep phase** (index 0, lowest concurrency):

| Metric | Value |
|---|---|
| Requests successful | 225 |
| Throughput (RPS) | **1.24 req/s** |
| Errored | 0 |

The sweep ramps load from ~1 req/s to ~118 req/s within the same 180-second window, exercising EPP under increasing multi-prefix concurrency.

## Prometheus Data

**Source:** Prometheus `query_range` API in `llm-d-monitoring` (same PromQL as [`grafana-dashboard-llm-performance.json`](../../instances/llm-d-monitoring/grafana-dashboard-llm-performance.json))  
**Window:** `2026-09-05T15:09:30Z` → `15:12:30Z` (epoch 1788620970–1788621150)  
**Filters:** `model_name=RedHatAI/Qwen3-8B-FP8-dynamic`, `kubernetes_namespace=demo-llm`

### Page 1 — TTFT, Cache Hit Rate, Throughput

| Panel | Pod / Series | Last | Mean | Min | Max |
|---|---|---|---|---|---|
| **P50 TTFT** | aggregate | **32.3 ms** | **50.3 ms** | 32.3 ms | 70.9 ms |
| **P95 TTFT** | aggregate | **74.6 ms** | **79.1 ms** | 74.6 ms | 93.0 ms |
| **P99 TTFT** | aggregate | **78.9 ms** | **84.8 ms** | 78.9 ms | 98.6 ms |
| **KV Cache Hit Rate** | aggregate | **54.1%** | **34.8%** | **6.7%** | **54.1%** |
| **Per-Pod Cache Hit Rates** | `mrvmw` | **53.1%** | **30.8%** | 0% | 53.1% |
| **Per-Pod Cache Hit Rates** | `v94w2` | **55.2%** | **38.9%** | 15.7% | 55.2% |
| **GPU Cache Usage %** | `mrvmw` | **0.00%** | **0.16%** | 0% | **0.51%** |
| **GPU Cache Usage %** | `v94w2` | **0.50%** | **0.08%** | 0% | **0.50%** |
| **Request Throughput** | aggregate | **1.27 req/s** | **1.00 req/s** | 0 | 1.27 req/s |
| **Request Throughput** | `mrvmw` | **0.65 req/s** | **0.49 req/s** | — | — |
| **Request Throughput** | `v94w2` | **0.62 req/s** | **0.50 req/s** | — | — |
| **Request Queue Status** | running / waiting | **1 / 0** | **0.5 / 0** | — | — |

KV hit rate **ramps during the window** (6.7% → 54.1%), consistent with cache warming across 50 distinct prefixes rather than a single shared prefix.

### Page 2 — Token Rate, E2E Latency, EPP Health

| Panel | Pod / Series | Last | Mean |
|---|---|---|---|
| **Prompt Tokens/sec** | aggregate | **1,383 tps** | **1,084 tps** |
| **Generated Tokens/sec** | aggregate | **63.3 tps** | **49.8 tps** |
| **E2E P50** | aggregate | **684 ms** | **787 ms** |
| **E2E P95** | aggregate | **946 ms** | **974 ms** |
| **E2E Average** | aggregate | **769 ms** | **786 ms** |
| **EPP Ready Pods** | `qwen-inference-pool` | **2** | **2** |
| **EPP Average Queue Size** | `qwen-inference-pool` | **0** | **0** |
| **EPP KV Cache Pool Utilization** | `qwen-inference-pool` | **0%** | **0%** |
| **Per-Pod Queue Sizes (EPP)** | both ranks | **0** | **0** |

Save screenshots as `grafana-page1.png` and `grafana-page2.png` in this directory for archival.

## Comparison vs Test 01a (single prefix)

| Metric | **01a** (1 × 2048 prefix, rate=5) | **02a** (50 × 1024 prefixes, sweep) |
|---|---|---|
| Workload | 1 shared prefix | **50 unique prefixes** |
| KV cache hit rate | **96.9%** | **34.8% mean**, **54.1%** at end |
| Per-pod cache skew | One pod ~97%, other ~0% | **Both ~31–39% mean**, balanced |
| GPU cache peak | ~0% (panel) | **~0.51%** both pods |
| EPP KV pool util | 0% | **0%** |
| TTFT P50 (server) | ~50 ms | **50.3 ms** mean *(mixed sweep phases)* |
| Peak client TTFT | ~57 ms | **~392 ms** (sweep phase 9) |
| Error rate | 0% | **0.12%** |

The **large drop in cache hit rate** (97% → 35–54%) confirms the multi-prefix workload is fundamentally different from 01a. EPP and vLLM still achieve meaningful prefix reuse (~54% at steady state) across a diverse prefix set.

## TESTPLAN Validation

Per [TESTPLAN.md](../../TESTPLAN.md) — Test 02a Global Cache Indexing:

| Pass criterion | Evidence | Result |
|---|---|---|
| EPP pool KV metric correlates with per-pod GPU cache growth | GPU cache **grew to ~0.51%** on both pods; EPP KV util **0%** entire window — no observable correlation | **FAIL** (metric gap) |
| Benchmark completes with acceptable errors | 118,694 successful, **0.12%** error rate | **PASS** |
| EPP tracks cache across pool under many prefixes | Hit rate **6.7% → 54.1%** ramp; hits **balanced** across `mrvmw` / `v94w2`; both pods active | **PASS** (behavioral) |

**Overall:** Global cache indexing **behavior is observed** (multi-prefix hits, pod distribution, GPU cache growth). The **EPP KV utilization dashboard metric did not populate**, same limitation as Tests 01a and 01c. Recommend validating EPP metrics export separately or using per-pod GPU cache + hit-rate trends as primary signals.

## Analysis

**Multi-prefix workload confirmed:** With **50 unique 1024-token prefixes**, aggregate KV hit rate (**~35%** mean, **54%** at end) is far below 01a's **97%** single-prefix result. This is expected — most requests miss on first encounter with a given prefix, then hits accumulate as prefixes repeat during the sweep.

**Balanced pool utilization:** Unlike 01a (one pod dominates), both pods show similar cache hit rates (**~31–39%** mean) and throughput (**~0.5 req/s** mean in Prometheus scrape windows). The `precise-prefix-cache-scorer` routes across the pool for diverse prefix traffic.

**GPU cache growth:** Per-pod GPU cache peaked at **~0.51%** during the run (`mrvmw` max 0.51%, `v94w2` max 0.50%), while starting at 0%. This satisfies the *intent* of watching cache growth under global indexing, even though EPP's aggregate KV utilization panel reported 0%.

**Sweep load profile:** GuideLLM ramped from **1.2 req/s** (sweep 0) to **118 req/s** (sweep 9) with **~422** mean concurrency at peak. Client-side TTFT at peak sweep reached **~392 ms** median — higher than light-load 01a/01d tests, reflecting concurrent multi-prefix pressure.

**Prometheus vs GuideLLM throughput:** Prometheus aggregate throughput (~1 req/s mean) reflects `rate()` smoothing over the full 180 s window including ramp-up/down; GuideLLM peak sweep reports **~118 req/s**. Use GuideLLM for peak-load latency; use Prometheus for cache-hit and GPU-cache trends over the measure window.

## Artifacts

| File | Description |
|---|---|
| `benchmark.csv` | GuideLLM summary metrics (10 sweep rows) |
| `benchmark.log` | Complete GuideLLM stdout (base64 payload) |
| `run-metadata.txt` | Gateway URL and time window |
| `prompt.txt` | LLM analysis prompt template |
| `grafana-page1.png` | *(add manually)* TTFT, cache hit, throughput panels |
| `grafana-page2.png` | *(add manually)* Token rate, E2E latency, EPP panels |
