# Skill 4 — Kubernetes Health Check

**Role:** Diagnostic Engine.

## Function
Assess cluster and workload health, produce a structured **Cluster Health
Report**, and decide the next hop:
- **Health-check-only** run (`review`, or `auto` with no issue) → alert via Slack.
- **Remediation** run (`auto`/`chat` **and** an issue is detected) → hand control
  to the SRE Troubleshooting Skill (#5).

## Dimensions Assessed

| Layer | Signals |
|-------|---------|
| **Nodes** | `Ready` condition, `MemoryPressure`/`DiskPressure`/`PIDPressure`, unschedulable/cordoned |
| **Storage** | PVC phase (`Pending`/`Lost`), PV bind status, capacity |
| **Workloads** | Deployment/StatefulSet `.status` desired vs. available replicas, stuck rollouts |
| **Pods** | `CrashLoopBackOff`, `ImagePullBackOff`/`ErrImagePull`, `OOMKilled`, `Pending` (unschedulable), `Evicted`, high `restartCount` |
| **Events** | `Warning` events in window (FailedScheduling, BackOff, Unhealthy probes) |

## Health Report (structured)
Conforms to `schemas/health-report.schema.json`:

```json
{
  "timestamp": "2026-07-21T17:40:00Z",
  "scope": {"namespace": "payments", "target": ""},
  "healthy": false,
  "summary": "1 deployment degraded; 2 pods in CrashLoopBackOff.",
  "findings": [
    {
      "kind": "Pod",
      "namespace": "payments",
      "name": "api-7c9f-abc12",
      "condition": "CrashLoopBackOff",
      "severity": "critical",
      "evidence": {"restartCount": 14, "lastExitCode": 137, "reason": "OOMKilled"}
    }
  ],
  "signature": "payments/api:CrashLoopBackOff:OOMKilled"
}
```

The `signature` is a stable fingerprint of the problem state — the Orchestrator
uses it for no-progress detection across iterations.

## Routing Logic
```
if healthy: notify Slack (green), return CONVERGED
else:
    if mode == review:          emit report, hand off findings to Skill 5 for RCA only
    if mode in (auto, chat):    hand off findings to Skill 5 for remediation
    always: alert Slack with the report summary
```

Reference implementation: `scripts/health-check.sh`.
