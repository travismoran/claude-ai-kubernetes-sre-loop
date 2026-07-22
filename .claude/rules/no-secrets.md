# Rule: no secrets in this repository

This is a **public** repository. Treat every commit as world-readable forever
(mirrors and caches keep history even after force-pushes).

## Never commit

- Credentials of any kind: passwords, client secrets, storage account keys,
  SAS tokens, connection strings, certificates/private keys (`*.pem`,
  `*.pfx`, `*.key`), kubeconfigs, `kube_config`/`kube_admin_config` output.
- **GitHub PATs** (`ghp_…`, `github_pat_…`) - the lifecycle hooks use one, but
  it is mounted from a Kubernetes Secret at runtime, never written to a manifest.
- **Slack webhook URLs** (`https://hooks.slack.com/services/T…`) - they embed a
  token; treat them as credentials.
- **Azure `AZURE_CREDENTIALS` JSON** or any service-principal client secret.
- Real identifiers, even "non-secret" ones: subscription IDs, tenant IDs,
  principal/object IDs, AKS cluster names, resource group names, registry
  hostnames, public IPs. They are not credentials, but repo policy keeps them
  out anyway - all flow in via GitHub Actions secrets/variables (CI) or a
  gitignored `.env` (local). Docs use the all-zeros GUID and RFC 5737 IPs
  (`203.0.113.x`) as placeholders; `.gitleaks.toml` allowlists exactly those.

## Where real values go

- **CI runtime:** GitHub Actions **secrets** (credentials) and **variables**
  (identifiers). See `docs/github-secrets-setup.md`.
- **Locally:** `.env` (gitignored), sourced before running scripts.
- **In-cluster:** the dispatch PAT lives in a Kubernetes Secret
  (`sre-loop-dispatch`), referenced as `$GITHUB_PAT`.

## Enforcement layers (keep all of them working)

0. `scripts/setup-dev.sh` - installs pinned gitleaks + activates the hooks;
   the required first step on every clone/machine.
1. `githooks/pre-commit` - blocks forbidden file types + keyword patterns
   (incl. `ghp_`/`github_pat_`/Slack webhook shapes) + gitleaks staged scan.
2. `githooks/pre-push` - gitleaks over working tree + full history.
3. `.pre-commit-config.yaml` - same checks for pre-commit-framework users.
4. CI `ci.yml` - gitleaks on every push/PR (last line of defense).
5. On demand: the `secret-scan` skill (`.claude/skills/secret-scan/`).

## For Claude specifically

- Before ANY `git commit` or `git push` in this repo, run the secret-scan
  skill (or `bash githooks/pre-push`) and act on findings.
- Never inline a real value from `az`/`kubectl` output or `.env` into a tracked
  file - reference the env var or a Kubernetes Secret instead.
- If a secret ever lands in a commit: STOP, tell the user, rotate the
  credential first, then rewrite history (`git filter-repo`) before pushing.
