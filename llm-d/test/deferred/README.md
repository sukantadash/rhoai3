# Deferred Test Scenarios

These llm-d features are documented in the RHOAI 3.5 guide and test plan but not yet implemented in this repository. Add manifests here when configs become available.

| ID | Feature | PDF ref | Blocker |
| --- | --- | --- | --- |
| 01E | Predicted Latency Routing (`latency-scorer`, `predicted-latency-producer`) | Ch.10 plugins | No latency predictor sidecar or EPP plugin config |
| 02B | Hierarchical KV Offloading | upstream llm-d | No `--cpu-offload-gb` or llm-d FS backend (Lustre/Mooncake) |
| 04B | Multi-Node LWS + TP/EP | 5.6.2, Ch.9 | LWS operator present; no inference workload manifest for large models |
| 04C | LoRA Adapters | — | No `--enable-lora`, adapter mounts, or multi-adapter routing |
| 04D | WideEP / DP-Aware Rank Routing | RHOAI Inference 3.5 Ch.3 | No external multi-port DP mode manifests or rank-level EPP config |
| 05A | Workload Variant Autoscaler (WVA) | Ch.9 | No WVA CRDs or saturation analyzer config |
| 05B | Async Batch API | Ch.8 | No `LLMBatchGateway`, Redis/PostgreSQL backing services, or `/v1/batches` endpoint |
| 07A | Flow Control + Priority Queuing | Ch.7 | No `flowControl` feature gate or `InferenceObjective` CRs |

When implementing a deferred scenario, add a folder following the same pattern:

```
<scenario-id>/
├── llminferenceservice.yaml
├── guidellm-job.yaml
└── results/
```

Then register it in `common/env.sh` and `test-script.sh`.
