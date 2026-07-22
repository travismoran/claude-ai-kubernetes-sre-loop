# 001 - SRE loop foundation

- **Status**: complete
- **Date**: 2026-07-21
- **Commits**: 7cc316c (initial), 6fa4399 (repo URL patch)

## Context

Stand up the autonomous Kubernetes SRE self-healing loop as a modular,
GitHub-Actions-driven system with `review`/`auto`/`chat` modes and seven
composable skills, plus a security posture matching the AKS platform repo.

## Design

- Each skill is a spec (`skills/*.md`) paired with a deterministic bash
  reference implementation (`scripts/*.sh`); they communicate only through the
  versioned JSON Schemas in `schemas/`. This lets the same contracts later
  drive an LLM agent without changing the architecture.
- Loop bounded three ways: `MAX_ITERATIONS`, anti-repeat fingerprint guard, and
  no-progress detection (health `signature` unchanged after a "successful" fix).
- `auto` remediation restricted to a non-destructive whitelist (`docs/SAFETY.md`).
- Security: gitleaks + git hooks + pre-commit + CI secret-scan, ported from
  the AKS platform repo and adapted for PAT/webhook/kubeconfig patterns.

## Steps

1. [x] Scaffold skills, scripts, schemas, manifests, docs.
2. [x] `sre-loop.yml` workflow (OIDC-preferred Azure login).
3. [x] `ci.yml` credential-free security + lint + schema/manifest validation.
4. [x] Secret-scanning layers + `docs/github-secrets-setup.md`.
5. [ ] Execute `MODE=review` against a live throwaway cluster (-> plan 002).

## Verification

- `bash -n scripts/*.sh githooks/*` clean.
- `python3 -c 'json.load(...)'` over `schemas/*.json` clean.
- CI green on GitHub (pending first push observation).

## Risks / open questions

- The loop logic is untested against real failing workloads; remediation
  command construction (deployment-name derivation from pod owner refs) needs
  live validation.
- `helm` is installed but not yet used by any skill - candidate for a future
  release-health check.
