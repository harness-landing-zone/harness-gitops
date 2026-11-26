# GitOps Agents

One YAML file per Org GitOps Agent (`agents/<agent>.yaml`).

- **Filename** (`<agent>`) is the agent's immutable name **and** its Kubernetes namespace on the hub (e.g. `agents/bu1-dev.yaml` deploys into namespace `bu1-dev` and registers Harness agent `bu1_dev`).
- Naming the namespace after the agent lets one tenant run multiple agents side by side (e.g. `bu1-dev` and `bu1-prod`) without namespace collisions.
- `fleet/agents.yaml` runs with `preserveResourcesOnDeletion: true` and `applicationsSync: create-update` so deleting a file here never accidentally deregisters a live Harness agent.

## Schema

```yaml
tenant: bu1          # Required: Harness organization identifier (^[a-z][a-z0-9]*$)
environment: dev     # Optional: DNS-1123 environment label
```

## Target clusters

Target clusters for an agent live separately under `clusters/<agent>/*.yaml` (see [clusters/README.md](../clusters/README.md)) so clusters can be added, rotated, or removed anytime without touching the agent's lifecycle.
