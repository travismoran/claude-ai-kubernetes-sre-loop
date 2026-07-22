#!/usr/bin/env bash
# Skill 2 — Dependencies & Tooling Verification
# Fail fast if any required tool is missing, unauthenticated, or pointed at the
# wrong cluster. Prints a structured summary and exits non-zero on any failure.
set -uo pipefail

FAIL=0
note() { printf '  %-8s %-5s %s\n' "$1" "$2" "$3"; }

echo "== Pre-flight verification =="

# --- Azure CLI ---
if az account show >/dev/null 2>&1; then
  note az PASS "subscription=$(az account show --query name -o tsv 2>/dev/null)"
else
  note az FAIL "not authenticated (run azure/login)"; FAIL=1
fi

# --- kubectl (binary + auth + context guard) ---
if kubectl version --client >/dev/null 2>&1; then
  CTX="$(kubectl config current-context 2>/dev/null || echo '?')"
  if kubectl auth can-i get pods -A >/dev/null 2>&1; then
    if [[ -n "${AKS_CLUSTER_NAME:-}" && "$CTX" != *"${AKS_CLUSTER_NAME}"* ]]; then
      note kubectl FAIL "context '$CTX' != expected '${AKS_CLUSTER_NAME}'"; FAIL=1
    else
      note kubectl PASS "context=$CTX"
    fi
  else
    note kubectl FAIL "cannot 'get pods' — RBAC/cluster unreachable"; FAIL=1
  fi
else
  note kubectl FAIL "binary missing"; FAIL=1
fi

# --- helm ---
if helm version >/dev/null 2>&1 && helm list -A >/dev/null 2>&1; then
  note helm PASS "$(helm list -A -q 2>/dev/null | wc -l | tr -d ' ') releases"
else
  note helm FAIL "binary missing or API unreachable"; FAIL=1
fi

# --- Slack webhook ---
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  CODE="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-type: application/json' \
    --data '{"text":":satellite: sre-loop pre-flight ping"}' \
    "$SLACK_WEBHOOK_URL" || echo 000)"
  if [[ "$CODE" =~ ^2 ]]; then note slack PASS "webhook $CODE"
  else note slack FAIL "webhook returned $CODE"; FAIL=1; fi
else
  note slack WARN "SLACK_WEBHOOK_URL unset — notifications disabled"
fi

echo "== Pre-flight $( [[ $FAIL -eq 0 ]] && echo PASS || echo FAIL ) =="
exit $FAIL
