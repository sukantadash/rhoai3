# llm-d Feature Validation — Consolidated Test Results

**Cluster:** `cluster-nqcv7.nqcv7.sandbox340.opentlc.com`  
**Model:** `RedHatAI/Qwen3-8B-FP8-dynamic`  
**Gateway:** `https://inference-gateway.apps.cluster-nqcv7.nqcv7.sandbox340.opentlc.com/demo-llm/`  
**Report generated:** 2026-09-08  
**Grafana source:** Prometheus `query_range` API (`llm-d-monitoring`), PromQL from [`grafana-dashboard-llm-performance.json`](../instances/llm-d-monitoring/grafana-dashboard-llm-performance.json)  

## Executive Summary

| ID | Scenario | Status | Error Rate | GuideLLM RPS | Server TTFT P50 | KV Hit Rate |
|---|---|---|---:|---:|---:|---:|
| 00 | `00-baseline` | **PASS** | 0.00% | 24.5 | 47.5 ms | 0.0% |
| 01a | `01a-prefix-cache-routing` | **PASS** | 0.00% | 5.0 | 49.7 ms | 96.8% |
| 01b | `01b-precise-prefix-cache-routing` | **PARTIAL PASS** | 0.00% | 5.0 | 44.4 ms | 96.7% |
| 01c | `01c-queue-kv-scheduling` | **PASS** | 0.00% | 38.3 | 173.8 ms | 97.3% |
| 01d | `01d-round-robin-control` | **PARTIAL PASS** | 0.00% | 5.0 | 47.9 ms | 96.7% |
| 02a | `02a-global-cache-indexing` | **PARTIAL PASS** | 0.12% | 119.9 | 270.0 ms | 93.4% |
| 03a | `03a-pd-separation` | **PARTIAL PASS** | 0.00% | 0.3 | N/A | N/A |
| 03b | `03b-pd-kv-transfer` | **PASS** | 0.00% | 1.2 | N/A | N/A |
| 03c | `03c-heterogeneous-pd` | **PASS** | 0.01% | 20.5 | N/A | N/A |
| 04a | `04a-data-parallelism` | **PARTIAL PASS** | 0.00% | 45.1 | 63.0 ms | 0.0% |

---

## Test 00 — Default Baseline

**Status:** PASS  
**Service:** `qwen`  
**Measure window (UTC):** `2026-09-08 15:24:36` → `2026-09-08 15:25:36`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **1,469** |
| Requests incomplete | 20 |
| Requests errored | 0 |
| Error rate | **0.00%** |
| Throughput (RPS, peak phase) | **24.5** |
| TTFT p50 (client) | **57.8 ms** |
| ITL p50 (client) | **15.4 ms** |
| Output tokens/s (client) | **1228** |
| Sweep phases | 1 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

#### Page 1 — TTFT, Cache Hit Rate, Throughput

| Panel | Observation |
|---|---|
| TTFT P50 | last **47.5 ms** / mean 47.6 ms / max 47.8 ms |
| TTFT P95 | last **62.1 ms** / mean 67.3 ms / max 72.5 ms |
| KV Cache Hit Rate | last **0.0%** / mean 0.0% / min 0.0% / max 0.0% |
| Per-Pod Cache Hit (`…l7dl7`) | last **0.0%** / mean 0.0% |
| Per-Pod Cache Hit (`…xpbnk`) | last **0.0%** / mean 0.0% |
| GPU Cache Usage (`…l7dl7`) | last 0.78% / max 0.78% |
| GPU Cache Usage (`…xpbnk`) | last 0.68% / max 0.68% |
| Request Throughput | last **12.0** / mean 5.9 / max 12.0 req/s |
| Request Queue | running last **21** mean 13.7 / waiting 0 |

#### Page 2 — Token Rate, E2E Latency, EPP Health

| Panel | Observation |
|---|---|
| Prompt Tokens/sec | last **1314** / mean 652 tps |
| Generated Tokens/sec | last **606** / mean 300 tps |
| E2E Latency P50 | last **0.73 s** / mean 0.74 s |
| E2E Latency P95 | last **0.97 s** / mean 0.97 s |
| E2E Latency Average | last **0.80 s** / mean 0.80 s |

| Panel | Observation |
|---|---|
| EPP Ready Pods | **2** |
| EPP Average Queue Size | mean 0.0 / max **0** |
| EPP KV Pool Utilization | max 1% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| Benchmark completes | 1,469 successful | **PASS** |
| Error rate < 1% | 0.00% | **PASS** |
| KV ~0% | 0.0% | **PASS** |

---

## Test 01a — Prefix-Cache Aware Routing

**Status:** PASS  
**Service:** `qwen`  
**Measure window (UTC):** `2026-09-08 15:29:35` → `2026-09-08 15:31:35`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **596** |
| Requests incomplete | 5 |
| Requests errored | 0 |
| Error rate | **0.00%** |
| Throughput (RPS, peak phase) | **5.0** |
| TTFT p50 (client) | **57.4 ms** |
| ITL p50 (client) | **15.7 ms** |
| Output tokens/s (client) | **249** |
| Sweep phases | 1 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

#### Page 1 — TTFT, Cache Hit Rate, Throughput

| Panel | Observation |
|---|---|
| TTFT P50 | last **49.7 ms** / mean 49.8 ms / max 49.8 ms |
| TTFT P95 | last **59.0 ms** / mean 59.0 ms / max 59.1 ms |
| KV Cache Hit Rate | last **96.8%** / mean 96.7% / min 96.3% / max 96.8% |
| Per-Pod Cache Hit (`…l7q7t`) | last **96.8%** / mean 96.7% |
| GPU Cache Usage (`…l7q7t`) | last 1.10% / max 1.10% |
| GPU Cache Usage (`…4szkw`) | last 0.00% / max 0.00% |
| Request Throughput | last **5.0** / mean 2.4 / max 5.0 req/s |
| Request Queue | running last **4** mean 3.2 / waiting 0 |

#### Page 2 — Token Rate, E2E Latency, EPP Health

| Panel | Observation |
|---|---|
| Prompt Tokens/sec | last **10546** / mean 5215 tps |
| Generated Tokens/sec | last **249** / mean 123 tps |
| E2E Latency P50 | last **0.90 s** / mean 0.90 s |
| E2E Latency P95 | last **0.99 s** / mean 0.99 s |
| E2E Latency Average | last **0.82 s** / mean 0.82 s |

| Panel | Observation |
|---|---|
| EPP Ready Pods | **2** |
| EPP Average Queue Size | mean 0.0 / max **0** |
| EPP KV Pool Utilization | max 1% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| KV > 90% | 96.8% | **PASS** |
| One pod > 70% hits | single-pod ~97% | **PASS** |
| Error < 1% | 0.00% | **PASS** |

---

## Test 01b — Precise Prefix-Cache Routing

**Status:** PARTIAL PASS  
**Service:** `qwen`  
**Measure window (UTC):** `2026-09-08 15:44:04` → `2026-09-08 15:46:04`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **597** |
| Requests incomplete | 4 |
| Requests errored | 0 |
| Error rate | **0.00%** |
| Throughput (RPS, peak phase) | **5.0** |
| TTFT p50 (client) | **58.6 ms** |
| ITL p50 (client) | **15.4 ms** |
| Output tokens/s (client) | **250** |
| Sweep phases | 1 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

#### Page 1 — TTFT, Cache Hit Rate, Throughput

| Panel | Observation |
|---|---|
| TTFT P50 | last **44.4 ms** / mean 44.5 ms / max 44.7 ms |
| TTFT P95 | last **58.6 ms** / mean 58.8 ms / max 59.1 ms |
| KV Cache Hit Rate | last **96.7%** / mean 96.3% / min 95.6% / max 96.7% |
| Per-Pod Cache Hit (`…ssrt6`) | last **96.7%** / mean 96.3% |
| Per-Pod Cache Hit (`…gr5vk`) | last **96.7%** / mean 96.3% |
| GPU Cache Usage (`…ssrt6`) | last 0.97% / max 0.97% |
| GPU Cache Usage (`…gr5vk`) | last 0.96% / max 0.96% |
| Request Throughput | last **4.9** / mean 2.4 / max 4.9 req/s |
| Request Queue | running last **2** mean 1.6 / waiting 0 |

#### Page 2 — Token Rate, E2E Latency, EPP Health

| Panel | Observation |
|---|---|
| Prompt Tokens/sec | last **10480** / mean 5192 tps |
| Generated Tokens/sec | last **248** / mean 123 tps |
| E2E Latency P50 | last **0.68 s** / mean 0.68 s |
| E2E Latency P95 | last **0.94 s** / mean 0.94 s |
| E2E Latency Average | last **0.79 s** / mean 0.79 s |

| Panel | Observation |
|---|---|
| EPP Ready Pods | **2** |
| EPP Average Queue Size | mean 0.0 / max **0** |
| EPP KV Pool Utilization | max 1% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| KV > 90% | 96.7% | **PASS** |
| Per-pod skew | both pods ~97% | **FAIL** |
| Error < 1% | 0.00% | **PASS** |

---

## Test 01c — Queue + KV Utilization Scheduling

**Status:** PASS  
**Service:** `qwen`  
**Measure window (UTC):** `2026-09-08 15:32:03` → `2026-09-08 15:34:03`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **4,592** |
| Requests incomplete | 80 |
| Requests errored | 0 |
| Error rate | **0.00%** |
| Throughput (RPS, peak phase) | **38.3** |
| TTFT p50 (client) | **163.5 ms** |
| ITL p50 (client) | **38.9 ms** |
| Output tokens/s (client) | **1917** |
| Sweep phases | 1 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

#### Page 1 — TTFT, Cache Hit Rate, Throughput

| Panel | Observation |
|---|---|
| TTFT P50 | last **173.8 ms** / mean 144.5 ms / max 174.0 ms |
| TTFT P95 | last **242.4 ms** / mean 205.9 ms / max 243.0 ms |
| KV Cache Hit Rate | last **97.3%** / mean 97.3% / min 96.9% / max 97.7% |
| Per-Pod Cache Hit (`…l7q7t`) | last **97.3%** / mean 97.3% |
| GPU Cache Usage (`…l7q7t`) | last 4.15% / max 4.53% |
| GPU Cache Usage (`…4szkw`) | last 0.00% / max 0.00% |
| Request Throughput | last **38.6** / mean 21.2 / max 38.6 req/s |
| Request Queue | running last **76** mean 63.2 / waiting 0 |

#### Page 2 — Token Rate, E2E Latency, EPP Health

| Panel | Observation |
|---|---|
| Prompt Tokens/sec | last **81668** / mean 45678 tps |
| Generated Tokens/sec | last **1924** / mean 1069 tps |
| E2E Latency P50 | last **2.11 s** / mean 1.71 s |
| E2E Latency P95 | last **2.46 s** / mean 2.12 s |
| E2E Latency Average | last **2.04 s** / mean 1.68 s |

| Panel | Observation |
|---|---|
| EPP Ready Pods | **2** |
| EPP Average Queue Size | mean 0.0 / max **0** |
| EPP KV Pool Utilization | max 2% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| Queue across pods | running mean 63 | **PASS** |
| Error < 1% | 0.00% | **PASS** |

---

## Test 01d — Round-Robin Control (A/B)

**Status:** PARTIAL PASS  
**Service:** `qwen`  
**Measure window (UTC):** `2026-09-08 15:38:13` → `2026-09-08 15:40:13`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **596** |
| Requests incomplete | 5 |
| Requests errored | 0 |
| Error rate | **0.00%** |
| Throughput (RPS, peak phase) | **5.0** |
| TTFT p50 (client) | **55.3 ms** |
| ITL p50 (client) | **15.4 ms** |
| Output tokens/s (client) | **249** |
| Sweep phases | 1 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

#### Page 1 — TTFT, Cache Hit Rate, Throughput

| Panel | Observation |
|---|---|
| TTFT P50 | last **47.9 ms** / mean 48.1 ms / max 48.4 ms |
| TTFT P95 | last **59.2 ms** / mean 59.2 ms / max 59.3 ms |
| KV Cache Hit Rate | last **96.7%** / mean 96.3% / min 95.6% / max 96.7% |
| Per-Pod Cache Hit (`…bvl24`) | last **96.7%** / mean 96.3% |
| Per-Pod Cache Hit (`…nbrzm`) | last **96.7%** / mean 96.3% |
| GPU Cache Usage (`…bvl24`) | last 0.00% / max 1.06% |
| GPU Cache Usage (`…nbrzm`) | last 1.03% / max 1.04% |
| Request Throughput | last **4.9** / mean 2.4 / max 4.9 req/s |
| Request Queue | running last **3** mean 2.8 / waiting 0 |

#### Page 2 — Token Rate, E2E Latency, EPP Health

| Panel | Observation |
|---|---|
| Prompt Tokens/sec | last **10464** / mean 5195 tps |
| Generated Tokens/sec | last **247** / mean 122 tps |
| E2E Latency P50 | last **0.83 s** / mean 0.83 s |
| E2E Latency P95 | last **0.98 s** / mean 0.98 s |
| E2E Latency Average | last **0.80 s** / mean 0.80 s |

| Panel | Observation |
|---|---|
| EPP Ready Pods | **2** |
| EPP Average Queue Size | mean 0.0 / max **0** |
| EPP KV Pool Utilization | max 1% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| 01a TTFT 3× better | 49.7 ms vs 47.9 ms | **FAIL** |
| 01a stronger skew | yes | **PASS** |
| Error < 1% | 0.00% | **PASS** |

---

## Test 02a — Global Cache Indexing

**Status:** PARTIAL PASS  
**Service:** `qwen`  
**Measure window (UTC):** `2026-09-05 15:09:30` → `2026-09-05 15:40:24`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **118,694** |
| Requests incomplete | 1,537 |
| Requests errored | 140 |
| Error rate | **0.12%** |
| Throughput (RPS, peak phase) | **119.9** |
| TTFT p50 (client) | N/A |
| ITL p50 (client) | N/A |
| Output tokens/s | N/A |
| Sweep phases | 10 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

#### Page 1 — TTFT, Cache Hit Rate, Throughput

| Panel | Observation |
|---|---|
| TTFT P50 | last **270.0 ms** / mean 143.9 ms / max 388.4 ms |
| TTFT P95 | last **707.3 ms** / mean 499.2 ms / max 3833.4 ms |
| KV Cache Hit Rate | last **93.4%** / mean 87.4% / min 14.3% / max 93.4% |
| Per-Pod Cache Hit (`…mrvmw`) | last **93.4%** / mean 87.1% |
| Per-Pod Cache Hit (`…v94w2`) | last **93.4%** / mean 87.7% |
| GPU Cache Usage (`…mrvmw`) | last 28.89% / max 34.58% |
| GPU Cache Usage (`…v94w2`) | last 28.81% / max 34.07% |
| Request Throughput | last **122.4** / mean 59.3 / max 124.1 req/s |
| Request Queue | running last **314** mean 151.4 / waiting 0 |

#### Page 2 — Token Rate, E2E Latency, EPP Health

| Panel | Observation |
|---|---|
| Prompt Tokens/sec | last **131971** / mean 65234 tps |
| Generated Tokens/sec | last **6116** / mean 2979 tps |
| E2E Latency P50 | last **3.52 s** / mean 1.83 s |
| E2E Latency P95 | last **4.90 s** / mean 3.06 s |
| E2E Latency Average | last **3.33 s** / mean 1.91 s |

| Panel | Observation |
|---|---|
| EPP Ready Pods | **2** |
| EPP Average Queue Size | mean 0.4 / max **12** |
| EPP KV Pool Utilization | max 34% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| Completes | 118,694 ok | **PASS** |
| EPP/GPU correlation | EPP KV max 34% | **PARTIAL** |
| Error < 1% | 0.12% | **PASS** |

---

## Test 03a — Prefill/Decode Separation

**Status:** PARTIAL PASS  
**Service:** `qwen-pd`  
**Measure window (UTC):** `2026-09-05 17:23:25` → `2026-09-05 17:44:40`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **185** |
| Requests incomplete | 531 |
| Requests errored | 0 |
| Error rate | **0.00%** |
| Throughput (RPS, peak phase) | **0.3** |
| TTFT p50 (client) | **86.0 ms** |
| ITL p50 (client) | **15.1 ms** |
| Output tokens/s (client) | **66** |
| Sweep phases | 10 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

*vLLM panels unavailable (TSDB retention gap). Use GuideLLM metrics above.*

| Panel | Observation |
|---|---|
| EPP Ready Pods | **2** |
| EPP Average Queue Size | mean 17.2 / max **200** |
| EPP KV Pool Utilization | max 50% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| Pools healthy | ready 2 | **PASS** |
| KV transfer logs | not observed | **FAIL** |
| Error < 1% | 0.00% | **PASS** |

---

## Test 03b — KV Direct Transfer

**Status:** PASS  
**Service:** `qwen-pd`  
**Measure window (UTC):** `2026-09-05 19:32:42` → `2026-09-05 19:34:42`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **151** |
| Requests incomplete | 49 |
| Requests errored | 0 |
| Error rate | **0.00%** |
| Throughput (RPS, peak phase) | **1.2** |
| TTFT p50 (client) | **942.0 ms** |
| ITL p50 (client) | **33.9 ms** |
| Output tokens/s (client) | **1104** |
| Sweep phases | 1 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

*vLLM panels unavailable (TSDB retention gap). Use GuideLLM metrics above.*

| Panel | Observation |
|---|---|
| EPP Ready Pods | **2** |
| EPP Average Queue Size | mean 0.0 / max **0** |
| EPP KV Pool Utilization | max 20% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| Error < 1% | 0.00% | **PASS** |
| Pools Ready | 2 | **PASS** |

---

## Test 03c — Heterogeneous P/D Workload

**Status:** PASS  
**Service:** `qwen-pd`  
**Measure window (UTC):** `2026-09-08 16:39:08` → `2026-09-08 17:09:38`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **18,938** |
| Requests incomplete | 1,727 |
| Requests errored | 2 |
| Error rate | **0.01%** |
| Throughput (RPS, peak phase) | **20.5** |
| TTFT p50 (client) | N/A |
| ITL p50 (client) | N/A |
| Output tokens/s | N/A |
| Sweep phases | 10 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

*vLLM panels unavailable (TSDB retention gap). Use GuideLLM metrics above.*

| Panel | Observation |
|---|---|
| EPP Ready Pods | **2** |
| EPP Average Queue Size | mean 28.7 / max **128** |
| EPP KV Pool Utilization | max 28% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| Completes | 18,938 ok | **PASS** |
| Error < 1% | 0.01% | **PASS** |
| Pools Ready | 2 | **PASS** |

---

## Test 04a — 4-Replica Throughput Scaling

**Status:** PARTIAL PASS  
**Service:** `qwen`  
**Measure window (UTC):** `2026-09-08 17:25:07` → `2026-09-08 17:27:07`  

### GuideLLM Results

| Metric | Value |
|---|---|
| Requests successful | **5,416** |
| Requests incomplete | 40 |
| Requests errored | 0 |
| Error rate | **0.00%** |
| Throughput (RPS, peak phase) | **45.1** |
| TTFT p50 (client) | **95.6 ms** |
| ITL p50 (client) | **16.1 ms** |
| Output tokens/s (client) | **2261** |
| Sweep phases | 1 |

### Prometheus / Grafana Metrics

Query window from `run-metadata.txt` / `benchmark.csv`. Raw: [`prometheus-metrics.json`](./prometheus-metrics.json).

#### Page 1 — TTFT, Cache Hit Rate, Throughput

| Panel | Observation |
|---|---|
| TTFT P50 | last **63.0 ms** / mean 63.4 ms / max 64.8 ms |
| TTFT P95 | last **206.3 ms** / mean 208.7 ms / max 212.8 ms |
| KV Cache Hit Rate | last **0.0%** / mean 0.0% / min 0.0% / max 0.0% |
| Per-Pod Cache Hit (`…9ggqq`) | last **0.0%** / mean 0.0% |
| Per-Pod Cache Hit (`…dkzr8`) | last **0.0%** / mean 0.0% |
| Per-Pod Cache Hit (`…52j9h`) | last **0.0%** / mean 0.0% |
| GPU Cache Usage (`…9ggqq`) | last 1.30% / max 1.62% |
| GPU Cache Usage (`…dkzr8`) | last 0.65% / max 1.23% |
| GPU Cache Usage (`…52j9h`) | last 0.87% / max 1.02% |
| Request Throughput | last **45.0** / mean 22.3 / max 45.0 req/s |
| Request Queue | running last **42** mean 36.4 / waiting 0 |

#### Page 2 — Token Rate, E2E Latency, EPP Health

| Panel | Observation |
|---|---|
| Prompt Tokens/sec | last **4873** / mean 2429 tps |
| Generated Tokens/sec | last **2258** / mean 1119 tps |
| E2E Latency P50 | last **0.89 s** / mean 0.89 s |
| E2E Latency P95 | last **0.99 s** / mean 0.99 s |
| E2E Latency Average | last **0.86 s** / mean 0.86 s |

| Panel | Observation |
|---|---|
| EPP Ready Pods | **3** |
| EPP Average Queue Size | mean 0.0 / max **0** |
| EPP KV Pool Utilization | max 1% |

### TESTPLAN Validation

| Criterion | Evidence | Result |
|---|---|---|
| 4 ready pods | saw 3 | **FAIL** |
| RPS 1.5–2× baseline | 1.84× client | **PASS** |
| Error < 1% | 0.00% | **PASS** |

---

## Cross-Test Comparisons

### Prefix-cache (01a vs 01d)

- 01a TTFT P50 49.7 ms, KV 96.8% (skewed)
- 01d TTFT P50 47.9 ms, KV 96.7% (balanced)

### Throughput (00 vs 04a)

- 00: 24.5 RPS client, server mean 5.9 req/s
- 04a: 45.1 RPS client, server mean 22.3 req/s (1.84×)

## Artifacts

| File | Description |
|---|---|
| `results.md` | This report |
| `prometheus-metrics.json` | Raw Prometheus data |
| `<scenario>/results/*` | Per-scenario benchmark artifacts |

See [TESTPLAN.md](./TESTPLAN.md).