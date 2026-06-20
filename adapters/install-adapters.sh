#!/bin/bash
# Install Fog hook adapters for Codex CLI, Gemini CLI, or Cursor.
#
#   ./install-adapters.sh codex
#   ./install-adapters.sh gemini
#   ./install-adapters.sh cursor
#
# Idempotent: re-running overwrites only Fog's own event entries, preserving other
# top-level settings. (If you already have a custom hook on one of the same events,
# it will be replaced — back up first if so.)
set -euo pipefail
cd "$(dirname "$0")"

SCRIPT="$(pwd)/agent-status-notify.sh"
chmod +x "$SCRIPT"
TOOL="${1:-}"

case "$TOOL" in
  codex)
    TARGET="$HOME/.codex/hooks.json"; SHAPE="nested"
    EVENTS="SessionStart:idle UserPromptSubmit:thinking PreToolUse:working PostToolUse:thinking PermissionRequest:waiting Stop:done" ;;
  gemini)
    TARGET="$HOME/.gemini/settings.json"; SHAPE="nested"
    EVENTS="SessionStart:idle BeforeAgent:thinking BeforeTool:working AfterTool:thinking Notification:waiting AfterAgent:done" ;;
  cursor)
    # Cursor has no clean "waiting for approval" event, so no waiting mapping.
    TARGET="$HOME/.cursor/hooks.json"; SHAPE="flat"
    EVENTS="sessionStart:idle beforeSubmitPrompt:thinking preToolUse:working postToolUse:thinking stop:done" ;;
  *)
    echo "usage: ./install-adapters.sh <codex|gemini|cursor>"; exit 1 ;;
esac

mkdir -p "$(dirname "$TARGET")"
[ -f "$TARGET" ] || echo '{}' > "$TARGET"
tmp="$(mktemp)"; cp "$TARGET" "$tmp"

for pair in $EVENTS; do
  ev="${pair%%:*}"; st="${pair##*:}"; cmd="$SCRIPT $st"
  if [ "$SHAPE" = "nested" ]; then
    entry="$(jq -nc --arg c "$cmd" '[{hooks:[{type:"command",command:$c}]}]')"
  else
    entry="$(jq -nc --arg c "$cmd" '[{command:$c}]')"
  fi
  jq --arg ev "$ev" --argjson entry "$entry" \
    '.hooks = (.hooks // {}) | .hooks[$ev] = $entry' "$tmp" > "$tmp.o" && mv "$tmp.o" "$tmp"
done

if [ "$TOOL" = "cursor" ]; then
  jq '.version = (.version // 1)' "$tmp" > "$tmp.o" && mv "$tmp.o" "$tmp"
fi

mv "$tmp" "$TARGET"
echo "✓ Installed Fog $TOOL adapter → $TARGET"
echo "  Make sure Fog.app is running, then restart $TOOL."
