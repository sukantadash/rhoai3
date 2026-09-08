# Test 03a — Prefill/Decode Separation Results

**Status:** PARTIAL PASS  
**Date:** 2026-09-05  
**Scenario:** `03a-pd-separation`  
**Model:** `RedHatAI/Qwen3-8B-FP8-dynamic`  
**Deployment:** `qwen-pd` — 1 prefill + 1 decode replica  
**Gateway:** `https://inference-gateway.apps.cluster-nqcv7.nqcv7.sandbox340.opentlc.com/demo-llm/qwen-pd`

## Summary

GuideLLM completed a **10-phase sweep** (1024 prompt / 1024 output tokens, 120 s per phase) over **~21 minutes**. **185 requests completed** with **0 errors**; **531 incomplete** (mostly from the high-concurrency throughput sweep phase where only 32 of 543 started requests finished within 120 s).

Both P/D pools remained **Ready** throughout the run (prefill and decode on separate GPU nodes). **NIXL** and **NixlPullConnector** initialized on both vLLM pods. However, **no `kv_transfer_params.do_remote_prefill` / `do_remote_decode` log lines** were found, and EPP routed **87 decode-only** profile decisions with **zero `run_prefill`** events. The `pd-profile-handler` **threshold is 30,000 tokens** while the GuideLLM workload uses **1,024-token prompts**, so disaggregated prefill was never triggered.

**Prometheus:** vLLM dashboard metrics (TTFT, cache hit, throughput) are **not retrievable** for this window — TSDB head minimum time (`18:00:00Z`) is after the benchmark ended (`17:44:40Z`). **EPP pool metrics** are available and show 2 ready endpoints with queue buildup under load.

## Test Configuration

| Parameter | Value |
|---|---|
| GuideLLM profile | `sweep`, `sweep_size=10`, `max_concurrency=512` |
| Duration | 120 seconds per phase (`max_duration` constraint) |
| Data | `synthetic_text`, **1024 prompt / 1024 output tokens** |
| EPP plugins | `pd-profile-handler` (threshold **30000**), `prefill-header-handler`, `prefill-filter`, `decode-filter`, `random-picker` |
| vLLM | NixlConnector (`kv_role: kv_both`), `--block-size 128` |
| GPUs | 1 prefill (`ip-10-0-43-194`) + 1 decode (`ip-10-0-46-104`) |

Source: `guidellm-job.yaml`, `llminferenceservice.yaml`, `benchmark.csv`, `benchmark.json`.

## Run Window

From `run-metadata.txt` and `benchmark.json`:

| | Timestamp (UTC) |
|---|---|
| Job start | 2026-09-05T17:23:11Z |
| GuideLLM measure window | **2026-09-05T17:23:25Z → 17:44:40Z** (~21 min, 10 × 120 s phases) |
| Job end | 2026-09-05T17:59:22Z |
| Results collected | 2026-09-05T18:01:25Z |
| Job pod | `guidellm-03a-pd-separation-dv76s` |
| Namespace | `demo-llm` |
| Prefill pod | `qwen-pd-kserve-prefill-578798f45c-msfbv` |
| Decode pod | `qwen-pd-kserve-6b848bc84f-z6zsb` |

## GuideLLM Results

Aggregate across all 10 sweep phases:

| Metric | Value |
|---|---|
| Requests successful | **185** |
| Requests incomplete | **531** |
| Requests errored | **0** |
| Error rate | **0%** |
| Total measure time | ~21 min (10 phases × 120 s) |

### Per-phase highlights

| Phase | Strategy | Successful | Incomplete | RPS (mean) | TTFT p50 (ms) | TTFT p95 (ms) | E2E p50 (s) | Concurrency |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 0 | synchronous | 8 | 0 | 0.06 | **78.9** | 137.8 | 15.5 | 1.0 |
| 1 | throughput | 32 | 511 | 0.26 | **1811.1** | 2743.7 | 113.8 | 30.6 |
| 2–9 | constant | 9–27 | 1–4 | 0.08–0.23 | **110–117** | 120–125 | 15.8–16.9 | 1.2–3.8 |

**Token shape (all completed requests):** ~1032 input tokens, ~1024 output tokens per request (full 1024/1024 workload as configured).

**Throughput sweep (phase 1)** dominated incompletes: 32 completed vs 511 incomplete at ~31 mean concurrency on a single decode GPU with 1024-token generations (~16 s E2E each). Constant phases completed steadily with TTFT **~110–117 ms** (higher than Test 00 baseline ~50 ms server-side, expected for long-prompt P/D path overhead even in decode-only mode).

## Prometheus / Grafana Data

**Source:** Prometheus `query_range` API in `llm-d-monitoring` (same PromQL family as [`grafana-dashboard-llm-performance.json`](../../instances/llm-d-monitoring/grafana-dashboard-llm-performance.json))  
**Window:** `2026-09-05T17:23:25Z` → `17:44:40Z` (epoch 1788629005–1788630280)  
**Filters:** `kubernetes_namespace=demo-llm`, pool `qwen-pd-inference-pool`

### vLLM panels — not available

Prometheus TSDB head minimum time is **2026-09-05T18:00:00Z**, which is **after** the benchmark ended. No `vllm:*` time series exist for the measure window. TTFT, cache-hit-rate, GPU cache, and per-pod vLLM throughput panels cannot be populated from Prometheus for this run. Use GuideLLM client-side latency tables above as the primary latency source.

### EPP pool metrics (available)

| Panel | Pool / Series | Last | Mean | Min | Max |
|---|---|---:|---:|---:|---:|
| **EPP Ready Pods** | `qwen-pd-inference-pool` | **2** | **2** | 2 | 2 |
| **EPP Average Queue Size** | `qwen-pd-inference-pool` | **0** | **17.2** | 0 | **200** |
| **EPP KV Cache Pool Utilization** | `qwen-pd-inference-pool` | **2%** | **5.2%** | 0% | **50%** |
| **Per-Pod Queue Size (EPP)** | rank 0 | **0** | **33.9** | 0 | **398** |
| **Per-Pod Queue Size (EPP)** | rank 1 | **0** | **0** | 0 | 0 |

EPP shows **2 ready endpoints** (prefill + decode) for the entire window. Queue depth spiked during the throughput sweep (max **200** average, **398** on one rank). KV pool utilization reached **50%** peak — the first non-zero EPP KV metric observed across Tests 01a–02a.

Save screenshots as `grafana-page1.png` and `grafana-page2.png` in this directory for archival (vLLM panels will be empty for this historical window unless captured live during the run).

## P/D Routing & KV Transfer Evidence

### vLLM startup (both pools)

Both pods initialized **NIXL** and **NixlPullConnector**:

```
NIXL is available
NixlConnector setting KV cache layout to HND for better xfer performance.
Creating v1 connector with name: NixlPullConnector
kv_transfer_config: KVTransferConfig(kv_connector='NixlConnector', kv_role='kv_both', ...)
```

### Request-path logs (TESTPLAN step 2)

Searched decode and prefill pod logs for `kv_transfer_params.do_remote_prefill` / `do_remote_decode`:

| Search | Decode pod | Prefill pod |
|---|---|---|
| `do_remote_prefill` / `do_remote_decode` | **0 matches** | **0 matches** |
| `kv_transfer_params` | startup config only | startup config only |

### EPP scheduler decisions (during benchmark)

| EPP decision | Count |
|---|---:|
| `complete_decode-only` | **87** |
| `run_prefill` | **0** |
| `no_prefill_profile_result` | present on all sampled traces |

**Likely cause:** `pd-profile-handler` threshold is **30,000 tokens** in the manifest, but GuideLLM sends **1,024-token** prompts (per TESTPLAN). Prompts below the threshold are routed **decode-only**, so the prefill pool stays idle and NIXL KV transfer is never exercised on the request path.

## Comparison vs Test 00 (baseline)

| Metric | **00** (2 replicas, colocated) | **03a** (1P + 1D, decode-only routing) |
|---|---|---|
| Workload | 50 prompt / 50 output tokens | **1024 / 1024 tokens** |
| TTFT (light load) | ~50 ms server, ~57 ms client | **~79 ms** client (phase 0) |
| E2E (light load) | ~688–749 ms | **~15.5 s** (1024-token generation) |
| Error rate | 0% | **0%** |
| Pools | 2 identical decode pods | 1 prefill + 1 decode (prefill unused) |

Long-output latency dominates E2E; TTFT at low concurrency is ~1.5× baseline, consistent with gateway + single-decode bottleneck under a 1024-token prefill workload without active P/D split.

## TESTPLAN Validation

Per [TESTPLAN.md](../../TESTPLAN.md) — Test 03a Prefill/Decode Separation:

| Pass criterion | Evidence | Result |
|---|---|---|
| Both pools healthy | `LLMInferenceService` Ready; EPP **2 ready pods** entire window; prefill + decode pods Running on separate GPU nodes | **PASS** |
| KV transfer visible in logs (`do_remote_prefill` / `do_remote_decode`) | **0** request-path matches; EPP **decode-only** routing (87×); NIXL initialized but not used for transfer | **FAIL** |

**Overall:** Infrastructure and P/D **deployment** validated (separate pools, NIXL configured, 0% errors on completed requests). **Functional P/D disaggregation and KV transfer were not exercised** because the 30,000-token `pd-profile-handler` threshold exceeds the 1,024-token GuideLLM prompt size. Recommend re-running with `threshold` ≤ 1024 (or longer prompts) to satisfy the KV-transfer log criterion.

## Analysis

**Deployment topology confirmed:** After adding `prefill.template` GPU resources, prefill (`…-msfbv` on `ip-10-0-43-194`) and decode (`…-z6zsb` on `ip-10-0-46-104`) landed on **different GPU nodes**, resolving the earlier co-location OOM failure.

**Decode-only routing:** EPP `pick_disagg_profile` consistently chose `complete_decode-only` with `no_prefill_profile_result`. The prefill deployment consumed a GPU but received no profile-routed traffic during the benchmark. This explains absent `do_remote_prefill` log lines despite a healthy prefill pod.

**Load characteristics:** With 1024-token outputs (~16 s per request on one decode GPU), the sweep's throughput phase (phase 1) queued heavily — **511 incomplete** requests. Constant phases completed **9–27 requests** per 120 s as concurrency ramped (~0.08–0.23 RPS). This is expected for a single-GPU decode pool on long generations.

**Observability gap:** Collect Grafana screenshots during the run, or ensure Prometheus retention covers the measure window. vLLM recording rules were unavailable post-run due to TSDB reset at 18:00 UTC.

## Artifacts

| File | Description |
|---|---|
| `benchmark.csv` | GuideLLM summary metrics (10 sweep rows) |
| `benchmark.json` | Full GuideLLM JSON results |
| `benchmark.log` | Complete GuideLLM stdout |
| `run-metadata.txt` | Gateway URL and time window |
| `prompt.txt` | LLM analysis prompt template |
| `grafana-page1.png` | *(add manually)* TTFT, cache hit, throughput panels |
| `grafana-page2.png` | *(add manually)* Token rate, E2E latency, EPP panels |
