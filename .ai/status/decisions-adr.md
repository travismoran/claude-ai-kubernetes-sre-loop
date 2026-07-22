# Architecture decision records

Short, append-only. Newest last.

## ADR-001: Spec + reference-impl split, contracts via JSON Schema

Each skill is a Markdown spec plus a bash reference implementation, coupled only
through versioned JSON Schemas (`schemas/`). **Why:** keeps the architecture
implementation-agnostic - the bash impls run today in CI, and the identical
contracts can later drive an LLM agent without touching the design. Rejected a
single monolithic script (untestable, no clean skill boundaries).

## ADR-002: Non-destructive whitelist for `auto` mode

`auto` may only rollout-restart, bounded-scale, or delete a single stuck pod.
Limit edits, manifest applies, node ops, and secret/configmap changes are
escalate-only in every mode. **Why:** autonomous write access to a cluster is
the core risk; a fixed reversible whitelist plus recorded rollbacks bounds blast
radius. See `docs/SAFETY.md`.

## ADR-003: Loop bounded by iterations + anti-repeat + no-progress

Convergence is enforced three ways, not one. **Why:** a naive retry cap still
thrashes (restart -> still broken -> restart). Fingerprinting failed actions in
memory and detecting an unchanged health signature stops repeat-failure loops.

## ADR-004: Identifiers as variables, credentials as secrets; OIDC preferred

Azure/AKS identifiers go in GitHub **variables**; only the Slack webhook and
(optional) SP JSON are **secrets**. Azure auth prefers OIDC federated creds so
no Azure secret is stored. **Why:** mirrors the AKS platform repo's policy and
minimizes stored secret material. See `docs/github-secrets-setup.md`.

## ADR-005: Security posture ported from the AKS platform repo

gitleaks config, git hooks, pre-commit, pinned+checksummed `setup-dev.sh`, and a
credential-free CI secret-scan are reused wholesale, adapted for PAT/webhook/
kubeconfig patterns. **Why:** this is a public repo; consistent, proven
enforcement beats a bespoke one.
