#!/usr/bin/env bash
# Slack notification helper (webhook / MCP-compatible).
# Usage: notify-slack.sh <emoji> <title> <body>
set -uo pipefail
[[ -z "${SLACK_WEBHOOK_URL:-}" ]] && { echo "SLACK_WEBHOOK_URL unset; skipping"; exit 0; }

emoji="${1:-:information_source:}"; title="${2:-sre-loop}"; body="${3:-}"
payload="$(jq -nc --arg t "$emoji $title" --arg b "$body" \
  '{blocks:[
     {type:"header",text:{type:"plain_text",text:$t}},
     {type:"section",text:{type:"mrkdwn",text:$b}}
   ]}')"

curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL"
