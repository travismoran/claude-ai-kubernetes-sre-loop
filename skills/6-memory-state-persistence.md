# Skill 6 — Memory & State Persistence

**Role:** Knowledge Accumulator.

## Function
Summarize each iteration into structured, injectable context so the **next**
loop iteration (and future runs) can:
- Avoid re-applying a fix that already failed (**anti-repeat guard**).
- Detect no-progress (identical health signature across iterations).
- Provide the Orchestrator with a running trace for convergence decisions.
- Give humans an audit trail of what was tried and why.

## Storage Model
```
memory/
├── latest.json              ← most recent iteration state (fast read for Orchestrator)
└── history/
    └── <run_id>.json        ← append-only full trace per workflow run
```

## Record (conforms to `schemas/iteration-memory.schema.json`)
```json
{
  "run_id": "1234567890",
  "mode": "auto",
  "iteration": 2,
  "max_iterations": 3,
  "scope": {"namespace": "payments", "target": "api"},
  "health_signature": "payments/api:CrashLoopBackOff:OOMKilled",
  "converged": false,
  "attempted_actions": [
    {"signature": "scale:payments/api:3", "result": "ok", "iteration": 2}
  ],
  "failed_actions": [
    {"signature": "restart:payments/api", "result": "no-effect", "iteration": 1,
     "lesson": "Rolling restart did not clear OOM; root cause is capacity, not a bad process."}
  ],
  "lessons": [
    "OOMKilled on api recurs after restart — prefer scale-out over restart for this signature."
  ],
  "escalated": false,
  "next_hint": "If signature persists after scale, escalate: likely needs limit increase (manifest change)."
}
```

## Anti-Repeat Contract
Before Skill 5 applies an action, the Orchestrator checks its fingerprint
against `failed_actions[].signature` in `latest.json`. A match means: **do not
re-apply** — escalate instead. This is what bounds the loop and prevents the
"restart → still broken → restart" thrash pattern.

## Lifecycle
1. Orchestrator loads `latest.json` at loop start (empty on first run).
2. After each iteration, this skill merges the new record, updates `latest.json`,
   and appends to `history/<run_id>.json`.
3. The GitHub Actions job commits `memory/` back to the repo (see workflow),
   making lessons durable across separate workflow runs.

## Contract
Consumes/Produces: `iteration-memory.schema.json`.
