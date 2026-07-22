# Skill 2 — Dependencies & Tooling Verification (Ancillary)

**Role:** Environmental pre-flight check. Fail fast, fail loud.

## Function
Verify binary availability, authentication, and connectivity for every tool the
loop depends on **before** any diagnostic or remediation runs. A single failure
here aborts the loop (nothing downstream can be trusted).

## Checklist

| Tool | Binary check | Auth / connectivity check |
|------|--------------|---------------------------|
| **Azure CLI** | `az version` | `az account show` returns a subscription |
| **kubectl** | `kubectl version --client` | `kubectl auth can-i get pods` + `kubectl cluster-info` |
| **helm** | `helm version` | `helm list -A` succeeds (API reachable) |
| **Slack** | — | `POST` test ping to `SLACK_WEBHOOK_URL` returns 2xx |

## Context Guard
`kubectl config current-context` **must** match the expected AKS cluster name
(`AKS_CLUSTER_NAME`). Operating against the wrong context is treated as a hard
failure — this is the single most important guardrail in the pre-flight.

## Behavior
- All checks pass → emit `preflight: PASS`, exit `0`.
- Any check fails → emit `preflight: FAIL` with the failing tool + reason,
  notify Slack, exit non-zero (Orchestrator aborts).

## Output (structured)
```json
{
  "preflight": "PASS",
  "checks": [
    {"tool": "az",      "binary": true, "auth": true,  "detail": "sub=..."},
    {"tool": "kubectl", "binary": true, "auth": true,  "detail": "ctx=aks-prod"},
    {"tool": "helm",    "binary": true, "auth": true,  "detail": "12 releases"},
    {"tool": "slack",   "binary": null, "auth": true,  "detail": "webhook 200"}
  ]
}
```

Reference implementation: `scripts/preflight.sh`.
