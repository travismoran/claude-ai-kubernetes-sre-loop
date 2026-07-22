#!/usr/bin/env bash
# Skill 5 — SRE Troubleshooting & Remediation
# Reads a ClusterHealthReport (JSON on stdin), produces a RemediationPlan (JSON
# on stdout). Applies actions only when MODE=auto (or an approved chat subset).
#
# NON-DESTRUCTIVE WHITELIST ONLY. Anything off-whitelist is escalate-only.
set -uo pipefail

MODE="${MODE:-review}"
FAILED_SIGS="${FAILED_SIGS:-[]}"   # JSON array of previously-failed action signatures (anti-repeat)
report="$(cat)"

first="$(jq -c '.findings[0] // empty' <<<"$report")"
if [[ -z "$first" ]]; then
  jq -nc '{target:{kind:"",namespace:"",name:""},root_cause:"no findings",actions:[],escalated:false,confidence:1.0}'
  exit 0
fi

kind="$(jq -r '.kind' <<<"$first")"
ns="$(jq -r '.namespace' <<<"$first")"
name="$(jq -r '.name' <<<"$first")"
cond="$(jq -r '.condition' <<<"$first")"
reason="$(jq -r '.evidence.reason // ""' <<<"$first")"

# Resolve the owning deployment for a pod (best-effort).
deploy="$name"
if [[ "$kind" == "Pod" ]]; then
  deploy="$(kubectl -n "$ns" get pod "$name" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null | sed 's/-[a-f0-9]*$//')"
  [[ -z "$deploy" ]] && deploy="$name"
fi

# --- Root cause -> whitelist action ------------------------------------------
action_type="none"; cmd=""; rollback=""; rc="unknown"; escalate=false
case "$cond" in
  CrashLoopBackOff)
    if [[ "$reason" == "OOMKilled" ]]; then
      rc="OOMKilled under load; scale out to spread pressure (limit edits are manifest changes → escalate)."
      cur="$(kubectl -n "$ns" get deploy "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)"
      new=$(( cur + 1 )); action_type="scale"
      cmd="kubectl -n $ns scale deploy/$deploy --replicas=$new"
      rollback="kubectl -n $ns scale deploy/$deploy --replicas=$cur"
    else
      rc="Transient crash loop; attempt rolling restart to clear bad process state."
      action_type="restart"
      cmd="kubectl -n $ns rollout restart deploy/$deploy"
      rollback="kubectl -n $ns rollout undo deploy/$deploy"
    fi ;;
  OOMKilled)
    rc="OOMKilled; scale out (do not autonomously edit resource limits)."
    cur="$(kubectl -n "$ns" get deploy "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)"
    new=$(( cur + 1 )); action_type="scale"
    cmd="kubectl -n $ns scale deploy/$deploy --replicas=$new"
    rollback="kubectl -n $ns scale deploy/$deploy --replicas=$cur" ;;
  Pending)
    rc="Pod unschedulable (capacity/affinity/PVC). Needs cluster change — escalate."
    escalate=true ;;
  ImagePullBackOff)
    rc="Bad/unreachable image tag or registry auth. Needs manifest/registry fix — escalate."
    escalate=true ;;
  *)
    rc="Condition '$cond' has no non-destructive auto-remedy — escalate."
    escalate=true ;;
esac

sig="${action_type}:${ns}/${deploy}"
applied=false; result="proposed"

# --- Anti-repeat guard: never re-apply a known-failed action -----------------
if [[ "$escalate" == false ]] && jq -e --arg s "$sig" 'index($s)' <<<"$FAILED_SIGS" >/dev/null 2>&1; then
  rc="$rc [anti-repeat: '$sig' already failed a prior iteration → escalate instead]"
  escalate=true; action_type="none"; cmd=""
fi

# --- Execute (auto mode only) ------------------------------------------------
if [[ "$escalate" == false && -n "$cmd" && "$MODE" == "auto" ]]; then
  if eval "$cmd" >/tmp/sre-diagnostics/last-action.log 2>&1; then
    applied=true; result="ok"
  else
    applied=true; result="error"
  fi
fi

jq -nc \
  --arg kind "$kind" --arg ns "$ns" --arg name "$deploy" \
  --arg rc "$rc" --arg at "$action_type" --arg cmd "$cmd" \
  --arg rb "$rollback" --arg res "$result" \
  --argjson applied "$applied" --argjson escalated "$escalate" \
  '{
    target: {kind:$kind, namespace:$ns, name:$name},
    root_cause: $rc,
    actions: ( if $cmd == "" then []
               else [{type:$at, command:$cmd, destructive:false,
                      applied:$applied, result:$res, rollback:$rb}] end ),
    escalated: $escalated,
    confidence: 0.7
  }'
