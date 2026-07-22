# Latest run - offline validation

Date: 2026-07-22

## Static checks (local, no cluster)

| Check | Command | Result |
|-------|---------|--------|
| Bash syntax (scripts) | `bash -n scripts/*.sh` | PASS (5/5) |
| Bash syntax (hooks) | `bash -n githooks/*` | PASS (2/2) |
| JSON schemas parse | `python3 json.load` over `schemas/*.json` | PASS (4/4) |

## Not yet run

- End-to-end loop against a live cluster (any mode). No AKS target configured.
- CI on GitHub (first push of `ci.yml` not yet observed green).
- gitleaks baseline (`./scripts/setup-dev.sh`) on this machine.

Log live-cluster evidence here as dated files, e.g.
`.ai/test-results/2026-07-DD-review-mode.md`, and link from the relevant plan.
