# ACTIVE SESSION - read me first

Last updated: 2026-07-22

## Current state

Scaffold complete and pushed to `travismoran/claude-ai-kubernetes-sre-loop`
(`main`). Nothing runs against a live cluster yet - no AKS target configured,
no GitHub secrets/variables set. Cost meter: $0.

Repo contents:
- 7 skill specs (`skills/`) + deterministic bash reference impls (`scripts/`).
- JSON contracts (`schemas/`), lifecycle-hook manifests (`manifests/`).
- Security posture ported from the AKS platform repo: gitleaks config,
  git hooks, pre-commit, `scripts/setup-dev.sh`, CI secret-scan.
- Two workflows: `ci.yml` (credential-free security+lint) and `sre-loop.yml`
  (the engine; OIDC-preferred Azure login).

## What is proven

- All bash scripts pass `bash -n`; all JSON schemas parse.
- Nothing has been executed end-to-end against a cluster - the loop logic is
  untested on real workloads. That is the top backlog item.

## Local machine context (WSL2)

- Project root: `~/k8s-sre-loop-engine`.
- Run `./scripts/setup-dev.sh` once to install pinned gitleaks + activate
  secret-scan hooks (NOT yet run on this machine - do it before committing).
- `jq` is required by the scripts; preinstalled on `ubuntu-latest` CI runners,
  install locally if testing scripts by hand.

## Immediate next steps

See `.ai/status/task-backlog.md`. Top of stack:
1. Configure GitHub variables/secrets to activate `sre-loop.yml`
   (`docs/github-secrets-setup.md`).
2. Run `MODE=review` against a throwaway AKS cluster; capture evidence in
   `.ai/test-results/`.
3. Confirm `ci.yml` is green on GitHub (secret-scan + lint + schema validation).
