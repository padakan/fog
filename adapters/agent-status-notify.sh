#!/bin/bash
# Generic agent → Fog bridge.
#
# Works for any coding agent whose hooks run a shell command and pass a JSON event
# on stdin — verified shapes: Codex CLI, Gemini CLI, Cursor. (Claude Code uses its
# own hooks/claude-status-notify.sh, but this script works there too.)
#
# Usage:  agent-status-notify.sh <state>
#   state = idle | thinking | working | waiting | done
#
# Never blocks the agent: short curl timeout, always exits 0.

PORT="${FOG_STATUS_PORT:-7842}"
STATE="${1:-idle}"
payload="$(cat 2>/dev/null)"

jqget() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

# Field names vary across tools — try the common ones.
tool="$(jqget '.tool_name')"; [ -z "$tool" ] && tool="$(jqget '.tool')"
cmd="$(jqget '.tool_input.command')"; [ -z "$cmd" ] && cmd="$(jqget '.command')"
file="$(jqget '.tool_input.file_path')"; [ -z "$file" ] && file="$(jqget '.file_path')"
msg="$(jqget '.message')"; [ -z "$msg" ] && msg="$(jqget '.notification')"; [ -z "$msg" ] && msg="$(jqget '.details')"

detail=""; question=""; notify="false"
case "$STATE" in
  working)
    if [ -n "$tool" ] && [ -n "$file" ]; then detail="$tool ${file##*/}"
    elif [ -n "$cmd" ]; then detail="Running: $cmd"
    elif [ -n "$tool" ]; then detail="$tool"
    else detail="Working"; fi ;;
  waiting)
    detail="${msg:-Needs your input}"
    question="${msg:-Agent needs your input}"
    notify="true" ;;
esac

if [ "${#detail}" -gt 70 ]; then detail="${detail:0:67}…"; fi

body="$(jq -nc \
  --arg s "$STATE" --arg d "$detail" --arg q "$question" --argjson n "$notify" \
  '{state:$s, detail:$d, question:$q, notify:$n, notifyTitle:"Fog", notifyBody:$d}')"

curl -s -m 1 -X POST "http://127.0.0.1:${PORT}/status" \
  -H 'Content-Type: application/json' -d "$body" >/dev/null 2>&1 || true

exit 0
