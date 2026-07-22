#!/usr/bin/env bash
#
# One-time developer setup for this repo's security posture. Idempotent.
#   1. Installs gitleaks (pinned + checksum-verified) to ~/.local/bin
#   2. Activates the repo's git hooks (githooks/pre-commit, pre-push)
#   3. Runs a baseline secret scan so you start from a known-clean state
#
# Usage: ./scripts/setup-dev.sh
set -euo pipefail

GITLEAKS_VERSION="8.24.3" # keep in sync with .pre-commit-config.yaml + ci.yml + .tool-versions
INSTALL_DIR="${HOME}/.local/bin"
REPO_ROOT="$(git rev-parse --show-toplevel)"

# sha256 sums from the official release checksums file:
# https://github.com/gitleaks/gitleaks/releases/download/v8.24.3/gitleaks_8.24.3_checksums.txt
declare -A CHECKSUMS=(
  ["linux_x64"]="9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c"
  ["linux_arm64"]="5f2edbe1f49f7b920f9e06e90759947d3c5dfc16f752fb93aaafc17e9d14cf07"
  ["darwin_arm64"]="b90f13bb8c90ab72083d9b0c842e39dafb82c0e5c3f872f407366b7a58909013"
)

# --- 1. gitleaks ------------------------------------------------------------
have_version="$(command -v gitleaks >/dev/null 2>&1 && gitleaks version 2>/dev/null || true)"
if [[ "${have_version}" == "${GITLEAKS_VERSION}" ]]; then
  echo ">> gitleaks ${GITLEAKS_VERSION} already installed: $(command -v gitleaks)"
else
  case "$(uname -s)_$(uname -m)" in
    Linux_x86_64) platform="linux_x64" ;;
    Linux_aarch64) platform="linux_arm64" ;;
    Darwin_arm64) platform="darwin_arm64" ;;
    *)
      echo "Unsupported platform $(uname -s)/$(uname -m) - install manually:" >&2
      echo "https://github.com/gitleaks/gitleaks/releases/tag/v${GITLEAKS_VERSION}" >&2
      exit 1
      ;;
  esac

  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  tarball="gitleaks_${GITLEAKS_VERSION}_${platform}.tar.gz"
  echo ">> Downloading ${tarball}"
  curl -sSfL -o "${tmp}/${tarball}" \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${tarball}"

  echo "${CHECKSUMS[$platform]}  ${tmp}/${tarball}" | sha256sum -c - >/dev/null \
    || { echo "CHECKSUM MISMATCH - aborting install." >&2; exit 1; }

  mkdir -p "${INSTALL_DIR}"
  tar -xzf "${tmp}/${tarball}" -C "${tmp}" gitleaks
  install -m 0755 "${tmp}/gitleaks" "${INSTALL_DIR}/gitleaks"
  echo ">> Installed gitleaks ${GITLEAKS_VERSION} to ${INSTALL_DIR}/gitleaks"
  case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *) echo "   NOTE: add ${INSTALL_DIR} to your PATH." ;;
  esac
fi

# --- 2. git hooks -----------------------------------------------------------
current_hookspath="$(git -C "${REPO_ROOT}" config core.hooksPath || true)"
if [[ "${current_hookspath}" == "githooks" ]]; then
  echo ">> git hooks already active (core.hooksPath=githooks)"
else
  git -C "${REPO_ROOT}" config core.hooksPath githooks
  echo ">> Activated secret-scan hooks (core.hooksPath=githooks)"
fi

# --- 3. baseline scan -------------------------------------------------------
echo ">> Baseline scan: working tree"
gitleaks dir "${REPO_ROOT}" --redact --no-banner -c "${REPO_ROOT}/.gitleaks.toml"
echo ">> Baseline scan: full git history"
(cd "${REPO_ROOT}" && gitleaks git --redact --no-banner -c .gitleaks.toml)

echo
echo "Setup complete. Every commit and push is now gated by secret scanning."
