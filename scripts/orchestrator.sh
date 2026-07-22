#!/usr/bin/env bash
# Skill 1 — Loop Orchestrator (reference implementation of the state machine).
# Drives: Health Check (4) -> Troubleshooting (5) -> Validation (3) -> Memory (6),
# looping until converged, retries exhausted, or anti-repeat/no-progress halts it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
MEM_DIR="$ROOT/memory"; MEM="$MEM_DIR/latest.json"
mkdir -p "$MEM_DIR/history" /tmp/sre-diagnostics
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

MODE="${MODE:-review}"
MAX="${MAX_ITERATIONS:-3}"
RUN_ID="${GITHUB_RUN_ID:-local-$$}"

echo "# 🔁 SRE Loop — mode=\`$MODE\` ns=\`${NAMESPACE:-*}\` target=\`${TARGET:-*}\`" >>"$SUMMARY"

# Load prior failed-action signatures for the anti-repeat guard.
FAILED_SIGS="[]"
[[ -f "$MEM" ]] && FAILED_SIGS="$(jq -c '[.failed_actions[]?.signature] // []' "$MEM" 2>/dev/null || echo '[]')"
prev_sig=""
converged=false; escalated=false; iteration=0

for (( iteration=1; iteration<=MAX; iteration++ )); do
  echo "## Iteration $iteration / $MAX" >>"$SUMMARY"

  # --- Skill 4: Health Check ---
  report="$("$HERE/health-check.sh" "${NAMESPACE:-}")"
  healthy="$(jq -r '.healthy' <<<"$report")"
  sig="$(jq -r '.signature' <<<"$report")"
  summary="$(jq -r '.summary' <<<"$report")"
  echo "- Health: healthy=\`$healthy\` — $summary" >>"$SUMMARY"
  echo "- Signature: \`$sig\`" >>"$SUMMARY"

  if [[ "$healthy" == "true" ]]; then
    converged=true
    "$HERE/notify-slack.sh" ":white_check_mark:" "SRE Loop: healthy" "Namespace ${NAMESPACE:-*} healthy after $iteration iteration(s)." >/dev/null || true
    break
  fi

  # Always alert on a detected issue.
  "$HERE/notify-slack.sh" ":rotating_light:" "SRE Loop: issue detected" "$summary (sig: $sig)" >/dev/null || true

  # --- review mode: RCA only, no remediation, no looping past first diagnosis ---
  if [[ "$MODE" == "review" ]]; then
    plan="$(MODE=review FAILED_SIGS="$FAILED_SIGS" "$HERE/remediate.sh" <<<"$report")"
    echo "- RCA: $(jq -r '.root_cause' <<<"$plan")" >>"$SUMMARY"
    echo '```json' >>"$SUMMARY"; jq '.' <<<"$plan" >>"$SUMMARY"; echo '```' >>"$SUMMARY"
    break
  fi

  # --- Skill 5: Troubleshoot + remediate (auto/chat) ---
  plan="$(MODE="$MODE" FAILED_SIGS="$FAILED_SIGS" "$HERE/remediate.sh" <<<"$report")"
  echo "- RCA: $(jq -r '.root_cause' <<<"$plan")" >>"$SUMMARY"
  applied_ok="$(jq -r '[.actions[]?|select(.applied and .result=="ok")]|length' <<<"$plan")"
  action_sig="$(jq -r '.actions[0]? as $a | if $a then "\($a.type):\(.target.namespace)/\(.target.name)" else "" end' <<<"$plan")"
  esc="$(jq -r '.escalated' <<<"$plan")"

  # --- Skill 3: Validation ---
  if [[ "$esc" == "true" ]]; then
    vstatus="FAIL"; vreason="No non-destructive auto-remedy; escalated."
    escalated=true
  elif [[ "$applied_ok" -ge 1 ]]; then
    vstatus="PASS"; vreason="Remediation applied cleanly ($action_sig)."
  else
    vstatus="FAIL"; vreason="Remediation did not apply successfully."
  fi
  echo "- Validation: **$vstatus** — $vreason" >>"$SUMMARY"

  # --- Skill 6: Persist memory ---
  record="$(jq -nc \
    --arg run "$RUN_ID" --arg mode "$MODE" --argjson it "$iteration" --argjson max "$MAX" \
    --arg ns "${NAMESPACE:-*}" --arg tgt "${TARGET:-}" --arg sig "$sig" \
    --arg asig "$action_sig" --arg vres "$vstatus" --argjson esc "$esc" \
    '{
      run_id:$run, mode:$mode, iteration:$it, max_iterations:$max,
      scope:{namespace:$ns, target:$tgt},
      health_signature:$sig, converged:false,
      attempted_actions: (if $asig=="" then [] else [{signature:$asig,result:$vres,iteration:$it}] end),
      failed_actions: (if ($vres=="FAIL" and $asig!="") then [{signature:$asig,result:"failed",iteration:$it}] else [] end),
      lessons: [], escalated:$esc, next_hint:""
    }')"
  # Merge failed_actions across iterations for the anti-repeat guard.
  if [[ -f "$MEM" ]]; then
    record="$(jq -s '.[0].failed_actions = ((.[0].failed_actions // []) + (.[1].failed_actions // []) | unique_by(.signature)) | .[0]' <<<"$(echo "$record"; cat "$MEM")")"
  fi
  echo "$record" >"$MEM"
  cp "$MEM" "$MEM_DIR/history/${RUN_ID}.json"
  FAILED_SIGS="$(jq -c '[.failed_actions[]?.signature]' "$MEM")"

  # --- Convergence checks ---
  if [[ "$escalated" == "true" ]]; then
    echo "- ⛔ Escalated — halting loop." >>"$SUMMARY"; break
  fi
  if [[ "$sig" == "$prev_sig" && "$vstatus" == "PASS" ]]; then
    echo "- ⚠️ No-progress: signature unchanged after remediation — escalating." >>"$SUMMARY"
    escalated=true; break
  fi
  prev_sig="$sig"
done

# --- Finalize memory converged flag ---
[[ -f "$MEM" ]] && jq --argjson c "$converged" '.converged=$c' "$MEM" >"$MEM.tmp" && mv "$MEM.tmp" "$MEM"

echo "" >>"$SUMMARY"
if [[ "$converged" == "true" ]]; then
  echo "### ✅ Converged" >>"$SUMMARY"; exit 0
elif [[ "$MODE" == "review" ]]; then
  echo "### 📋 Review complete (read-only)" >>"$SUMMARY"; exit 0
else
  echo "### ⛔ Unresolved after $((iteration-1)) iteration(s) — escalate to on-call" >>"$SUMMARY"
  "$HERE/notify-slack.sh" ":sos:" "SRE Loop: UNRESOLVED" "Namespace ${NAMESPACE:-*} not converged; on-call attention needed." >/dev/null || true
  exit 1
fi
