#!/bin/bash
# Claude Code hook -> Claude Status Border app.
#
# Usage (from settings.json hooks):  claude-status-notify.sh <state>
#   state = idle | thinking | working | waiting | done
#
# Reads the hook's JSON event from stdin, builds a short detail label,
# and POSTs it to the local app. Never blocks Claude Code: short curl
# timeout, always exits 0.

PORT="${CLAUDE_STATUS_PORT:-7842}"
STATE="${1:-idle}"

payload="$(cat)"

tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
message="$(printf '%s' "$payload" | jq -r '.message // empty' 2>/dev/null)"

# Claude's interactive question tool → treat as "waiting for your answer".
if [ "$tool" = "AskUserQuestion" ]; then STATE="waiting"; fi

detail=""
question=""
options="[]"
notify="false"

case "$STATE" in
  working)
    case "$tool" in
      Bash)
        d="$(printf '%s' "$payload" | jq -r '.tool_input.description // .tool_input.command // empty' 2>/dev/null)"
        detail="Running: ${d}" ;;
      Read|Edit|Write|NotebookEdit)
        f="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
        detail="${tool} ${f##*/}" ;;
      Grep|Glob)
        q="$(printf '%s' "$payload" | jq -r '.tool_input.pattern // .tool_input.query // empty' 2>/dev/null)"
        detail="${tool}: ${q}" ;;
      Task|Agent)
        detail="Running subagent" ;;
      "")
        detail="Working" ;;
      *)
        detail="${tool}" ;;
    esac ;;
  waiting)
    q2="$(printf '%s' "$payload" | jq -r '.tool_input.questions[0].question // empty' 2>/dev/null)"
    o2="$(printf '%s' "$payload" | jq -c '[.tool_input.questions[0].options[].label]' 2>/dev/null)"
    detail="${message:-${q2:-Needs your input}}"
    question="${message:-${q2:-Claude needs your input}}"
    [ -n "$o2" ] && [ "$o2" != "null" ] && options="$o2"
    notify="true" ;;
  thinking)
    detail="" ;;
  done)
    detail="" ;;
  idle)
    detail="" ;;
esac

# Trim overly long detail lines.
if [ "${#detail}" -gt 70 ]; then
  detail="${detail:0:67}…"
fi

body="$(jq -nc \
  --arg state "$STATE" \
  --arg detail "$detail" \
  --arg question "$question" \
  --argjson options "$options" \
  --argjson notify "$notify" \
  '{state: $state, detail: $detail, question: $question, options: $options, notify: $notify, notifyTitle: "Claude", notifyBody: $detail}')"

curl -s -m 1 -X POST "http://127.0.0.1:${PORT}/status" \
  -H 'Content-Type: application/json' \
  -d "$body" >/dev/null 2>&1 || true

exit 0
