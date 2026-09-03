# Test 00 — Baseline Results

**Status:** PASS  
**Date:** 2026-09-03  
**Scenario:** `00-baseline`  
**Model:** Qwen/Qwen3-0.6B  
**Replicas:** 2  
**Gateway:** `https://inference-gateway.REPLACE_WITH_CLUSTER_APPS_DOMAIN/demo-llm/qwen`

## Test Configuration

| Parameter | Value |
|---|---|
| GuideLLM profile | `throughput`, max_concurrency=20 |
| Duration | 60 seconds |
| Data | `synthetic_text`, 100 prompt / 50 output tokens |
| Prefix buckets | None (random traffic) |
| EPP plugins | precise-prefix-cache-scorer (3), queue-scorer (2), kv-cache-utilization-scorer (2) |

## Run Window

| | Timestamp (UTC) |
|---|---|
| Start | 2026-09-03T15:34:35Z |
| End | 2026-09-03T15:35:54Z |
| Job pod | `guidellm-00-baseline-lq294` |

## GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | 3,814 |
| Requests incomplete | 18 (stopped at max_duration) |
| Requests errored | 0 |
| Error rate | 0% |
| Throughput | 63.5 req/s (mean) |
| Concurrency | 20 (median) |
| TTFT p50 | ~63 ms |
| TTFT mean | ~67 ms |
| ITL p50 | ~5.0 ms |
| E2E latency mean | ~313 ms |
| Input tokens / request | ~108 |
| Output tokens / request | ~50 |
| Input tokens/s | ~6,919 |
| Output tokens/s | ~3,190 |
| Total tokens/s | ~10,081 |

## Grafana Observations

Time range: 2026-09-03 08:34:35 → 08:35:54 (local)

| Panel | Observation |
|---|---|
| TTFT | P50 ~31–37 ms (server-side); stable under load |
| KV Cache Hit Rate | 0% — expected (no shared prefixes) |
| GPU Cache Usage | ~0% — short prompts on small model |
| Request Throughput | Ramps to ~6–7 req/s per series as concurrency fills |
| Request Queue | Running peaks at 20; waiting stays at 0 |
| EPP Ready Pods | 2 (`qwen-kserve-84d65b77d8-lqr4b`, `...-whp9d`) |
| EPP Queue Size | 0 on both pods |
| EPP KV Cache Utilization | 0% |
| Token Processing Rate | ~324 + ~317 tokens/s at peak (split across pods) |
| E2E Latency P50 | ~242–250 ms |

### Grafana Screenshots

**Page 1** — TTFT, inter-token latency, KV cache hit rate, GPU cache usage, request throughput, request queue status

![Grafana page 1: TTFT, cache, throughput, and queues](graphana-page1.png)

**Page 2** — Token processing rate, end-to-end latency, EPP pool health, KV cache utilization, per-pod queue sizes

![Grafana page 2: tokens, E2E latency, and EPP health](grafana-page2.png)

## Pass / Fail

| Criterion | Result |
|---|---|
| Gateway returns 200 | PASS |
| Both pods receive traffic | PASS |
| EPP healthy (`inference_pool_ready_pods == 2`) | PASS |
| Error rate < 1% | PASS (0%) |
| Benchmark completes | PASS |

## Interpretation

This baseline establishes reference performance for random synthetic traffic with no prefix affinity. The 0% KV cache hit rate is expected — every prompt is unique, so the precise-prefix-cache scorer has nothing to route on. Both replicas are active with no queue buildup at concurrency 20.

## Comparison Reference

Use these values when evaluating later tests:

| Test | Expected change vs baseline |
|---|---|
| 01a Prefix-cache | TTFT drops on warm prefixes; KV hit rate > 0%; one pod dominates cache |
| 01b Queue/KV spillover | Queues on both pods under concurrency=80; secondary pod cache rises |
| 01c Round-robin control | Higher TTFT, lower cache hit rate than 01a |
| 04a Data parallelism (4 rep) | ~1.5–2× throughput vs 63.5 req/s |

## Artifacts

| File | Description |
|---|---|
| `benchmark.json` | Full GuideLLM run data |
| `benchmark.csv` | Summary statistics |
| `benchmark.log` | GuideLLM console output |
| `run-metadata.txt` | Collection metadata |
| `graphana-page1.png` | Grafana: TTFT, cache, throughput, queues |
| `grafana-page2.png` | Grafana: tokens, E2E latency, EPP health |
