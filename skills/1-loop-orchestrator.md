# Skill 1 — Loop Orchestrator

**Role:** Main controller governing the state machine.

## Responsibilities
- Read inputs: `mode` flag, dispatch `payload`, and previous-iteration `memory/`.
- Execute sub-skills in sequence.
- Evaluate convergence criteria after each iteration.
- Manage flow, retries, and termination.

## State Machine

```
START
  │
  ▼
LOAD_CONTEXT ──────────► read mode, payload, memory/latest.json
  │
  ▼
PREFLIGHT (Skill 2) ───► FAIL ─► NOTIFY + ABORT (non-zero exit)
  │ PASS
  ▼
┌─ ITERATION n ────────────────────────────────────────────────┐
│  HEALTH_CHECK (Skill 4)  ─► healthy? ─► yes ─► CONVERGED       │
│        │ no                                                    │
│        ▼                                                       │
│  guard: mode == review ? ─► emit RCA only, skip remediation    │
│        │ auto/chat                                             │
│        ▼                                                       │
│  TROUBLESHOOT (Skill 5)  ─► produce+apply remediation plan     │
│        │                                                       │
│        ▼                                                       │
│  VALIDATE (Skill 3)      ─► PASS / FAIL + REASON               │
│        │                                                       │
│        ▼                                                       │
│  PERSIST_MEMORY (Skill 6)                                      │
└──────────────┬────────────────────────────────────────────────┘
               ▼
   convergence check:
     - issue resolved?        ─► DONE (success)
     - n >= MAX_ITERATIONS?   ─► DONE (exhausted, escalate)
     - fix already tried?     ─► DONE (anti-repeat, escalate)
     - else                   ─► n += 1, loop
```

## Convergence Criteria (evaluated in order)
1. **Resolved** — Health Check reports no issues → exit `0`, notify success.
2. **Retry limit** — `n >= MAX_ITERATIONS` → exit non-zero, escalate to on-call.
3. **Anti-repeat** — the remediation selected this iteration matches a
   `failed_action` fingerprint in memory → do not re-apply; escalate.
4. **No-progress** — health signature identical to previous iteration after a
   remediation was applied → escalate.

## Inputs
| Name | Source | Notes |
|------|--------|-------|
| `mode` | env `MODE` | `review` \| `auto` \| `chat` |
| `namespace` | env `NAMESPACE` | empty = cluster-wide |
| `target` | env `TARGET` | optional scoping |
| `max_iterations` | env `MAX_ITERATIONS` | default 3 |
| prior memory | `memory/latest.json` | see Skill 6 |

## Outputs
- `$GITHUB_STEP_SUMMARY` markdown run summary.
- Updated `memory/latest.json` + append-only `memory/history/<run_id>.json`.
- Process exit code: `0` converged, non-zero unresolved/escalated.

## Contract
Consumes: `iteration-memory.schema.json`.
Produces/updates: `iteration-memory.schema.json`.
Reference implementation: `scripts/orchestrator.sh`.
