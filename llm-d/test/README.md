# llm-d Feature Validation Testing Framework

Repeatable, scenario-based test harness for validating **llm-d** features on OpenShift. Each scenario deploys a specific `LLMInferenceService` configuration, generates load with [GuideLLM](https://github.com/vllm-project/guidellm), and correlates results with **Prometheus/Grafana** dashboards.

The goal is to prove that llm-d routing, caching, and scheduling features produce measurable performance wins — not just that the cluster is up.

For detailed objectives, pass criteria, and troubleshooting, see [TESTPLAN.md](TESTPLAN.md).

## How it works

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  test-script.sh │────▶│ LLMInferenceSvc  │────▶│  vLLM replicas  │
│  (orchestrator) │     │  (per scenario)  │     │  + llm-d EPP    │
└────────┬────────┘     └──────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  GuideLLM Job   │────▶│  Gateway (HTTPS) │
│  (K8s batch)    │     │  demo-llm/qwen   │
└────────┬────────┘     └──────────────────┘
         │
         ▼
┌─────────────────┐
│  results/       │  benchmark.json, benchmark.csv, run-metadata.txt
└─────────────────┘
```

Each scenario is a self-contained directory with:

| File | Purpose |
|---|---|
| `llminferenceservice.yaml` | Model deployment + EPP scheduler config for that feature |
| `guidellm-job.yaml` | Traffic pattern tuned to exercise the feature |
| `results/` | Collected benchmark output (see `.gitignore`; commit `RESULTS.md` when documenting runs) |

The orchestrator (`test-script.sh`) handles deploy → smoke test → benchmark → collect → cleanup.

## Prerequisites

1. Base cluster deployed via [`../llmd-script.sh`](../llmd-script.sh) (GPU operators, RHOAI, gateway, `demo-llm` namespace, `test-user` RBAC).
2. Monitoring overlay applied: `oc apply -k ../overlays/09-llm-d-monitoring/`
3. `ghcr-pull-secret` in `demo-llm` namespace (for GuideLLM image).
4. Logged in to cluster: `oc whoami`
5. GPU capacity per scenario (see table below).

## Quick start

```bash
cd rhoai3/llm-d/test

# Verify cluster, gateway, and monitoring
./test-script.sh setup

# Run one scenario end-to-end (~5–10 min depending on scenario)
./test-script.sh run 00-baseline

# Run the full suite (keeps deployment between related scenarios)
./test-script.sh run-all
```

### Commands

| Command | Description |
|---|---|
| `setup` | Verify cluster access, gateway, and monitoring |
| `run <scenario>` | Deploy model, run benchmark, collect results, cleanup |
| `run-all` | Run all scenarios in order |
| `deploy <scenario>` | Apply `llminferenceservice.yaml` and wait for Ready |
| `benchmark <scenario>` | Apply `guidellm-job.yaml` and wait for completion |
| `collect <scenario>` | Copy benchmark results to `<scenario>/results/` |
| `cleanup <scenario>` | Delete GuideLLM job for scenario |
| `cleanup-all` | Delete all test jobs and LLMInferenceServices |

## Scenario coverage

| ID | Scenario | Feature under test | GPUs | Deploy? |
|---|---|---|---|---|
| **00** | `00-baseline` | Baseline throughput | 2 | Yes |
| **01a** | `01a-prefix-cache-routing` | Prefix-cache aware routing | 2 | Yes |
| **01b** | `01b-queue-kv-scheduling` | Queue + KV utilization scheduling | 2 | No (reuses 01a) |
| **01c** | `01c-round-robin-control` | Round-robin control (A/B vs 01a) | 2 | Yes |
| **02a** | `02a-global-cache-indexing` | Global cache indexing | 2 | Yes |
| **03a** | `03a-pd-separation` | Prefill/decode separation | 2 | Yes |
| **03b** | `03b-pd-kv-transfer` | KV direct transfer (NIXL) | 2 | No (reuses 03a) |
| **03c** | `03c-heterogeneous-pd` | Heterogeneous P/D workloads | 2 | No (reuses 03a) |
| **04a** | `04a-data-parallelism` | 4-replica data parallelism | 4 | Yes |

Some scenarios reuse the previous deployment to avoid unnecessary redeploys.

## Reading results

After `./test-script.sh run <scenario>` (or `collect`), artifacts land in `<scenario>/results/`:

- **`benchmark.json` / `benchmark.csv`** — GuideLLM metrics (TTFT, ITL, RPS, error rate)
- **`run-metadata.txt`** — Gateway URL, benchmark time window (use this for Grafana)
- **`benchmark.log`** — Full GuideLLM output
- **`prompt.txt`** — LLM prompt template for generating `RESULTS.md`
- **`grafana-page*.png`** — Grafana screenshots (added manually after each run)
- **`RESULTS.md`** — Test result analysis (generated from prompt + artifacts above)

### Step 1 — Review benchmark artifacts

Inspect `benchmark.csv` and `run-metadata.txt` for throughput, latency, and error rate. Note `start_time` and `end_time` from `run-metadata.txt` — you will need them for Grafana.

### Step 2 — Capture Grafana screenshots

1. Open the LLM Performance dashboard in Grafana:

   ```bash
   oc get route grafana-secure -n llm-d-monitoring -o jsonpath='{.spec.host}'
   ```

2. Set the time range to `start_time` → `end_time` from `run-metadata.txt`.
3. Capture screenshots of the panels relevant to the scenario (see [TESTPLAN.md](TESTPLAN.md) for which metrics to watch per test).
4. Save screenshots in `<scenario>/results/` (e.g. `grafana-page1.png`, `grafana-page2.png`).

### Step 3 — Generate test result analysis with an LLM

Each scenario's `results/` directory includes a **`prompt.txt`** with instructions for analyzing that run. Pass the prompt to an LLM (Cursor, ChatGPT, etc.) together with all test artifacts:

- `benchmark.csv`
- `benchmark.json`
- `run-metadata.txt`
- Grafana screenshots from Step 2

Ask the LLM to produce **`RESULTS.md`** in `<scenario>/results/`. The analysis should explain the benchmark numbers, embed the Grafana screenshots, and validate outcomes against the pass criteria in [TESTPLAN.md](TESTPLAN.md).

See `00-baseline/results/RESULTS.md` and `01a-prefix-cache-routing/results/RESULTS.md` for examples.

### Example pass criteria (01a — prefix cache routing)

- Warm-prefix TTFT at least **5× faster** than cold-start TTFT
- One pod receives **>70%** of cache hits
- GuideLLM error rate **< 1%**

Each scenario in [TESTPLAN.md](TESTPLAN.md) has its own objective, expected Grafana signals, and pass/fail criteria.

## Repo layout

```
test/
├── README.md               # This file
├── TESTPLAN.md             # Full test plan with pass criteria
├── test-script.sh          # Main orchestrator
├── common/
│   ├── env.sh              # Shared config (namespace, model, gateway)
│   └── collect-results.sh  # Pulls results from GuideLLM pod
├── 00-baseline/
├── 01a-prefix-cache-routing/
├── ...
└── deferred/               # Future scenarios (see deferred/README.md)
```

## Adding a new scenario

1. Create a directory with `llminferenceservice.yaml` and `guidellm-job.yaml`.
2. Register it in `common/env.sh` (service name, job name, deploy flag).
3. Add it to `RUN_ALL_SCENARIOS` and the `test-script.sh` usage block.
4. Document objectives and pass criteria in [TESTPLAN.md](TESTPLAN.md).

## Further reading

- [TESTPLAN.md](TESTPLAN.md) — Detailed steps, pass criteria, troubleshooting
- [../README.md](../README.md) — Cluster deployment
- [deferred/README.md](deferred/README.md) — Planned scenarios not yet configured
