# Skill 3 — Validation

**Role:** Gatekeeper & Quality Assurer.

## Function
Analyze the outputs produced by the Health Check and Troubleshooting skills and
decide whether the iteration is trustworthy. Validation does **not** fix
anything — it judges whether the data gathered is complete enough for the
Orchestrator to make a sound convergence decision.

## What it checks
1. **Telemetry completeness** — were the expected artifacts collected?
   - `kubectl describe` events for each flagged workload
   - Pod logs (current + `--previous` where `restartCount > 0`)
   - Resource/metrics snapshot (`kubectl top`, if metrics-server present)
2. **Action integrity** (auto mode) — did each applied remediation return
   success, and is the resulting object in the expected state?
3. **Consistency** — does the post-remediation health signature differ from the
   pre-remediation one (i.e., did anything actually change)?

## Verdict
Emits a single structured result the Orchestrator consumes:

```json
{
  "status": "PASS",
  "reason": "All telemetry collected; rollout restart completed; 3/3 pods Ready.",
  "missing": [],
  "iteration": 2
}
```

- `PASS` — data complete and (if applicable) remediation applied cleanly.
- `FAIL` — required telemetry missing OR remediation errored. `reason` explains,
  `missing[]` lists absent artifacts so the next iteration can re-collect.

## Contract
Consumes: `health-report.schema.json`, `remediation-plan.schema.json`.
Produces: `validation-result.schema.json`.
