# Skill 7 — In-Cluster Lifecycle Hook Provisioning

**Role:** Webhook Integration Generator.

## Function
Generate Kubernetes manifests that automatically **trigger** the SRE loop
(`repository_dispatch`) when a deployment starts, succeeds, or fails — closing
the self-healing loop without a human pressing "Run workflow".

This skill runs **out-of-band** (it is a generator, not part of the runtime
loop). Its output is applied to target workloads once, then the cluster drives
the loop on its own.

## Trigger Surfaces

| Surface | Fires on | Mechanism |
|---------|----------|-----------|
| `postStart` lifecycle hook | container start | inline `curl` → `repository_dispatch` |
| Argo/CD or Job post-sync | deploy success/fail | sidecar/Job → `repository_dispatch` |
| Failure watcher CronJob | periodic scan for bad pods | in-cluster CronJob → `repository_dispatch` |

## Dispatch Payload Contract
Every trigger POSTs to `/repos/{org}/{repo}/dispatches` with:
```json
{
  "event_type": "aks-deployment-success",   // or aks-deployment-failure
  "client_payload": {
    "mode": "auto",
    "namespace": "payments",
    "deployment": "api",
    "source": "postStart-hook"
  }
}
```
`event_type` must match a `repository_dispatch.types` entry in `sre-loop.yml`.
`client_payload` maps directly onto the workflow's env normalization.

## Security Requirements (enforced by the generator)
- **Never** inline a PAT in the manifest. Mount it from a Secret and reference
  `$GITHUB_PAT` in the command. The generator refuses to emit a literal token.
- Use a fine-grained PAT scoped to `contents:read` + `dispatch` on one repo.
- Prefer a dedicated sidecar/Job over `postStart` for anything beyond a fire-and-
  forget ping (`postStart` has no retry and can block pod startup).

## Generated Artifacts
- `manifests/deployment-poststart-hook.yaml` — annotated Deployment with a
  Secret-backed `postStart` dispatch (the pattern from the project brief, hardened).
- `manifests/failure-dispatch-cronjob.yaml` — CronJob that scans for
  `CrashLoopBackOff`/`ImagePullBackOff` pods and dispatches `aks-deployment-failure`.

## Contract
Produces: Kubernetes YAML manifests (validated with `kubectl apply --dry-run=server`).
