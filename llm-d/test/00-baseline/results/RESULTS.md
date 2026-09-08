# Test 00 — Default Baseline Results

**Status:** PASS  
**Date:** 2026-09-04  
**Scenario:** `00-baseline`  
**Model:** `RedHatAI/Qwen3-8B-FP8-dynamic`  
**Replicas:** 2  
**Gateway:** `https://inference-gateway.apps.cluster-nqcv7.nqcv7.sandbox340.opentlc.com/demo-llm/qwen`

## Summary

GuideLLM completed **1,476 successful requests** at concurrency 20 over a 60-second measurement window with **0% errors** (20 incomplete at `max_duration` cutoff). Both `qwen` pods were active under random synthetic traffic with **no shared prefixes**. Grafana confirms **0% KV cache hit rate** on both pods — expected for this workload. Server-side **TTFT P50 ~47–51 ms** and **~7–12 req/s** sustained throughput establish the baseline floor before feature-specific llm-d scheduler tests (01a onward). All [TESTPLAN.md](../../TESTPLAN.md) pass criteria are met.

## Test Configuration

| Parameter | Value |
|---|---|
| GuideLLM profile | `throughput`, `max_concurrency=20` |
| Duration | 60 seconds (`max_duration` constraint) |
| Data | `synthetic_text`, 100 prompt / 50 output tokens |
| Prefix buckets | None (random traffic) |
| EPP config | Default — `router.scheduler: {}` (no inline `EndpointPickerConfig`) |
| vLLM | Platform defaults (no `--enable-prefix-caching`) |

Source: `guidellm-job.yaml`, `llminferenceservice.yaml`, `benchmark.csv`.

## Run Window

From `run-metadata.txt`:

| | Timestamp (UTC) |
|---|---|
| Job start | 2026-09-04T23:50:28Z |
| Job end | 2026-09-04T23:51:52Z |
| GuideLLM measure window | 2026-09-04T23:50:47Z → 23:51:47Z (60 s) |
| Results collected | 2026-09-04T23:51:55Z |
| Job pod | `guidellm-00-baseline-cg4mh` |
| Namespace | `demo-llm` |

Set Grafana time range to the measure window above when reviewing dashboard panels.

## GuideLLM Results

From `benchmark.csv` summary row:

| Metric | Value |
|---|---|
| Requests successful | 1,476 |
| Requests incomplete | 20 (stopped at max_duration) |
| Requests errored | 0 |
| Error rate | **0%** |
| Throughput (RPS) | **24.6 req/s** (mean), 3.3 (median bucket) |
| Concurrency | 20 (median) |
| TTFT p50 | **51.0 ms** |
| TTFT mean | 55.5 ms |
| ITL p50 | **16.1 ms** |
| ITL mean | 16.2 ms |
| E2E latency mean | 801 ms |
| Input tokens / request | 108 (mean) |
| Output tokens / request | 50 |
| Input tokens/s | 2,695 (mean) |
| Output tokens/s | 1,232 (mean) |

## Grafana Observations

### Page 1 — LLM Performance Dashboard

Save screenshots as `grafana-page1.png` in this directory to embed below:

![Grafana LLM Performance Dashboard — page 1](./grafana-page1.png)

| Panel | Observation |
|---|---|
| TTFT P50 | **46.7–45.7 ms** (last), **51–59 ms** (mean) across replicas |
| TTFT P95 | **59.0–59.2 ms** (last), **68–98 ms** (mean) |
| TTFT P99 | **68.8–71.1 ms** (last), **87–121 ms** (mean) |
| Inter-Token Latency | No data (panel empty for this run) |
| KV Cache Hit Rate | **0%** — expected with random traffic, no shared prefixes |
| Per-Pod Cache Hit Rates | **Pod `qwen-kserve-6cccd699cd-zxcl5`: 0%**, **Pod `qwen-kserve-6cccd699cd-zrnn9`: 0%** |
| GPU Cache Usage % | **0.000** on both pods |
| Per-Pod GPU Cache Usage | **0.000** on both pods |
| Request Throughput | Success rate **~11.4–11.9 req/s** (last), **~7.4–7.8 req/s** (mean); total rate matches |
| Request Queue Status | Running **0**, Waiting **0** — no backlog at end of run |

Both pods appear in per-pod panels, confirming traffic reached both replicas.

### Page 2 — Token Rate, E2E Latency, EPP Health

Save screenshots as `grafana-page2.png` in this directory to embed below:

![Grafana LLM Performance Dashboard — page 2](./grafana-page2.png)

| Panel | Observation |
|---|---|
| Prompt Tokens/sec | **1,210–1,289 tps** (last), **812–850 tps** (mean) |
| Generated Tokens/sec | **558–596 tps** (last), **372–392 tps** (mean) |
| E2E Latency P50 | **688–689 ms** (last), **749–766 ms** (mean) |
| E2E Latency P95 | **951 ms** (last), **966–974 ms** (mean) |
| E2E Latency P99 | **990 ms** (last), **993–995 ms** (mean) |
| E2E Latency Average | **799–801 ms** |
| EPP Pool Health & Load | No data |
| EPP KV Cache Pool Utilization | No data |
| Per-Pod Queue Sizes (EPP View) | No data |

**Note:** EPP-specific panels reported no data for this default deployment run. This is not a TESTPLAN pass/fail criterion for Test 00. vLLM-side metrics (TTFT, throughput, queue status) are sufficient to validate the baseline.

## TESTPLAN Validation

Per [TESTPLAN.md](../../TESTPLAN.md) — Test 00 Default Baseline (No Custom llm-d Config):

| Pass criterion | Evidence | Result |
|---|---|---|
| Benchmark completes | 1,476 successful + 20 incomplete at duration limit; job pod exited cleanly | **PASS** |
| Baseline metrics recorded | `benchmark.json`, `benchmark.csv`, `run-metadata.txt` present | **PASS** |
| GuideLLM error rate < 1% | 0 errored / 1,496 total = **0%** | **PASS** |
| Both `qwen` pods receive traffic | Two distinct pod names in Grafana per-pod panels | **PASS** |
| KV cache hit rate ~0% | Aggregate and per-pod hit rate **0%** under random traffic | **PASS** |
| Gateway returns HTTP 200 | 0% error rate; 1,476 successful completions | **PASS** |

## Analysis

**Throughput:** GuideLLM mean RPS of **24.6 req/s** (client-side, concurrency 20) and Grafana success rate of **~7–12 req/s** (server-side scrape window) both indicate healthy sustained load. The difference reflects aggregation windows and client vs server measurement points — both confirm the service handled concurrent random traffic without errors.

**Latency:** Server-side **TTFT P50 ~47–51 ms** on the 8B FP8 model sets the latency floor for later feature tests. **E2E P50 ~688–749 ms** reflects full request lifecycle (prefill + 50-token decode) at concurrency 20.

**Caching:** **0% KV cache hit rate** is correct — Test 00 uses random synthetic prompts with no shared prefix buckets. The default platform scheduler is active but has nothing cache-affine to route on.

**Baseline role:** These numbers are the reference point for Test 04a (4-replica scaling should show ~1.5–2× RPS) and for contrasting Test 01a (where prefix-cache routing should dramatically improve warm-prefix TTFT and cache hit rate).

## Artifacts

| File | Description |
|---|---|
| `benchmark.csv` | GuideLLM summary metrics |
| `benchmark.json` | Full GuideLLM run record |
| `benchmark.log` | Complete GuideLLM stdout |
| `run-metadata.txt` | Gateway URL and time window |
| `prompt.txt` | LLM analysis prompt template |
| `grafana-page1.png` | *(add manually)* TTFT, cache, throughput panels |
| `grafana-page2.png` | *(add manually)* Token rate, E2E latency panels |
