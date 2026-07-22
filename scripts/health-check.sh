#!/usr/bin/env bash
# Skill 4 — Kubernetes Health Check
# Scans nodes/PVCs/workloads/pods and emits a ClusterHealthReport JSON on stdout.
# Usage: health-check.sh [namespace]   (empty namespace => cluster-wide)
set -uo pipefail

NS="${1:-${NAMESPACE:-}}"
DIAG_DIR="/tmp/sre-diagnostics"; mkdir -p "$DIAG_DIR"
NS_FLAG=(-A); [[ -n "$NS" ]] && NS_FLAG=(-n "$NS")

findings="[]"
add_finding() { # kind ns name condition severity evidence-json
  findings="$(jq -c --arg k "$1" --arg ns "$2" --arg n "$3" --arg c "$4" --arg s "$5" \
    --argjson ev "${6:-{}}" \
    '. += [{kind:$k,namespace:$ns,name:$n,condition:$c,severity:$s,evidence:$ev}]' \
    <<<"$findings")"
}

# --- Nodes ---
while IFS=$'\t' read -r name status; do
  [[ "$status" != "True" ]] && add_finding Node "" "$name" "NotReady" critical '{}'
done < <(kubectl get nodes -o json 2>/dev/null \
  | jq -r '.items[] | [.metadata.name, (.status.conditions[]|select(.type=="Ready").status)] | @tsv')

# --- PVCs ---
while IFS=$'\t' read -r ns name phase; do
  [[ "$phase" != "Bound" ]] && add_finding PVC "$ns" "$name" "$phase" warning '{}'
done < <(kubectl get pvc "${NS_FLAG[@]}" -o json 2>/dev/null \
  | jq -r '.items[] | [.metadata.namespace,.metadata.name,.status.phase] | @tsv')

# --- Pods (the primary signal) ---
while IFS=$'\t' read -r ns name phase reason restarts exitcode; do
  cond=""; sev="warning"
  case "$reason" in
    CrashLoopBackOff)              cond="CrashLoopBackOff"; sev="critical" ;;
    ImagePullBackOff|ErrImagePull) cond="ImagePullBackOff"; sev="critical" ;;
    OOMKilled)                     cond="OOMKilled";        sev="critical" ;;
    Evicted)                       cond="Evicted";          sev="warning"  ;;
  esac
  [[ "$phase" == "Pending" ]] && cond="Pending" && sev="warning"
  if [[ -n "$cond" ]]; then
    ev="$(jq -nc --arg r "$restarts" --arg e "$exitcode" --arg rs "$reason" \
      '{restartCount:($r|tonumber?//0), lastExitCode:($e|tonumber?//null), reason:$rs}')"
    add_finding Pod "$ns" "$name" "$cond" "$sev" "$ev"
    kubectl -n "$ns" describe pod "$name" >"$DIAG_DIR/${ns}_${name}.describe" 2>&1 || true
  fi
done < <(kubectl get pods "${NS_FLAG[@]}" -o json 2>/dev/null | jq -r '
  .items[] | . as $p |
  ($p.status.containerStatuses // [])[0] as $c |
  [ $p.metadata.namespace, $p.metadata.name, $p.status.phase,
    ($c.state.waiting.reason // $c.lastState.terminated.reason // ""),
    ($c.restartCount // 0),
    ($c.lastState.terminated.exitCode // "") ] | @tsv')

# --- Workloads: desired vs available ---
while IFS=$'\t' read -r ns name desired ready; do
  [[ "${ready:-0}" -lt "${desired:-0}" ]] && \
    add_finding Deployment "$ns" "$name" "Degraded" warning \
      "$(jq -nc --arg d "$desired" --arg r "$ready" '{desired:($d|tonumber),ready:($r|tonumber)}')"
done < <(kubectl get deploy "${NS_FLAG[@]}" -o json 2>/dev/null \
  | jq -r '.items[] | [.metadata.namespace,.metadata.name,(.spec.replicas//0),(.status.readyReplicas//0)] | @tsv')

count="$(jq 'length' <<<"$findings")"
healthy=$([[ "$count" -eq 0 ]] && echo true || echo false)
crit="$(jq '[.[]|select(.severity=="critical")]|length' <<<"$findings")"
sig="$(jq -r 'if length==0 then "healthy" else (.[0]|"\(.namespace)/\(.name):\(.condition):\(.evidence.reason//"")") end' <<<"$findings")"

jq -nc \
  --arg ns "${NS:-*}" --arg tgt "${TARGET:-}" \
  --argjson healthy "$healthy" --argjson findings "$findings" \
  --arg sig "$sig" --arg count "$count" --arg crit "$crit" \
  '{
     timestamp: (now|todateiso8601),
     scope: {namespace:$ns, target:$tgt},
     healthy: $healthy,
     summary: ("\($count) finding(s), \($crit) critical."),
     signature: $sig,
     findings: $findings
   }'
