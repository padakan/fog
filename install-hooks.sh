#!/bin/bash
# Register the Claude Status Border hooks into a Claude Code settings.json.
#
#   ./install-hooks.sh            # installs into ~/.claude/settings.json (global)
#   ./install-hooks.sh ./path     # installs into <path>/.claude/settings.json
#
# Idempotent: re-running replaces our own entries, leaving any other hooks alone.
set -euo pipefail
cd "$(dirname "$0")"

HOOK="$(pwd)/hooks/claude-status-notify.sh"
chmod +x "$HOOK"

if [ "${1:-}" != "" ]; then
  SETTINGS="$(cd "$1" && pwd)/.claude/settings.json"
else
  SETTINGS="${HOME}/.claude/settings.json"
fi
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# event : state : matcher (matcher only meaningful for tool events)
pairs=(
  "SessionStart:idle:"
  "UserPromptSubmit:thinking:"
  "PreToolUse:working:*"
  "PostToolUse:thinking:*"
  "Notification:waiting:"
  "Stop:done:"
)

tmp="$(mktemp)"; cp "$SETTINGS" "$tmp"

for pair in "${pairs[@]}"; do
  event="${pair%%:*}"; rest="${pair#*:}"
  state="${rest%%:*}"; matcher="${rest#*:}"
  cmd="${HOOK} ${state}"

  jq --arg event "$event" --arg cmd "$cmd" --arg matcher "$matcher" '
    .hooks = (.hooks // {}) |
    .hooks[$event] = (.hooks[$event] // []) |
    # drop any previous entry that references our script (idempotent re-install)
    .hooks[$event] = [ .hooks[$event][]
      | select( ([(.hooks // [])[].command] | map(test("claude-status-notify.sh")) | any) | not ) ] |
    .hooks[$event] += [
      ( if $matcher == ""
        then { hooks: [ { type: "command", command: $cmd } ] }
        else { matcher: $matcher, hooks: [ { type: "command", command: $cmd } ] }
        end )
    ]
  ' "$tmp" > "${tmp}.out" && mv "${tmp}.out" "$tmp"
done

mv "$tmp" "$SETTINGS"
echo "✓ Hooks installed into: $SETTINGS"
echo "  Restart any running Claude Code sessions to pick them up."
