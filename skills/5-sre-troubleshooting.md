# Skill 5 — Kubernetes SRE Troubleshooting

**Role:** Incident Response & Remediation.

## Function
Deep-dive into the components flagged by the Health Check, determine root cause,
and — depending on mode — either propose or apply a fix.

## Diagnostic Deep-Dive
For each finding, collect and analyze:
- **Termination codes** — exit code + reason (`137`→OOMKilled, `1`→app error,
  `143`→SIGTERM, `127`→missing binary).
- **Events** — `kubectl describe` FailedScheduling / probe failures / BackOff.
- **Resource limits** — requests/limits vs. observed usage; OOM correlation.
- **Logs** — current and `--previous` container logs; probe endpoints.
- **Config** — referenced ConfigMaps/Secrets exist and are mounted;
  image tag resolvable (ImagePull faults).

## Root-Cause → Remediation Mapping (non-destructive whitelist)

| Root cause | `review` output | `auto` action |
|------------|-----------------|---------------|
| Transient crash / stuck rollout | RCA + suggest restart | `kubectl rollout restart deploy/<x>` |
| OOMKilled (bursty) | RCA + suggest limit bump | Scale replicas (spread load) — **not** limit edits |
| Under-replicated / load | RCA + suggest scale | `kubectl scale --replicas=N` (within HPA bounds) |
| Stuck/terminating pod | RCA + suggest delete | `kubectl delete pod <x>` (controller recreates) |
| ImagePullBackOff (bad tag) | RCA + flag | **No auto action** — escalate (needs image fix) |
| Missing ConfigMap/Secret | RCA + flag | **No auto action** — escalate (needs manifest change) |
| Node pressure | RCA + flag | **No auto action** — escalate (cluster capacity) |

> Anything not on the whitelist is **escalate-only**, in every mode. Destructive
> or config-mutating fixes are never applied autonomously. See `docs/SAFETY.md`.

## Mode Behavior
- **`review`** — produce a Root Cause Analysis and a *proposed* remediation plan.
  Apply nothing. Set `plan.applied = false`.
- **`auto`** — formulate a safe plan from the whitelist and execute it. Record
  every command, its exit status, and the object state before/after.
- **`chat`** — present the proposed plan to the operator, await confirmation,
  then execute the approved subset.

## Output — Remediation Plan
Conforms to `schemas/remediation-plan.schema.json`:

```json
{
  "target": {"kind": "Deployment", "namespace": "payments", "name": "api"},
  "root_cause": "Container OOMKilled (exit 137) under peak load; single replica.",
  "actions": [
    {"type": "scale", "command": "kubectl -n payments scale deploy/api --replicas=3",
     "destructive": false, "applied": true, "result": "ok", "rollback": "scale --replicas=1"}
  ],
  "escalated": false,
  "confidence": 0.72
}
```

Reference implementation: `scripts/remediate.sh`.
