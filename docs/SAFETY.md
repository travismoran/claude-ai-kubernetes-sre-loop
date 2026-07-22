# Safety Model & Guardrails

The engine can modify a live cluster in `auto` mode. This document is the
contract for what it may and may not do. **Read before enabling `auto` in prod.**

## 1. Non-Destructive Whitelist
`auto` mode may only take actions on this list. Everything else is escalate-only.

| Allowed (reversible) | Forbidden (never autonomous) |
|----------------------|------------------------------|
| `rollout restart` a Deployment | Editing resource limits/requests |
| `scale --replicas` within HPA bounds | Deleting Deployments/StatefulSets/PVCs |
| Deleting a single stuck/terminating **pod** (controller recreates) | `kubectl apply` of new manifests |
| Annotating for tracking | Draining/deleting nodes |
| — | Editing Secrets/ConfigMaps |
| — | Anything touching image tags or registries |

Every applied action records a `rollback` command in the RemediationPlan.

## 2. Anti-Repeat Guard (loop bounding)
A remediation is fingerprinted (`type:namespace/name`). If that fingerprint is
in `memory/latest.json → failed_actions[]`, the Orchestrator refuses to re-apply
and escalates instead. This prevents restart-thrash and infinite loops.

## 3. Bounded Iteration
`MAX_ITERATIONS` (default 3) caps the loop. On exhaustion, the run exits
non-zero and pages on-call via Slack.

## 4. No-Progress Detection
If the health `signature` is identical before and after a remediation that
"succeeded", the engine treats the fix as ineffective and escalates.

## 5. Context Guard
Pre-flight aborts if `kubectl` current-context does not match
`AKS_CLUSTER_NAME`. The loop never runs against an unexpected cluster.

## 6. Concurrency
GitHub Actions `concurrency` serializes runs per namespace so two loops never
remediate the same target simultaneously.

## 7. Least Privilege
- Azure SP: read for `review`; scoped write only where remediation is intended.
- In-cluster trigger PAT: fine-grained, `contents:write` + `dispatch`, single repo.
- Watcher ServiceAccount: `get/list pods` only.

## 8. Progressive Rollout Recommendation
Enable per environment in order: `review` (observe only) → `chat` (human
approves each action) → `auto` in non-prod → `auto` in prod for one namespace →
broaden. Never skip straight to cluster-wide `auto`.
