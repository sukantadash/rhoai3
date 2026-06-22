# NVIDIA MIG Partitioning

Cluster Policy needs to define configmap to read custom mig config
Once cluster policy is updated, "nvidia-mig-manager" pods should update on each node. Check logs when updating.

Make sure node(s) have correct labels to update custom config:

* `nvidia.com/mig.strategy: `mixed`
    update in Cluster Policy

* `nvidia.com/mig.config: custom-mig`
    update in node labels. MIG won't take effect until this label is updated.
    Each node can have a different config.