# MaaS Architecture

| Document | Topology | When to use |
|----------|----------|-------------|
| [multicluster-maas-llmd.md](multicluster-maas-llmd.md) | MaaS (CPU) + llm-d (GPU), overlays 12–13 | PoC, Wells Fargo demo, single remote model cluster |
| [maas.md](maas.md) | MaaS + 2 GPU clusters + shared LB | Production HA, multi-model routing at load balancer |

## Quick links

- **Deploy MaaS control plane:** [../README.md](../README.md)
- **Deploy llm-d on GPU cluster:** [../../llm-d/README.md](../../llm-d/README.md)
- **Runbook (overlays 12–13):** [../maas-script.sh](../maas-script.sh)
