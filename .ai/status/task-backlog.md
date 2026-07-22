# Task backlog

Ordered roughly by priority. Keep `.ai/ACTIVE_SESSION.md` pointing at the top.

## Next

1. Configure GitHub variables/secrets and activate `sre-loop.yml`
   (`docs/github-secrets-setup.md`). Prefer OIDC.
2. Run `MODE=review` against a throwaway AKS cluster with a deliberately broken
   workload (e.g. a bad image tag). Capture evidence in `.ai/test-results/`.
3. Confirm `ci.yml` is green on GitHub (secret-scan + shellcheck + actionlint +
   yamllint + schema/manifest validation).

## Soon

4. Validate remediation command construction on real objects: pod->owner
   Deployment derivation in `scripts/remediate.sh` is best-effort regex; verify
   against ReplicaSet-owned pods and StatefulSets.
5. Wire `helm` into a release-health check (Skill 4 currently ignores it).
6. Add a `chat`-mode input round-trip (currently the spec describes it; the
   orchestrator treats chat like auto).

## Later

7. Optional: replace the bash reference impls with a Claude Agent SDK loop that
   reasons over the same `schemas/` contracts.
8. Add unit tests for the jq transforms in `health-check.sh` using fixture JSON.
