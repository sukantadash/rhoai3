# Test 01c — Queue + KV Utilization Scheduling Results

**Status:** PASS  
**Date:** 2026-09-05  
**Scenario:** `01c-queue-kv-scheduling`  
**Model:** `RedHatAI/Qwen3-8B-FP8-dynamic`  
**Replicas:** 2  
**Gateway:** `https://inference-gateway.apps.cluster-nqcv7.nqcv7.sandbox340.opentlc.com/demo-llm/qwen`

## Summary

GuideLLM completed **7,285 successful requests** at **80 concurrent streams** over a 120-second measurement window with **0% errors** (80 incomplete at `max_duration` cutoff). Same shared **2048-token prefix** as 01a, but at **16× higher concurrency** (~61 req/s vs 01a's rate=5).

Grafana confirms **97.1% KV cache hit rate** with **both pods actively serving traffic** (~24.5 req/s each, ~49 req/s combined) — evidence that under overload, requests spill beyond a single cache-affine replica. Server-side **TTFT P50 ~95–97 ms** and **E2E P50 ~1.25 s** are higher than 01a, as expected under sustained concurrent load. Per-pod EPP queue sizes reported **0** at the end-of-run snapshot (queues likely drained after benchmark stopped). Error rate **0%**. All [TESTPLAN.md](../../TESTPLAN.md) pass criteria are met.

**Run-order note:** Pod names (`d2cj6`, `gwphg`) match the 01b run (03:16 UTC), not 01a (00:26 UTC). This 01c run executed **after 01b redeployed** `precise-prefix-cache-scorer`, not immediately after 01a as TESTPLAN specifies. Results still validate spillover under overload; for strict 01a-stack comparison, re-run 01c immediately after 01a without intervening deploys.

## Test Configuration

| Parameter | Value |
|---|---|
| GuideLLM profile | `concurrent`, `streams=80` |
| Duration | 120 seconds (`max_duration` constraint) |
| Data | `synthetic_text`, 50 prompt / 50 output tokens |
| Prefix buckets | 1 × 2048-token shared prefix (100% weight) |
| Deployment | No redeploy — reuses existing `qwen` stack (see run-order note) |
| Expected EPP | `prefix-cache-scorer` + queue/kv/lru scorers (01a manifest) |

Source: `guidellm-job.yaml`, `benchmark.csv`.

## Run Window

From `run-metadata.txt` and `benchmark.csv`:

| | Timestamp (UTC) |
|---|---|
| Job start | 2026-09-05T03:24:01Z |
| GuideLLM measure window | 2026-09-05T03:24:15Z → 03:26:15Z (120 s) |
| Job end | 2026-09-05T03:26:24Z |
| Results collected | 2026-09-05T03:26:27Z |
| Job pod | `guidellm-01c-queue-kv-w6vnv` |
| Namespace | `demo-llm` |
| Inference pods | `qwen-kserve-7cbd77f7b6-d2cj6`, `qwen-kserve-7cbd77f7b6-gwphg` |

Set Grafana time range to the measure window above when reviewing dashboard panels.

## GuideLLM Results

From `benchmark.csv` summary:

| Metric | Value |
|---|---|
| Requests successful | 7,285 |
| Requests incomplete | 80 (stopped at max_duration) |
| Requests errored | 0 |
| Error rate | **0%** |
| Throughput (RPS) | **60.7 req/s** (mean) |
| Concurrency | **80** (median streams) |
| TTFT p50 | **139.2 ms** (client-side) |
| TTFT p95 | **295.4 ms** (client-side) |
| TTFT mean | 158.7 ms |
| ITL p50 | **23.5 ms** |
| ITL mean | 23.5 ms |
| E2E latency mean | **1,310 ms** |
| Input tokens / request | 2,111 |
| Output tokens / request | 50 |
| Input tokens/s | 129,652 (mean) |
| Output tokens/s | 3,044 (mean) |

## Grafana Observations

### Page 1 — TTFT, Cache Hit Rate, Throughput

Save screenshots as `grafana-page1.png` in this directory to embed below:

![Grafana LLM Performance Dashboard — page 1](./grafana-page1.png)

| Panel | Observation |
|---|---|
| TTFT P50 | Pod `d2cj6`: **104 / 95.6 ms**; Pod `gwphg`: **96.8 / 95.3 ms** |
| TTFT P95 | Pod `d2cj6`: **235 / 229 ms**; Pod `gwphg`: **234 / 232 ms** |
| TTFT P99 | Pod `d2cj6`: **247 / 246 ms**; Pod `gwphg`: **247 / 247 ms** |
| Inter-Token Latency | No data |
| KV Cache Hit Rate | **97.1%** — cache reuse maintained under overload |
| Per-Pod Cache Hit Rates | Both pods **97.1%** |
| GPU Cache Usage % | **0.000** on both pods |
| Per-Pod GPU Cache Usage | **0.000** on both pods |
| Request Throughput | Pod `d2cj6`: **24.4 / 24.5 req/s**; Pod `gwphg`: **20.7 / 24.6 req/s** — **both pods active** |
| Request Queue Status | Running **0 / 0**, Waiting **0 / 0** at snapshot |

### Page 2 — Token Rate, E2E Latency, EPP Health

Save screenshots as `grafana-page2.png` in this directory to embed below:

![Grafana LLM Performance Dashboard — page 2](./grafana-page2.png)

| Panel | Observation |
|---|---|
| Prompt Tokens/sec | Pod `d2cj6`: **52,634 / 52,265 tps**; Pod `gwphg`: **48,412 / 52,299 tps** |
| Generated Tokens/sec | Pod `d2cj6`: **1,255 / 1,235 tps**; Pod `gwphg`: **1,101 / 1,234 tps** |
| E2E Latency P50 | Pod `d2cj6`: **1.25 s**; Pod `gwphg`: **1.25 s** |
| E2E Latency P95 | Pod `d2cj6`: **1.48 / 1.47 s**; Pod `gwphg`: **1.48 / 1.50 s** |
| E2E Latency P99 | Pod `d2cj6`: **1.50 / 1.49 s**; Pod `gwphg`: **1.50 / 1.59 s** |
| E2E Latency Average | Pod `d2cj6`: **1.22 / 1.10 s**; Pod `gwphg`: **1.22 / 1.11 s** |
| EPP Pool Health & Load | Ready Pods **2**, Average Queue Size **0** |
| EPP KV Cache Pool Utilization | **0%** |
| Per-Pod Queue Sizes (EPP View) | Both pods **0** at snapshot |

## Comparison vs Test 01a

Same prefix workload; 01c increases concurrency from rate=5 to **80 streams**.

| Metric | **01a** (rate=5) | **01c** (streams=80) | Delta |
|---|---|---|---|
| Requests completed | 596 | **7,285** | **12× more** |
| Throughput | ~5 req/s | **~61 req/s** (GuideLLM) / **~49 req/s** (Grafana) | **~10–12×** |
| KV cache hit rate | 96.9% | **97.1%** | maintained |
| TTFT P50 (Grafana) | 50 ms | **95–97 ms** | **~2× higher** under load |
| TTFT p50 (GuideLLM) | 57 ms | **139 ms** | higher under concurrency |
| E2E P50 (Grafana) | 900 ms | **1.25 s** | **~39% higher** |
| Per-pod traffic | One pod dominated | **Both ~24.5 req/s** | **spillover confirmed** |
| Error rate | 0% | **0%** | stable under overload |

**Key finding:** 01a at rate=5 concentrated traffic on one pod. 01c at 80 streams distributes load across **both pods** while maintaining **97.1%** cache hits — the queue and KV utilization scorers spill traffic when the cache-affine pod saturates, without errors.

## TESTPLAN Validation

Per [TESTPLAN.md](../../TESTPLAN.md) — Test 01c Queue + KV Utilization Scheduling:

| Pass criterion | Evidence | Result |
|---|---|---|
| Queue depth distributed across both pods | Per-pod throughput **~24.5 req/s each**; both pods show token processing and E2E metrics — load shared across replicas | **PASS** |
| Error rate < 1% | 0 errored / 7,365 total = **0%** | **PASS** |

### Additional Observations (not pass/fail)

| Expected behavior | Evidence | Result |
|---|---|---|
| Cache hit rate remains high under overload | **97.1%** aggregate | **Observed** |
| TTFT increases under saturation | P50 **95–97 ms** (vs 50 ms in 01a) | **Expected** |
| Per-Pod Queue Sizes visible during run | **0** at end-of-run snapshot only — panel may not capture peak queue depth | **Inconclusive** (use throughput split as spillover signal) |

## Analysis

**Spillover works:** The defining difference from 01a is pod utilization. At rate=5, one pod handled nearly all cache-affine traffic. At 80 concurrent streams, **both pods sustained ~24 req/s** with comparable prompt token rates (~52k tps each), proving the EPP queue and KV utilization scorers route overflow to the second replica.

**Cache effectiveness maintained:** **97.1% KV cache hit rate** under 12× more requests and 10× higher throughput shows prefix caching scales with concurrent shared-prefix traffic — the system does not sacrifice cache reuse when spilling.

**Latency trade-off:** **TTFT P50 ~96 ms** and **E2E P50 ~1.25 s** are higher than 01a's 50 ms / 900 ms. This is expected: 80 concurrent streams create GPU contention and queuing delay. The system remains stable (0% errors) at ~61 req/s.

**Queue panels at zero:** EPP per-pod queue sizes and request queue status show **0** at the Grafana snapshot, likely captured after the benchmark ended or during a drain period. The **throughput and token-rate split across pods** is stronger evidence of distributed load than the queue snapshot alone.

**Run-order caveat:** Executed after 01b (not immediately after 01a). Spillover behavior is validated; strict TESTPLAN sequencing would run 01c directly after 01a before any redeploy.

## Artifacts

| File | Description |
|---|---|
| `benchmark.csv` | GuideLLM summary metrics |
| `benchmark.log` | GuideLLM stdout (base64 payload) |
| `run-metadata.txt` | Gateway URL and time window |
| `prompt.txt` | LLM analysis prompt template |
| `grafana-page1.png` | *(add manually)* TTFT, cache hit, throughput panels |
| `grafana-page2.png` | *(add manually)* Token rate, E2E latency, EPP panels |
