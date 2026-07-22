# claude-ai-kubernetes-sre-loop - project guidelines

Public example repo: an autonomous, modular **Kubernetes SRE Self-Healing Loop
Engine** driven by GitHub Actions. Three modes (`review` / `auto` / `chat`),
seven skills (see `skills/`), deterministic bash reference implementations
(`scripts/`), JSON contracts (`schemas/`), lifecycle-hook manifests
(`manifests/`). Targets AKS via `az` + `kubectl` + `helm`, alerts via Slack.

## Session pickup

**Always read `.ai/ACTIVE_SESSION.md` first** - it holds live state, what has
been proven end-to-end, and next steps. Plans in `.ai/plans/`, test evidence in
`.ai/test-results/`, backlog and ADRs in `.ai/status/`. Keep them updated as
work progresses.

## Hard rules

1. **No secrets in the repo - ever.** See `.claude/rules/no-secrets.md`.
   Real runtime credentials live in **GitHub Actions secrets/variables**
   (see `docs/github-secrets-setup.md`), never in tracked files.
2. `auto` mode may only take actions on the **non-destructive whitelist** in
   `docs/SAFETY.md` (rollout restart, bounded scale, single stuck-pod delete).
   Limit edits, manifest applies, node/secret changes are always escalate-only.
3. The loop must stay bounded: `MAX_ITERATIONS`, the anti-repeat guard, and
   no-progress detection. Never remove a guardrail to "make it converge".
4. Skills communicate only through the versioned JSON Schemas in `schemas/`.
   Change a contract -> bump the schema and every producer/consumer together.
5. Lifecycle-hook manifests must mount the GitHub PAT from a Secret
   (`$GITHUB_PAT`); never inline a token literal in a manifest.

## Dev commands

```bash
./scripts/setup-dev.sh                 # one-time: gitleaks + secret-scan hooks
bash scripts/preflight.sh              # Skill 2: env/auth/context pre-flight
MODE=review bash scripts/orchestrator.sh   # dry, read-only loop (needs a cluster)
shellcheck scripts/*.sh githooks/*     # lint the bash
bash githooks/pre-push                 # manual secret sweep before pushing
```

CI (`.github/workflows/ci.yml`) runs gitleaks + shellcheck + actionlint +
yamllint + schema/manifest validation on every push to main and every PR -
no cloud credentials required, so it is green on forks too.

## Environment quirks

- Runtime tools: `az` (Azure auth), `kubectl` (cluster), `helm` (releases),
  Slack webhook (notify). `scripts/preflight.sh` verifies all four + the
  kube-context guard before anything else runs.
- Scripts use `jq` heavily; it is preinstalled on `ubuntu-latest` runners.
- Never write to `~/.kube/config` on a dev box if it is a symlink; prefer
  `az aks get-credentials --file ~/.kube/<cluster>.yaml`.
