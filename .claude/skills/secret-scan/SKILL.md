---
name: secret-scan
description: Scan this repository (working tree, staged changes, and full git history) for secrets or policy-violating identifiers before committing or pushing. Use before any git commit/push, after generating files from live Azure/kubectl output, or when asked to audit the repo for leaks.
---

# Secret scan

Run all three layers from the repo root and report findings. This repo is
PUBLIC - the bar is "no real values at all", not just "no credentials"
(policy: `.claude/rules/no-secrets.md`).

## 1. Automated scan (gitleaks)

```bash
gitleaks dir . --redact --no-banner -c .gitleaks.toml          # working tree
gitleaks git --redact --no-banner -c .gitleaks.toml            # full history
gitleaks git --pre-commit --staged --redact --no-banner -c .gitleaks.toml  # staged only
```

If gitleaks is missing, install the pinned release into `~/.local/bin`
(`./scripts/setup-dev.sh`, or see `.pre-commit-config.yaml` for the version),
or fall back to step 2 and say clearly that the scan was degraded.

## 2. Policy grep (things gitleaks won't reliably flag)

Real identifiers and low-entropy tokens are banned even when gitleaks passes
them. Search tracked files only:

```bash
# GitHub PATs and Slack webhook URLs
git ls-files -z | xargs -0 grep -nEI \
  'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|hooks\.slack\.com/services/T[A-Za-z0-9/]{20,}'

# Real GUIDs (subscription/tenant/principal IDs) that aren't the placeholder
git ls-files -z | xargs -0 grep -nEI \
  '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
  | grep -v '00000000-0000-0000-0000-000000000000'

# Public IPs that aren't RFC5737 docs / RFC1918 private ranges
git ls-files -z | xargs -0 grep -nEI \
  '\b((25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\b' \
  | grep -vE '(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|203\.0\.113\.|127\.|0\.0\.0\.0|255\.)'
```

Expected clean output: nothing from any of the three (the documented
`YOUR_GITHUB_PAT` placeholder and RFC ranges are fine and excluded).

## 3. Forbidden files

```bash
git ls-files | grep -E '(^|/)\.env$|\.pem$|\.pfx$|\.key$|kubeconfig|kube_config|kube_admin_config' | grep -v example
```

Must return nothing.

## Reporting

- All clean -> say so explicitly, listing which layers ran.
- Findings -> list file:line, what it looks like, and the fix (move to a GitHub
  Actions secret / Kubernetes Secret / env var, delete, or - if it's a real
  credential already in history - STOP, tell the user to rotate it, and rewrite
  history before any push).
