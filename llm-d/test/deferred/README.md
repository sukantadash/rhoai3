# Deferred Test Scenarios

These llm-d features are documented in the test plan but not yet implemented in this repository. Add manifests here when configs become available.

| ID | Feature | Blocker |
|---|---|---|
| 01D | Predicted Latency Routing | No XGBoost sidecar or latency-scorer EPP plugin config |
| 02B | Hierarchical KV Offloading | No `--cpu-offload-gb` or llm-d FS backend (Lustre/Mooncake) |
| 04B | Multi-Node LWS + TP/EP | LWS operator present; no inference workload manifest for large models |
| 04C | LoRA Adapters | No `--enable-lora`, adapter mounts, or multi-adapter routing |
| 05A | Workload Variant Autoscaler (WVA) | No WVA CRDs or saturation analyzer config |
| 05B | Async Batch API | No batch gateway or `/v1/batch` endpoint config |

When implementing a deferred scenario, add a folder following the same pattern:

```
<scenario-id>/
├── llminferenceservice.yaml
├── guidellm-job.yaml
└── results/
```

Then register it in `common/env.sh` and `test-script.sh`.
