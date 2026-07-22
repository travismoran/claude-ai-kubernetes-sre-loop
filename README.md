# Kubernetes SRE Self-Healing Loop Engine

An autonomous, modular **Agentic Loop System** for Kubernetes operational
automation, driven by GitHub Actions. The engine scans cluster state, diagnoses
failing workloads, and (optionally) applies non-destructive remediation — then
iterates until the issue converges or a retry limit is reached.

---

## Execution Modes

The engine is driven by a single `mode` flag passed via `workflow_dispatch` or
`repository_dispatch`:

| Mode     | Access      | Behavior |
|----------|-------------|----------|
| `review` | Read-only   | Scans state, runs health checks, gathers diagnostics, emits RCA. **No changes.** |
| `auto`   | Read/Write  | Scans, diagnoses, and autonomously applies **non-destructive** remediation. |
| `chat`   | Interactive | Prompts the operator for targeted inputs (namespace, pod, deployment) before proceeding. |

---

## The Loop

```
┌──────────────────────────────────────────────────────────────┐
│                     LOOP ORCHESTRATOR                          │
│  (reads flags + payload + previous-iteration memory)          │
└───────────────┬──────────────────────────────────────────────┘
                │
                ▼
   ┌────────────────────────┐   pre-flight
   │ 2. Deps & Tooling Check │   (az, kubectl, helm, slack)
   └────────────┬───────────┘
                ▼
   ┌────────────────────────┐   diagnostic engine
   │ 4. K8s Health Check     │──── issue? ─── no ──▶ report + alert ──▶ EXIT (converged)
   └────────────┬───────────┘
                │ yes (and mode != review)
                ▼
   ┌────────────────────────┐   incident response
   │ 5. SRE Troubleshooting  │   (RCA in review / remediate in auto)
   └────────────┬───────────┘
                ▼
   ┌────────────────────────┐   gatekeeper
   │ 3. Validation           │   PASS / FAIL + REASON
   └────────────┬───────────┘
                ▼
   ┌────────────────────────┐   knowledge accumulator
   │ 6. Memory & State       │   writes memory for next iteration
   └────────────┬───────────┘
                ▼
        converged? / retries left?  ──▶ loop back to Orchestrator
```

**Skill 7 (Lifecycle Hook Provisioning)** is a generator run out-of-band: it
emits Kubernetes manifests that call `repository_dispatch` to *trigger* this
whole loop when a deployment starts or fails.

---

## Repository Layout

```
k8s-sre-loop-engine/
├── README.md                     ← you are here
├── .github/workflows/
│   ├── sre-loop.yml              ← GitHub Actions entrypoint (the loop driver)
│   └── ci.yml                    ← credential-free security scan + lint + validation
├── skills/                       ← modular skill definitions (prompts + contracts)
│   ├── 1-loop-orchestrator.md
│   ├── 2-deps-tooling-verification.md
│   ├── 3-validation.md
│   ├── 4-k8s-health-check.md
│   ├── 5-sre-troubleshooting.md
│   ├── 6-memory-state-persistence.md
│   └── 7-lifecycle-hook-provisioning.md
├── schemas/                      ← JSON Schemas for inter-skill contracts
│   ├── health-report.schema.json
│   ├── validation-result.schema.json
│   ├── remediation-plan.schema.json
│   └── iteration-memory.schema.json
├── scripts/                      ← executable helpers invoked by skills
│   ├── preflight.sh
│   ├── health-check.sh
│   ├── remediate.sh
│   └── notify-slack.sh
├── manifests/                    ← lifecycle-hook manifest templates
│   ├── deployment-poststart-hook.yaml
│   └── failure-dispatch-cronjob.yaml
├── memory/                       ← per-run iteration memory (JSON), git-tracked
│   └── .gitkeep
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SAFETY.md                 ← what "non-destructive" means; guardrails
│   └── github-secrets-setup.md   ← gh secret/variable set commands (OIDC-first)
├── githooks/                     ← pre-commit / pre-push secret-scan gates
├── scripts/setup-dev.sh          ← one-time: pinned gitleaks + activate hooks
├── .gitleaks.toml                ← secret-scan config (allowlists doc placeholders)
├── .pre-commit-config.yaml       ← same checks for pre-commit-framework users
├── .claude/                      ← project guidelines, no-secrets rule, secret-scan skill
└── .ai/                          ← working context: ACTIVE_SESSION, plans, ADRs, backlog
```

---

## Security & Contributing

This is a **public** repo — no real credentials, PATs, webhook URLs, or Azure
identifiers may ever be committed (`.claude/rules/no-secrets.md`). Enforcement is
layered: pinned gitleaks + git hooks locally, and a credential-free `ci` workflow
(gitleaks + shellcheck + actionlint + yamllint + schema/manifest validation) that
runs on every push to `main` and every PR.

```bash
./scripts/setup-dev.sh      # one-time per clone: installs gitleaks, activates hooks
bash githooks/pre-push      # manual full-history secret sweep
```

Runtime credentials live only in GitHub Actions secrets/variables — see
`docs/github-secrets-setup.md`.

---

## Quick Start

1. Configure repository secrets (see `.github/workflows/sre-loop.yml` header).
2. Trigger a read-only pass:
   ```bash
   gh workflow run sre-loop.yml -f mode=review -f namespace=default
   ```
3. Review the run summary and the committed `memory/` artifact.
4. When confident, run `-f mode=auto` for autonomous remediation.

See `docs/SAFETY.md` before ever running `auto` against production.

---

## Design Principles

- **Modular skills, explicit contracts.** Every skill communicates through a
  versioned JSON Schema (see `schemas/`), never through implicit conventions.
- **Convergence over persistence.** The loop is bounded by `MAX_ITERATIONS` and
  a memory-backed anti-repeat guard — it will not retry a fix it already knows failed.
- **Non-destructive by default.** `auto` mode is whitelisted to a fixed set of
  reversible actions. Destructive operations are never taken autonomously.
