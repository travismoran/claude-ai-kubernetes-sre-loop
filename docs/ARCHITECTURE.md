# Architecture

## Skill dependency graph

```
                 ┌──────────────────────────┐
   trigger ─────▶│ 1. Loop Orchestrator      │◀── memory/latest.json (6)
 (dispatch)      └──┬─────────┬─────────┬─────┘
                    │         │         │
             (pre-flight)  (loop body) (persist)
                    ▼         ▼         ▼
          ┌─────────────┐ ┌──────────────┐ ┌───────────────────┐
          │ 2. Deps &   │ │ 4. Health    │ │ 6. Memory & State │
          │   Tooling   │ │    Check     │ └───────────────────┘
          └─────────────┘ └──────┬───────┘
                                 │ issue + mode!=review
                                 ▼
                        ┌──────────────────┐
                        │ 5. SRE Trouble-  │
                        │    shooting      │
                        └────────┬─────────┘
                                 ▼
                        ┌──────────────────┐
                        │ 3. Validation    │──▶ PASS/FAIL to Orchestrator
                        └──────────────────┘

  7. Lifecycle Hook Provisioning  ── out-of-band generator ──▶ emits the
     manifests that fire the (dispatch) trigger at top-left.
```

## Inter-skill contracts (data flow)

| Producer | Artifact | Schema | Consumer |
|----------|----------|--------|----------|
| Skill 4 | Cluster Health Report | `health-report.schema.json` | Skills 5, 3 |
| Skill 5 | Remediation Plan | `remediation-plan.schema.json` | Skills 3, 6 |
| Skill 3 | Validation Result | `validation-result.schema.json` | Skill 1 |
| Skill 6 | Iteration Memory | `iteration-memory.schema.json` | Skill 1 (next iter) |

## Mode matrix

| | `review` | `auto` | `chat` |
|---|---|---|---|
| Health check | ✅ | ✅ | ✅ |
| Gather diagnostics | ✅ | ✅ | ✅ |
| Produce RCA | ✅ | ✅ | ✅ |
| Apply remediation | ❌ | ✅ (whitelist) | ✅ after operator OK |
| Loops to convergence | ❌ (one pass) | ✅ | ✅ |
| Cluster writes | none | scoped | scoped |

## Why scripts + skill-prompts (not one big script)
Each `skills/*.md` is the human/LLM-facing **specification** (role, contract,
decision logic). Each `scripts/*.sh` is a **deterministic reference
implementation** of that spec. This separation lets the loop run today as plain
bash in CI, while the same skill definitions can drive an LLM agent (e.g. Claude
via the Agent SDK) that reasons over the same JSON contracts when richer
judgment is wanted — swap the implementation without changing the architecture.

## Extending
- Add a diagnostic dimension → extend `health-check.sh` + `health-report.schema.json`.
- Add a remediation → add to the whitelist in `remediate.sh` **and** `docs/SAFETY.md`.
- Swap bash for an LLM agent → keep the schemas; the contracts are the interface.
