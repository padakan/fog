# Fog adapters — Codex CLI · Gemini CLI · Cursor

Fog is just a local status sink (HTTP `POST 127.0.0.1:7842`). Any agent whose hooks
can run a shell command and pass a JSON event on stdin can drive it. These three all
can, so they share one bridge script: [`agent-status-notify.sh`](agent-status-notify.sh).

> Claude Code uses its own [`../hooks/claude-status-notify.sh`](../hooks/claude-status-notify.sh)
> + `../install-hooks.sh`. Claude Code running inside Cursor/VS Code/JetBrains terminals
> already works through that — nothing extra needed.

## Install

Make sure `Fog.app` is running, then:

```bash
./install-adapters.sh codex     # → ~/.codex/hooks.json
./install-adapters.sh gemini    # → ~/.gemini/settings.json (merges the "hooks" key)
./install-adapters.sh cursor    # → ~/.cursor/hooks.json
```

Restart the tool afterwards. Re-running is idempotent (overwrites only Fog's own
event entries; other settings are preserved).

## What maps to what

| State | Codex CLI | Gemini CLI | Cursor |
|-------|-----------|------------|--------|
| thinking | `UserPromptSubmit` | `BeforeAgent` | `beforeSubmitPrompt` |
| working  | `PreToolUse` | `BeforeTool` / `AfterTool` | `preToolUse` |
| waiting  | `PermissionRequest` | `Notification` (ToolPermission) | — (no clean event) |
| done     | `Stop` | `AfterAgent` | `stop` |
| idle     | `SessionStart` | `SessionStart` | `sessionStart` |

### Per-tool notes
- **Codex** — no dedicated "model is thinking" event; we proxy it with
  `UserPromptSubmit`. Everything else maps cleanly. Hooks live in `~/.codex/hooks.json`
  (you can also inline them in `config.toml`).
- **Gemini** — the richest: all four states map directly.
- **Cursor** — its built-in AI exposes no clean "waiting for approval" event, so there's
  no `waiting` mapping (you still get thinking/working/done). Hooks are a Cursor 1.7+
  feature (beta).

## Caveat — single border, multiple sources

Fog shows one global status. If two agents run at once (e.g. Claude Code + Cursor),
they share the same border — last event wins. Fine for one-agent-at-a-time use; a
per-source/priority model would be needed to show several at once.

## Status of these adapters

The `agent-status-notify.sh → Fog` path is verified (simulated payloads). The hook
configs follow each tool's documented format, but were authored from docs — none of
the three CLIs/editors were installed here to test end-to-end. If a field differs in
your version, tweak `agent-status-notify.sh` (it already tries several field names).
