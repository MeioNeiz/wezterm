a91f883c38371b4d5 ####################

I have what I need. Here is the report.

---

# Terminal-multiplexer-native tooling for driving Claude Code, 2026

**Headline finding: the highest-value things to steal are now first-party.** Between late 2025 and mid 2026 Anthropic shipped (a) a machine-readable session state API (`claude agents --json`), (b) a hook event catalogue of ~35 events with documented JSON payloads, (c) native tmux/iTerm2 split-pane agent teams, and (d) a per-session Unix domain socket for pushing text into a running session. Most of the third-party session managers in this cluster exist to paper over gaps that no longer exist. The interesting third-party work in 2026 is no longer "scrape the TUI", it is "intercept the harness" (happy) and "impersonate tmux" (cmux).

Everything below was verified against a fetched page or source file, with URLs inline. Docs moved from `docs.claude.com/en/docs/claude-code/` to `code.claude.com/docs/en/`; appending `.md` to any docs URL returns raw markdown, which is far better than scraping the HTML.

---

## 1. Official Claude Code surface (steal from here first)

### 1.1 Hook events, complete catalogue

Source: https://code.claude.com/docs/en/hooks.md

Events fall into three cadences: once per session (`SessionStart`, `SessionEnd`), once per turn (`UserPromptSubmit`, `Stop`, `StopFailure`), and per tool call (`PreToolUse`, `PostToolUse`).

Full event list as of the current docs: `SessionStart`, `Setup`, `InstructionsLoaded`, `UserPromptSubmit`, `UserPromptExpansion`, `MessageDisplay`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `PermissionDenied`, `Notification`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `ConfigChange`, `CwdChanged`, `DirectoryAdded`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `SessionEnd`, `Elicitation`, `ElicitationResult`.

There are five handler types, not just `command`: `command`, `http` (POST, same JSON body), `mcp_tool`, `prompt` (single-turn LLM eval returning JSON), and `agent` (spawns a subagent to decide). Handler common fields: `type`, `if` (a single permission rule such as `"Bash(git *)"` or `"Edit(*.ts)"`), `timeout` (default 600s for command/http/mcp_tool), `statusMessage` (custom spinner text), `once`. Command hooks add `command`, `args` (exec form, no shell), `async`, `asyncRewake`, `shell` (`"bash"`/`"powershell"`).

`asyncRewake: true` is underrated: the hook runs in the background and **wakes Claude on exit code 2**, delivering stderr as a system reminder. That is a supported "poke a running agent from outside" channel.

### 1.2 Common input fields (stdin JSON)

`session_id`, `prompt_id` (UUID of the current user prompt, matches OTel `prompt.id`, v2.1.196+), `transcript_path`, `cwd`, `permission_mode` (`"default"`, `"plan"`, `"acceptEdits"`, `"auto"`, `"dontAsk"`, `"bypassPermissions"`; the UI's **Manual** arrives as `"default"`), `effort` (object with `level`: `low`/`medium`/`high`/`xhigh`/`max`), `hook_event_name`. Inside a subagent or `--agent`: `agent_id`, `agent_type`.

Verbatim `PreToolUse` example from the docs:

```json
{
  "session_id": "abc123",
  "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
  "transcript_path": "/home/user/.claude/projects/.../transcript.jsonl",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "npm test", "description": "Run test suite", "timeout": 120000, "run_in_background": false },
  "tool_use_id": "toolu_01ABC123..."
}
```

Important gotcha the docs state explicitly: **the transcript file is written asynchronously and may lag the in-memory conversation.** Hooks needing the current turn's final text must use `last_assistant_message` on `Stop`/`SubagentStop`, not parse the JSONL.

### 1.3 The three state-signalling events (this is the core of state detection)

**`Notification`**, matched on `notification_type`. The matcher values are the state machine:

| Matcher | Fires when |
|---|---|
| `permission_prompt` | Claude needs tool approval and the prompt has waited ~6 seconds |
| `idle_prompt` | Claude finished responding ~60s ago and you have not typed since |
| `agent_needs_input` | A background session starts waiting on input while agent view is open, or a teammate asks a terminal setup question (v2.1.198+, teammate case v2.1.248+) |
| `agent_completed` | A background session finishes or fails, only while agent view is open (v2.1.198+) |
| `elicitation_dialog`, `elicitation_url_dialog`, `elicitation_complete`, `elicitation_response` | MCP elicitation lifecycle |
| `auth_success` | Auth completes |
| `quota_auto_resume_fired` / `_stale` / `_disabled` | Usage-limit pause handling (v2.1.234+) |

Payload:

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf-....jsonl",
  "cwd": "/Users/...",
  "hook_event_name": "Notification",
  "message": "Claude needs your permission",
  "title": "Permission needed",
  "notification_type": "permission_prompt"
}
```

Critical timing caveat: `permission_prompt`, `idle_prompt`, `elicitation_dialog` and `elicitation_url_dialog` are **gated on you appearing to be away**. `permission_prompt` waits ~6s and each keystroke defers it; `idle_prompt` waits ~60s. If you want an instant signal when Claude asks for permission, use a `PermissionRequest` hook, not `Notification`. Hook events still fire even with desktop notifications disabled (`preferredNotifChannel: notifications_disabled` changes alerting, not hook execution).

**`Stop`** (main agent finished a turn; does **not** run on user interrupt; API errors fire `StopFailure` instead):

```json
{
  "session_id": "abc123",
  "transcript_path": "~/.claude/projects/.../00893aaf-....jsonl",
  "cwd": "/Users/...",
  "permission_mode": "default",
  "hook_event_name": "Stop",
  "stop_hook_active": true,
  "last_assistant_message": "I've completed the refactoring. Here's a summary...",
  "background_tasks": [
    { "id": "task-001", "type": "shell", "status": "running", "description": "tail logs", "command": "tail -f /var/log/syslog" }
  ],
  "session_crons": [
    { "id": "cron-001", "schedule": "0 9 * * 1-5", "recurring": true, "prompt": "check the build" }
  ]
}
```

`background_tasks[].type` is one of `shell`, `subagent`, `monitor`, `workflow`, `teammate`, `cloud session`, `MCP task`. This array is exactly how you distinguish **"session is done"** from **"session is parked waiting for background work to wake it"**, which is the single biggest false-idle source in any screen-scraping approach. `stop_hook_active` is `true` when Claude is already continuing because of a prior Stop-hook block, and is your loop guard.

**`StopFailure`** carries `error` (one of `rate_limit`, `overloaded`, `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `billing_error`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `unknown`), `error_details`, and `last_assistant_message` (here the rendered API error text, e.g. `"API Error: Rate limit reached"`). Output and exit code are ignored **except** `terminalSequence`.

**`TeammateIdle`** (new, agent teams): fires when a teammate is about to go idle. Payload adds `teammate_name` and `team_name` (the latter deprecated). Exit 2 keeps the teammate working with stderr as feedback; `{"continue": false, "stopReason": "..."}` stops it entirely.

### 1.4 JSON output, exit codes, decision control

Universal output fields: `continue` (default `true`; `false` stops processing and takes precedence over event-specific decisions), `stopReason`, `suppressOutput` (**accepted but has no effect**), `systemMessage`, `terminalSequence`.

Exit code semantics: **exit 2 is the only code that blocks through the code alone.** Exit 1 is treated as a non-blocking error and the action proceeds. Any non-2 exit code with a schema-valid JSON object on stdout: the JSON alone decides and the exit code is ignored. Stdout is parsed as JSON only if it starts with `{` **and** ends with `}`. Output strings are capped at 10,000 characters, beyond which they are written to a file and replaced with a preview plus path.

Per-event exit-2 behaviour (abridged from the docs table): blocks on `PreToolUse`, `UserPromptSubmit`, `UserPromptExpansion`, `Stop`, `SubagentStop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `ConfigChange`, `PostToolBatch`, `PreCompact`, `PreModelSwitch`, `Elicitation`, `ElicitationResult`, `WorktreeCreate` (any non-zero). Ignored on `Notification`, `StopFailure`, `Setup`, `PermissionDenied`, `SessionEnd`, `InstructionsLoaded`, `MessageDisplay`.

Decision patterns: top-level `{"decision": "block", "reason": "..."}` for `UserPromptSubmit`/`PostToolUse`/`Stop`/`SubagentStop`/`PreCompact`/etc; `hookSpecificOutput.permissionDecision` (`allow`/`deny`/`ask`/`defer`) plus `permissionDecisionReason` for `PreToolUse`; `hookSpecificOutput.decision.behavior` (`allow`/`deny`) for `PermissionRequest`. Rewrites: `PreToolUse.updatedInput`, `PostToolUse.updatedToolOutput`, `PermissionRequest.decision.updatedInput`.

### 1.5 `terminalSequence`: the WezTerm-specific win

Hooks run **without a controlling terminal** on macOS and Linux, so writing escape sequences to `/dev/tty` fails. Instead return `terminalSequence` and Claude Code emits it through its own terminal write path, race-free. Allowlist: OSC `0`/`1`/`2` (window and icon titles), OSC `9` (**explicitly documented as iTerm2, ConEmu, Windows Terminal and WezTerm notifications, including `9;4` taskbar progress**), OSC `99` (Kitty), OSC `777` (urxvt, Ghostty, Warp), and bare BEL. Everything else, including OSC 8 hyperlinks and OSC 52 clipboard, is rejected and the whole field ignored. It works even on events that discard `systemMessage`, such as `Notification` and `StopFailure`. It is ignored in `-p` mode and the SDK.

Documented example:

```bash
#!/bin/bash
input=$(cat)
title="Claude Code"
body=$(jq -r '.message // "Needs your attention"' <<<"$input")
seq=$(printf '\033]777;notify;%s;%s\007' "$title" "$body")
jq -nc --arg seq "$seq" '{terminalSequence: $seq}'
```

For WezTerm, swap the OSC 777 for OSC 9, and consider `9;4` for per-pane taskbar progress.

### 1.6 Agent view: the native `claude agents --json` state API

Source: https://code.claude.com/docs/en/agent-view.md

This is the single most valuable thing in the entire report. `claude agents --json` prints active sessions as a JSON array and exits. Fields:

| Field | Present | Meaning |
|---|---|---|
| `cwd`, `kind`, `startedAt` | always | `kind` is `interactive` or `background`; `startedAt` in Unix ms |
| `id` | background | short ID for `claude attach` / `logs` / `stop` |
| `state` | background | one of `working`, `blocked`, `done`, `failed`, `stopped` |
| `pid`, `status` | while alive | process ID and current status |
| `waitingFor` | when `status` is `waiting` | `permission prompt`, `input needed`, `sandbox request`, `worker...` |
| `sessionId`, `name` | when set | full UUID usable with `--resume` |

Add `--all` to include completed background sessions. `claude agents --cwd <path>` scopes it.

Shell management commands: `claude attach <id>`, `claude logs <id>`, `claude stop <id>` (alias `claude kill`), `claude respawn <id>` / `--all`, `claude rm <id>`, `claude daemon status`, `claude daemon stop --any [--keep-workers]`.

On-disk state:

| Path | Contents |
|---|---|
| `~/.claude/daemon.log` | supervisor log |
| `~/.claude/daemon/roster.json` | running background sessions, for reconnect after restart |
| `~/.claude/jobs/<id>/state.json` | per-session state shown in agent view |
| `~/.claude/jobs/<id>/tmp/` | per-session scratch, writes here do not prompt for permission |

Each background session gets `CLAUDE_JOB_DIR` pointing at `~/.claude/jobs/<id>`. Setting `CLAUDE_CONFIG_DIR` makes the supervisor run as a **separate instance with its own sessions**, which is a clean way to sandbox an experiment.

The UI state model (worth copying wholesale): state is `Working` / `Needs input` / `Idle` / `Completed` / `Failed` / `Stopped`, and **separately** the icon shape encodes process liveness: `✻`/animated `✽` = process alive, `∙` = process exited (still resumable), `✢` = a `/loop` session sleeping between iterations. Decoupling "task state" from "process alive" is the right model and is what most third-party tools get wrong. Row summaries are generated by a Haiku-class model. The terminal tab title shows `2 awaiting input · claude agents`.

### 1.7 Agent teams: native tmux and iTerm2 split panes

Source: https://code.claude.com/docs/en/agent-teams.md

Enabled by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in env or settings.json. Display mode is set by `--teammate-mode` (experimental, does **not** appear in `claude --help`) or the `teammateMode` setting, with values `in-process` (default since v2.1.179), `auto`, `tmux`, `iterm2` (v2.1.186+). Split-pane mode requires tmux or iTerm2 with the `it2` CLI (https://github.com/mkusaka/it2) plus iTerm2's Python API enabled. It is explicitly **not supported** in VS Code's integrated terminal, Windows Terminal, or Ghostty. `tmux -CC` in iTerm2 is the suggested entry point.

Architecture and on-disk layout, all under a session-derived team name of `session-` plus the first eight characters of the session ID:

- Team config: `~/.claude/teams/{team-name}/config.json` — holds runtime state including session IDs **and tmux pane IDs**; the docs warn it is overwritten on every state update, so do not hand-edit
- Mailboxes: `~/.claude/teams/{team-name}/inboxes/{agent-name}.json` — one JSON file per agent, entries validated on read
- Task list: `~/.claude/tasks/{team-name}/` — persists after the team config directory is removed at session end

The `members` array carries each member's name and agent ID; the lead's entry always has agent type `team-lead`. There is **no** project-level equivalent; `.claude/teams/teams.json` in a project is treated as an ordinary file. Nesting is unsupported: a teammate cannot spawn a sub-team. Teammate permission prompts surface in the **lead** session.

Separately, `claude --worktree <name> --tmux` natively creates a tmux session for a worktree (`--tmux` requires `--worktree`; uses iTerm2 native panes when available, `--tmux=classic` forces traditional tmux). Worktrees land at `<repo>/.claude/worktrees/<name>`.

Troubleshooting section confirms teams can leave **orphaned tmux sessions**: `tmux ls` then `tmux kill-session -t <session-name>`.

### 1.8 Cross-session messaging: the per-session Unix socket

Source: https://code.claude.com/docs/en/cross-session-messaging.md

Claude Code binds an **inbox socket per session**: a Unix domain socket on macOS/Linux/WSL2, a named pipe on native Windows. Two ways to find it:

- `/status` shows it in the `Peer address` row, prefixed `uds:`
- exported to hooks and Bash commands as **`CLAUDE_CODE_MESSAGING_SOCKET`**, set before any hook runs including `SessionStart`; each session exports its own, never an inherited one

A per-session token is exported as **`CLAUDE_CODE_MESSAGING_TOKEN`**. A script posting to its own session's socket sends `{"type":"auth","token":"<token>"}` as the first line: optional on macOS/Linux, **required** on native Windows. Open the connection only when the message is ready, because Claude Code closes a connection that has not sent a complete line within 30 seconds. When the socket directory is unacceptable it falls back to a private per-user directory `/tmp/cc-socks-<uid>`.

Own-child messages (a hook or Bash command posting back to its own session) are delivered without inbound-control gating when no `crossSessionInbound` value applies. On Linux this is verified by process evidence even after the child exits; on macOS only while the posting process is still running, otherwise it falls back to the token.

The receiving Claude reads the message **between tool calls** during an active turn, so a running tool is never interrupted; if the session is idle, Claude Code starts a new turn with the message. Inbound controls are `accept` / `hold` / `refuse` via the `crossSessionInbound` setting.

There is also a one-shot idle subscription: the `SendMessage` tool's `notify_when_idle` input asks another local session to send back one notice when it next goes idle or exits. It expires unanswered after 12 hours and only the main conversation's Claude can subscribe (not subagents or teammates). `/list-agents` shows reachable targets.

### 1.9 Headless and stream-json

Source: https://code.claude.com/docs/en/headless.md and https://code.claude.com/docs/en/agent-sdk/typescript.md

`--output-format` is `text` | `json` | `stream-json`. Streaming: `claude -p "..." --output-format stream-json --verbose --include-partial-messages`. Documented filter:

```bash
claude -p "Write a poem" --output-format stream-json --verbose --include-partial-messages | \
  jq -rj 'select(.type == "stream_event" and .event.delta.type? == "text_delta") | .event.delta.text'
```

`--bare` skips auto-discovery of hooks, skills, commands, subagents, plugins, MCP servers, auto memory and CLAUDE.md, and is documented as the recommended mode for scripted calls and the future default for `-p`. Note the security point: **without** `--bare`, a `-p` session runs the hooks in a project's `.claude/settings.json` and connects its `.mcp.json` servers even in a folder you have never trusted, with no trust dialog.

The `SDKMessage` union (the exact `type`/`subtype` values on the wire) is much wider than most tooling assumes:

`SDKAssistantMessage`, `SDKUserMessage`, `SDKUserMessageReplay`, `SDKResultMessage`, `SDKSystemMessage`, `SDKPartialAssistantMessage`, `SDKCompactBoundaryMessage`, `SDKStatusMessage`, `SDKLocalCommandOutputMessage`, `SDKHookStartedMessage`, `SDKHookProgressMessage`, `SDKHookResponseMessage`, `SDKPluginInstallMessage`, `SDKToolProgressMessage`, `SDKAuthStatusMessage`, `SDKTaskNotificationMessage`, `SDKTaskStartedMessage`, `SDKTaskProgressMessage`, `SDKTaskUpdatedMessage`, `SDKBackgroundTasksChangedMessage`, `SDKThinkingTokensMessage`, `SDKSessionStateChangedMessage`, `SDKWorkerShuttingDownMessage`, `SDKCommandsChangedMessage`, `SDKNotificationMessage`, `SDKFilesPersistedEvent`, `SDKToolUseSummaryMessage`, `SDKMemoryRecallMessage`, `SDKRateLimitEvent`, `SDKElicitationCompleteMessage`, `SDKPermissionDeniedMessage`, `SDKPromptSuggestionMessage`, `SDKAPIRetryMessage`, `SDKMirrorErrorMessage`, `SDKInformationalMessage`, `SDKConversationResetMessage`.

Caveat on honesty: `SDKSessionStateChangedMessage` and `SDKNotificationMessage` are listed in the union but I could not find their field definitions on that page, so I am not quoting shapes for them.

The ones that matter for state:

```typescript
type SDKSystemMessage = {
  type: "system"; subtype: "init";
  uuid: UUID; session_id: string;
  agents?: string[]; apiKeySource: ApiKeySource; betas?: string[];
  claude_code_version: string; cwd: string; tools: string[];
  mcp_servers: { name: string; status: string }[];
  model: string; permissionMode: PermissionMode;
  slash_commands: string[]; terminal_slash_commands?: string[];
  output_style: string; skills: string[];
  plugins: { name: string; path: string }[];
  fast_mode_state?: FastModeState; fast_mode_disabled_reason?: FastModeDisabledReason;
  effort?: "low"|"medium"|"high"|"xhigh"|"max"|null;
  capabilities?: string[];
};
```

`capabilities` is an open set for feature detection instead of version-string comparison (e.g. `interrupt_receipt_v1`, `interrupt_cancel_queued_v1`).

```typescript
type SDKToolProgressMessage = {
  type: "tool_progress"; tool_use_id: string; tool_name: string;
  parent_tool_use_id: string | null; elapsed_time_seconds: number;
  task_id?: string; heartbeat?: boolean; subagent_type?: string;
  subagent_retry?: { agent_id: string; attempt: number; max_retries: number;
                     retry_delay_ms: number; error_status: number | null; error_category: string };
  uuid: UUID; session_id: string;
};
```

A `tool_progress` with `heartbeat: true` is emitted **every 30 seconds** while a tool runs in the main conversation. That is a ready-made liveness beat: no heartbeat plus no result means the session is wedged, not busy.

```typescript
type SDKBackgroundTasksChangedMessage = {
  type: "system"; subtype: "background_tasks_changed";
  tasks: { task_id: string; task_type: string; description: string; ambient?: boolean }[];
  uuid: UUID; session_id: string;
};
```

The `tasks` array is the full current set, not a delta. Nothing is emitted at startup; reset to empty on CLI restart. Requires v2.1.203+.

`SDKResultMessage` success arm carries `duration_ms`, `duration_api_ms`, `num_turns`, `result`, `stop_reason`, `ttft_ms`, `ttft_stream_ms`, `total_cost_usd`, `usage`, `modelUsage`, `permission_denials`, `queued_turn_count`, `structured_output`, `deferred_tool_use`, `terminal_reason`, `origin`. Error arm subtypes: `error_max_turns`, `error_during_execution`, `error_max_budget_usd`, `error_max_structured_output_retries`. `terminal_reason` is one of `completed`, `max_turns`, `tool_deferred`, `aborted_streaming`, `aborted_tools`, `hook_stopped`, `stop_hook_prevented`, `background_reque…` (truncated in the docs table). Use `modelUsage`, not `usage`, for accounting: `usage` is main-loop only and excludes subagents.

Subagent attribution: subagent messages carry `parent_tool_use_id` = the ID of the spawning tool call; main-conversation messages carry `null`. By default only subagent `tool_use`/`tool_result` blocks are emitted; `--forward-subagent-text` or `CLAUDE_CODE_FORWARD_SUBAGENT_TEXT=1` adds their text and thinking, at every nesting depth.

`--include-hook-events` puts `hook_started` / `hook_progress` / `hook_response` into the stream (`SessionStart` and `Setup` hook events are always included).

### 1.10 Session/transcript layout on disk

Source: https://code.claude.com/docs/en/sessions.md

Transcripts are JSONL at **`~/.claude/projects/<project>/<session-id>.jsonl`**, where `<project>` is the working directory path with non-alphanumeric characters replaced by `-`. The docs explicitly warn: *"The entry format is internal to Claude Code and changes between versions, so scripts that parse these files directly can break on any release."* Prefer `/export`, `claude -p --output-format json`, or the `transcript_path` handed to hooks.

Relocation: `CLAUDE_CONFIG_DIR` moves the root; `CLAUDE_CODE_PROJECT_DIR_NAME` (set together with `CLAUDE_CONFIG_DIR`) names the `projects/` subdirectory yourself. Retention is `cleanupPeriodDays` (default 30). `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` suppresses transcript writes entirely (and removes the session from `--resume`/`--continue`).

Sessions created with `claude -p` or the Agent SDK are excluded from the `/resume` picker and from `claude --continue`, but can still be resumed by explicit ID. `claude -p --continue` **does** include them.

### 1.11 Status line JSON

Source: https://code.claude.com/docs/en/statusline.md

The `statusLine` command receives on stdin (abridged, real example from the docs):

```json
{
  "cwd": "...", "session_id": "abc123...", "session_name": "my-session",
  "prompt_id": "550e8400-...", "transcript_path": "/path/to/transcript.jsonl",
  "model": { "id": "claude-opus-5", "display_name": "Opus" },
  "workspace": { "current_dir": "...", "project_dir": "...", "added_dirs": [],
                 "git_worktree": "feature-xyz",
                 "repo": { "host": "github.com", "owner": "anthropics", "name": "claude-code" } },
  "version": "2.1.90",
  "output_style": { "name": "default" },
  "cost": { "total_cost_usd": 0.01234, "total_duration_ms": 45000, "total_api_duration_ms": 2300,
            "total_lines_added": 156, "total_lines_removed": 23 },
  "context_window": { "total_input_tokens": 15500, "total_output_tokens": 1200,
                      "context_window_size": 200000, "used_percentage": 8, "remaining_percentage": 92,
                      "current_usage": { "input_tokens": 8500, "output_tokens": 1200,
                                         "cache_creation_input_tokens": 5000, "cache_read_input_tokens": 2000 } },
  "exceeds_200k_tokens": false,
  "prompt_cache": { "warm": true, "ttl": "1h", "expires_at": 1738429200, "hit_ratio": 0.91, ... },
  "fast_mode": false,
  "effort": { "level": "high" },
  "thinking": { "enabled": true },
  "rate_limits": { "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
                   "seven_day": { ... }, "spend_limit": { ... } },
  "vim": { "mode": "NORMAL" }
}
```

Note there is **no agent state field here**. The status line tells you context, cost and rate limits, not busy/idle. Do not try to build state detection on it. The docs also give a useful caching tip: use `session_id` as the cache-file key because it is stable per session and unique across concurrent sessions, whereas `$$`/`os.getpid()` changes every invocation.

There is also a `subagentStatusLine` setting (mentioned under `allowManagedHooksOnly` restrictions).

### 1.12 Env vars worth knowing

From https://code.claude.com/docs/en/env-vars.md:

- `CLAUDECODE=1` set in every subprocess Claude Code spawns (Bash/PowerShell tools, **tmux sessions**, hook commands, status line). This is how you detect "am I inside Claude Code", and why nesting tools `unset CLAUDECODE`.
- `CLAUDE_CODE_CHILD_SESSION=1` in Bash/PowerShell/Monitor subprocesses, hook commands and status line.
- `CLAUDE_CODE_SESSION_ID` set automatically in Bash/PowerShell tool subprocesses, hook command subprocesses, and stdio MCP servers.
- `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` forces transcript persistence, prompt history and `claude agents` registration **even when this `claude` was launched from inside another one**. Essential if your bash scripts spawn Claude from within Claude.
- `CLAUDE_CODE_TASK_LIST_ID` shares a task list across sessions: set the same ID in multiple instances to coordinate.
- `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, `CLAUDE_CODE_SUBAGENT_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`.
- `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` plus `CLAUDE_CODE_RESUME_PROMPT` (default `Continue from where you left off.`) and `CLAUDE_CODE_RESUME_INTERRUPTED_TURN_MAX_AGE_MS`. Purpose-built for spawn scripts.
- `CLAUDE_CODE_RETRY_WATCHDOG=1` retries 429/529 indefinitely, documented for unattended sessions, eval harnesses, CI and remote workers.
- `CLAUDE_CODE_PROCESS_WRAPPER` routes every process Claude Code starts from its own binary (including the supervisor and every agent view session) through a launcher of your choosing.
- `CLAUDE_ENV_FILE` available to `SessionStart`, `Setup`, `CwdChanged` and `FileChanged` hooks: append `export FOO=bar` lines and they persist into subsequent Bash commands for the session.

### 1.13 CLI flags relevant to orchestration (verbatim descriptions)

- `--session-id` — "Use a specific session ID for the conversation (must be a valid UUID)"
- `--fork-session` — "When resuming, create a new session ID instead of reusing the original"
- `--name`, `-n` — display name, shown in `/resume` and the terminal title; resumable via `claude --resume <name>`
- `--bg`, `--background` — "Start the session as a background agent and return immediately. Prints the session ID and management commands." Cannot combine with `-p`.
- `--exec` — "Run a shell command as a PTY-backed background job instead of starting a Claude session. Use with `--bg`"
- `--teammate-mode` — `in-process` (default), `auto`, `tmux`, `iterm2`
- `--tmux` — "Create a tmux session for the worktree. Requires `--worktree`. Uses iTerm2 native panes when available; pass `--tmux=classic` for traditional tmux"
- `--worktree`, `-w` — isolated worktree at `<repo>/.claude/worktrees/<name>`; accepts `#<number>` or a PR/MR URL
- `--agents` — define custom subagents dynamically via JSON
- `--replay-user-messages` — re-emit stdin user messages on stdout for acknowledgement; requires stream-json both ways
- `--include-hook-events`, `--include-partial-messages`, `--input-format`, `--output-format`, `--json-schema`, `--max-turns`, `--max-budget-usd`, `--settings`, `--mcp-config`, `--add-dir`, `--permission-mode`, `--channels`, `--init-only`, `--maintenance`

### 1.14 `SessionStart` output: auto-naming and auto-prompting panes

`hookSpecificOutput` for `SessionStart` accepts `additionalContext`, **`initialUserMessage`** (becomes the first user turn in `-p` mode even with no prompt supplied), **`sessionTitle`** (same effect as `/rename`, applies when `source` is `startup`/`resume`/`fork`), **`watchPaths`** (array of absolute paths to watch, generating `FileChanged` events), and `reloadSkills`. The input carries `session_title` so you can avoid overwriting a title the user set.

`source` matcher values: `startup`, `resume`, `clear`, `compact`, `fork`. On resume/fork the hook also receives `seconds_since_last_response`, `context_tokens`, `prompt_cache_likely_expired`, `estimated_cache_write_usd`.

`SessionEnd` `reason` values: `clear`, `resume`, `logout`, `prompt_input_exit`, `other`. Default timeout is **1.5 seconds** (override with `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`).

---

## 2. ccmanager (kbwo/ccmanager)

https://github.com/kbwo/ccmanager — TypeScript, 1,233 stars, 92 forks, last push 2026-09-02, not archived, created 2025-06-07. Now describes itself as "Coding Agent Session Manager for Claude Code / Gemini CLI / Codex CLI / Cursor Agent / Copilot CLI / Cline CLI / OpenCode / Kimi CLI".

**Spawn/attach mechanism.** No tmux. It runs each agent in its own PTY inside its own process, using **Bun's built-in `Bun.Terminal` API** (`src/services/bunTerminal.ts`), which replaced `@skitee3000/bun-pty` to avoid native library issues in compiled binaries. It sets `TERM` from the `name` option, calls `setRawMode(true)` by default (with an escape hatch for `devcontainer exec`, which manages termios itself), and clears the `ONLCR` output flag (`0x0002`) to avoid double CRLF translation. Output is buffered and flushed on an 8ms timer (`FLUSH_DELAY_MS`, "~2 frames at 60fps"), with special handling for **synchronised output** escape sequences `\x1b[?2026h` / `\x1b[?2026l` used by Ink: while in sync mode it buffers until the end sequence arrives or a 100ms `SYNC_TIMEOUT_MS` elapses, then emits the whole frame atomically. That detail matters: without it you tear frames and misread state.

Each session feeds its PTY output into a headless xterm (`@xterm/headless`) `Terminal` plus a `SerializeAddon` for restore. State detection reads the **visible viewport only**, never scrollback (`src/utils/screenCapture.ts` uses `buffer.baseY` and `terminal.rows`, and `line.translateToString(true, 0, cols)`).

**State detection: the actual regexes.** `src/services/stateDetector/claude.ts`. States are `'idle' | 'busy' | 'waiting_input' | 'pending_auto_approval'` (`src/types/index.ts`).

```typescript
const SPINNER_CHARS = '✱✲✳✴✵✶✷✸✹✺✻✼✽✾✿❀❁❂❃❇❈❉❊❋✢✣✤✥✦✧✨⊛⊕⊙◉◎◍⁂⁕※⍟☼★☆·•⏺▸▹∙⋅○●';
const SPINNER_ACTIVITY_PATTERN = new RegExp(`^[${SPINNER_CHARS}] \\S+ing.*\u2026`, 'm');
const TOKEN_STATS_LINE_PATTERN = /\([^)]*\d[^)]*tokens\s*\)/i;
export const IDLE_DEBOUNCE_MS = 1500;
```

The classification order in `detectState()` is precise and worth copying:

1. If the last 200 lines contain `'⌕ Search…'` → idle (debounced).
2. If the last 30 lines (lowercased, **including** the prompt box) contain `'ctrl+r to toggle'` → return current state unchanged.
3. `/(?:do you want|would you like).+\n+[\s\S]*?(?:yes|❯)/` → `waiting_input`.
4. Contains `'esc to cancel'` → `waiting_input`.
5. `/\d+\.\s*deny\s*\(esc\)/` → `waiting_input`. The comment notes this catches permission menus with no question phrasing, e.g. "Claude in Chrome wants to navigate on example.com" with `❯ 1. Allow` / `2. Deny (esc)`; the numbered "Deny (esc)" is "the stable marker across variants".
6. Then, **only on content above the prompt box**: `'esc to interrupt'` or `'ctrl+c to interrupt'` → `busy`.
7. `SPINNER_ACTIVITY_PATTERN` → `busy`.
8. `TOKEN_STATS_LINE_PATTERN` (e.g. `(9m 21s · ↓ 13.7k tokens)`) → `busy`.
9. Otherwise idle, debounced.

Two structural tricks make this work. `getContentAbovePromptBox()` walks lines bottom-up counting `/^─+$/` full-width border lines and cuts at the **second** one, isolating the chat area from the input box. `getRecentContentAbovePromptBox()` then trims trailing blanks, `❯`, and `/^[-─\s]+$/` lines, and walks back to the start of the last contiguous non-blank block. The reason, quoted from the source: *"Claude Code frequently redraws the lower pane using cursor-addressed updates. xterm's buffer can retain transient fragments from those redraws outside the latest visible content block, so busy detection should only inspect the most recent contiguous block directly above the prompt box."*

`debounceIdle()` hashes the last 30 lines of content and only returns `'idle'` once that content has been unchanged for `IDLE_DEBOUNCE_MS` (1500ms), with the stated rationale: *"Claude Code sometimes appears idle in terminal output while still actively processing (busy). To mitigate false idle transitions…"* This is the single most important lesson from the whole codebase: **screen-scraped idle is a lie without a stability window.**

Polling is `STATE_CHECK_INTERVAL_MS = 100` (`src/services/sessionManager.ts`), i.e. 10Hz per session, and each tick also runs `detectBackgroundTask()` and `detectTeamMembers()`.

`detectBackgroundTask()` inspects the **last 3 lines** only: `/(\d+)\s+(?:background\s+task|local\s+agent)/` for a count, else `'(running)'` → 1, else 0.

`detectTeamMembers()` also inspects the last 3 lines, finds the line containing `'shift+↑ to expand'` or `'shift+up to expand'`, and counts `/@[\w-]+/g` matches. This is a direct tell that Claude Code renders an agent-teams footer listing `@teammate` names.

Status display (`src/constants/statusIcons.ts`): `●` Busy, `◐` Waiting, `○` Idle, with dim-ANSI tags `\x1b[2m[BG]\x1b[0m`, `[BG:N]`, and `[Team:N]`.

**Teammate mode injection.** `src/utils/commandArgs.ts` is short and pointed:

```typescript
// Inject `--teammate-mode in-process` into args when running the `claude` command
// with the `claude` detection strategy. This prevents tmux conflicts when
// Claude Code's agent teams feature is used inside ccmanager's PTY-based sessions.
```

It appends `--teammate-mode in-process` when `command === 'claude'`, strategy is `claude`, and the user has not already passed `--teammate-mode`. Confirmation that native agent teams will try to grab tmux out from under any PTY-based manager.

**Status hooks (env-var based, not JSON).** `src/utils/hookExecutor.ts` spawns `sh -c` with:

`CCMANAGER_WORKTREE_PATH`, `CCMANAGER_WORKTREE_DIR` (basename), `CCMANAGER_WORKTREE_BRANCH`, `CCMANAGER_GIT_ROOT`, `CCMANAGER_OLD_STATE`, `CCMANAGER_NEW_STATE`, `CCMANAGER_SESSION_ID`, `CCMANAGER_PRESET_NAME`. Worktree hooks get `CCMANAGER_BASE_BRANCH`. Config lives under `statusHooks: { idle?, busy?, waiting_input?, pending_auto_approval? }`, each `{ command, enabled }`; also `worktreeHooks: { pre_creation?, post_creation? }`. Pre-creation hook errors **propagate and abort** worktree creation (deliberate, "NO Effect.catchAll"); everything else is caught and logged.

**Auto-approval (experimental).** `src/services/autoApprovalVerifier.ts`. When state is `waiting_input` and auto-approval is on, state becomes `pending_auto_approval`, and then: first a **hardcoded deterministic blocklist** of dangerous command regexes runs (mkfs, reboot/shutdown/halt/poweroff, eval with command substitution, container escape, and so on; git `push --force`/`reset --hard`/`clean -f` are deliberately excluded), described in-source as *"defense-in-depth layer that cannot be bypassed by prompt injection"*. Only if that passes does it shell out to `claude` with `--output-format json --json-schema '{"type":"object","properties":{"needsPermission":{"type":"boolean"},"reason":{"type":"string"}},"required":["needsPermission"]}'`, piping the terminal output on stdin. If the verdict is "no permission needed", it approves by writing `'\r'` to the PTY (`session.process.write('\r')`), i.e. pressing Enter on the highlighted default. A custom command can replace the LLM call, receiving the prompt via `DEFAULT_PROMPT` env var, and must emit the same JSON.

Other config keys (`ConfigurationData`): `shortcuts` (default `returnToMenu` Ctrl+E, `cancel` Escape), `commandPresets` (`{ id, name, command, args, fallbackArgs, detectionStrategy }` plus `defaultPresetId`, `selectPresetOnStart`), `worktree` (`autoDirectory`, `autoDirectoryPattern`, `copySessionData`, `sortByLastSession`, `autoUseDefaultBranch`, `includeRemoteBranches`), `mergeConfig`, `autoApproval` (`enabled`, `customCommand`, `timeout`). Env: `CCMANAGER_MULTI_PROJECT_ROOT` enables multi-project mode.

Claude directory handling (`src/utils/claudeDir.ts`): respects `CLAUDE_CONFIG_DIR`, else `~/.claude`; `pathToClaudeProjectName()` is `path.resolve(p).replace(/[/\\.]/g, '-')`, i.e. slashes, backslashes **and dots** all become dashes. Useful if you map worktrees to transcript directories yourself.

**What to steal:** the debounce-before-idle rule; the "only look above the prompt box, only the last contiguous block" rule; the `Deny (esc)` marker; the deterministic blocklist in front of any LLM auto-approver; the state-transition-hook env var contract.

---

## 3. cmux (manaflow-ai/cmux) — the most important new entrant

https://github.com/manaflow-ai/cmux — Swift, **26,777 stars**, 2,314 forks, created 2026-01-28, last push 2026-09-04. A Ghostty/libghostty-based native macOS terminal (AppKit, not Electron), GPL, reading your existing `~/.config/ghostty/config`.

**Why it matters to a WezTerm user:** it solves exactly your problem, and its `claude-teams` integration contains the single most stealable trick in this report.

**The tmux shim.** From https://cmux.com/docs/agent-integrations/claude-code-teams: `cmux claude-teams` creates a fake tmux binary at `~/.cmuxterm/claude-teams-bin/tmux` that redirects to `cmux __tmux-compat`, and **prepends that directory to PATH so Claude finds the shim first**. It then sets:

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- `TMUX` — a fake tmux socket path encoding the current cmux workspace and pane
- `TMUX_PANE` — a fake tmux pane identifier mapped to the current cmux pane
- `CMUX_SOCKET_PATH` — the cmux control socket

The shim translates tmux commands including `split-window`, `new-session` and `send-keys` into cmux socket API calls, so Claude Code's teammates spawn as **native cmux splits** with sidebar metadata and notifications, with no real tmux involved. Source lives in `CLI/CMUXCLI+TmuxCompat*.swift` (`TmuxCompatSupport`, `TmuxCompatStore`, `TmuxCompatResizePane`, `TmuxCompatLaunchContext`, `TmuxCompatHUDSupport`), and `CMUXCLI+TmuxCompatSupport.swift` contains a key-name translation table (`enter`/`c-m`/`kpenter`, `tab`/`c-i`, `space`, `bspace`/`backspace`, `escape`/`esc`/`c-[`, `c-c`, `c-d`, `c-z`, `c-l`, and directional `left`/`right`/`up`). There is even a `.github/workflows/tmux-corpus.yml` implying they test against a corpus of real tmux invocations.

**Agent state detection.** cmux installs hooks per agent via a generic `AgentHookDef` system (`CLI/CMUXCLI+AgentHookDefinitions.swift`, catalog in `CMUXCLI+AgentHookCatalog.swift`). The canonical mapping used across agents is:

- `SessionStart` → `session-start`
- `UserPromptSubmit` → `prompt-submit` (turn begins, i.e. busy)
- `Stop` → `stop` (turn ends, i.e. needs you)
- `Notification` → `notification` (needs input)
- `SessionEnd` → `session-end`

plus a set of `feedHookEvents` that install a `cmux hooks feed --source <name>` bridge, typically `PreToolUse` (for Codex: `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`). Notable design details in the source: a `HookDispatch` enum with `.ambient` versus `.pinned(marker:)` because *"agents that sanitize hook subprocess environments"* need the installing CLI and socket embedded in the command; a `sessionEndIsTurnBoundary` flag because some agents re-emit session-end after every turn (they cite issue #5000, where treating it as teardown destroyed the restore record after the first turn); PID-based hook authentication (`cmuxTests/ClaudeHookPIDAuthenticationTests.swift`); and a per-agent kill switch env var such as `CMUX_CODEX_HOOKS_DISABLED`.

**Event bus.** `~/.cmuxterm/events.jsonl` is an append-only newline-delimited JSON log, mirrored by a live socket stream. Clients send one line, `{"id":"client-1","method":"events.stream","params":{"after_seq":123,"categories":["notification","feed"]}}`, and then read frames. Every event has a process-local monotonic `seq` and a `boot_id`; reconnect with `after_seq` or `cmux events --cursor-file ~/.cache/cmux/events.seq --reconnect`, and `resume.gap: true` tells you your cursor is stale so you should re-snapshot via `list-workspaces` / `list-notifications` / `tree`. Event names include `notification.created`, `notification.read`, `notification.removed`, `notification.cleared`, and `agent.hook.<HookEventName>`. Heartbeats every 15s by default. Docs: https://github.com/manaflow-ai/cmux/blob/main/docs/events.md

The README's own motivation is telling: *"I was using Ghostty with a bunch of split panes, and relying on native macOS notifications to know when an agent needed me. But Claude Code's notification body i[s]…"* (truncated), and the design philosophy section says *"cmux is a primitive, not a solution."*

**What to steal:** the PATH-shim technique, wholesale. You can get Claude Code's native agent teams to spawn teammates into **WezTerm** panes by putting a `tmux` shim on PATH that implements `new-session`, `split-window`, `send-keys`, `display-message`, `list-panes` and `kill-pane` in terms of `wezterm cli split-pane`, `wezterm cli send-text`, `wezterm cli list --format json`, and `wezterm cli kill-pane`, plus setting `TMUX` and `TMUX_PANE` to plausible values so Claude Code believes it is inside tmux. Also steal the seq+boot_id resumable event log; it is a much better contract than tailing a file.

---

## 4. agent-view (Frayo44/agent-view) — the cleanest small template

https://github.com/Frayo44/agent-view — TypeScript/Bun, 368 stars, last push 2026-07-27. A tmux-based TUI session manager. Small enough to read in one sitting and the closest match to "bash scripts driving panes".

**Hook integration is the whole state mechanism** (`src/core/hooks.ts`), and the file header states the design rationale precisely:

> Agent-view maintains its own settings file (`~/.agent-view/hooks/claude-settings.json`) that is passed to claude via `--settings` at launch, the user's `~/.claude/settings.json` is never touched. The hooks invoke `notify.sh`, which fires a native OS notification and drops a signal file for the TUI. Delivery lives in the script (not the TUI) on purpose: the TUI event loop is frozen while attached to any session, and notifications must work even when the TUI isn't running at all.

The generated settings are just two events:

```json
{ "hooks": {
    "Stop":         [ { "hooks": [ { "type": "command", "command": "bash \"$HOME/.agent-view/hooks/notify.sh\" stop" } ] } ],
    "Notification": [ { "hooks": [ { "type": "command", "command": "bash \"$HOME/.agent-view/hooks/notify.sh\" notification" } ] } ]
} }
```

The generated `notify.sh` does four things worth copying verbatim:

1. `[ -z "$AGENT_ORCHESTRATOR_SESSION" ] && exit 0` — self-scoping, so the hook is inert in sessions the manager did not launch.
2. Reads a config toggle: `grep -q '"notifications"[[:space:]]*:[[:space:]]*false' "$CONFIG" && exit 0`.
3. **Suppresses the OS notification when you are already looking at the pane**: `tmux -L agent-view display-message -p -t "$TMUX_PANE" '#{session_attached}'`, and skips if non-zero.
4. Always writes a signal file regardless: `printf '{"event":"%s","sessionId":"%s","timestamp":%s}\n' ... > "$NOTIF_DIR/$AGENT_ORCHESTRATOR_SESSION.json"` under `~/.agent-view/notifications/`. That file powers the TUI's needs-attention glyph.

For the `notification` event it extracts the message with `sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'`. For `stop` it hardcodes "Finished — waiting for you". Files are written with `mode 0o600`/`0o700` and only when content changed.

tmux driving (`src/core/tmux.ts`) uses a **private socket and config**: `tmux -L ${TMUX_SOCKET} -f "${CONFIG_PATH}" ${subcmd}`, so it never touches your default server. Commands used: `new-session -d -s "<name>" -c "<cwd>"`, `send-keys -t <name> -l <keys>` then a separate `send-keys -t <name> Enter`, `capture-pane -t <name> -p`, `display-message -t <name> -p "#{pane_width}\t#{pane_height}"`, `list-windows -a -F "#{session_name}\t#{window_activity}"`, `list-panes -a -F "#{session_name} #{pane_pid}"`, `list-sessions -F #{session_name}`. Note it sends `unset CLAUDECODE` into the pane before launching, to stop Claude Code detecting itself as nested.

**What to steal:** all of it. The `--settings` sidecar pattern (never mutate the user's settings.json), the self-scoping env-var guard, the "am I being watched" suppression check, and the atomic per-session signal file. For WezTerm the attached check becomes `wezterm cli list --format json` and comparing the focused pane ID.

Also in this space: **agent-deck** (https://github.com/asheshgoplani/agent-deck, Go, 834 stars, pushed 2026-09-02), a multi-agent TUI with `internal/fleet/detect.go`, `cmd/agent-deck/status_stale.go` and per-agent detectors (`copilot_detect_test.go`, `crush_detect_test.go`, `hermes_detect_test.go`), advertising smart polling and waiting-session display in the tmux status bar. And **Claude-Code-Agent-Monitor** (https://github.com/hoangsonww/Claude-Code-Agent-Monitor, TypeScript, 971 stars, pushed 2026-09-03), a SQLite + Express + React + WebSocket dashboard with a Kanban status board.

---

## 5. happy (slopus/happy) — the cleverest state detection in the cluster

https://github.com/slopus/happy — TypeScript, 23,634 stars, 1,995 forks, last push 2026-09-03. "Mobile and Web client for Codex and Claude Code, with realtime voice, encryption". Installed as `npm install -g happy`, used as `happy claude` instead of `claude`. Components: happy-cli, happy-app (Expo web + mobile), happy-agent ("Remote agent control CLI (create, send, monitor sessions)"), happy-server, plus a separate native macOS app at slopus/happy-desktop.

**How it attaches.** Not by scraping, and not by tmux. Two paths:

*Local mode* (`packages/happy-cli/src/claude/claudeLocal.ts`) spawns a **launcher shim**, `scripts/claude_local_launcher.cjs`, via `cross-spawn` on `node`, with an extra stdio fd. The launcher monkey-patches `global.fetch` before requiring the real Claude CLI:

```javascript
function writeMessage(message) { try { fs.writeSync(3, JSON.stringify(message) + '\n'); } catch (err) {} }
const originalFetch = global.fetch;
let fetchCounter = 0;
global.fetch = function(...args) {
    const id = ++fetchCounter;
    // ...parse hostname/path for privacy...
    writeMessage({ type: 'fetch-start', id, hostname, path, method, timestamp: Date.now() });
    const fetchPromise = originalFetch(...args);
    const sendEnd = () => writeMessage({ type: 'fetch-end', id, timestamp: Date.now() });
    fetchPromise.then(sendEnd, sendEnd);
    return fetchPromise;
};
// preserves fetch.name and fetch.length, then:
const { getClaudeCliPath, runClaudeCli } = require('./claude_version_utils.cjs');
runClaudeCli(getClaudeCliPath());
```

The parent reads **fd 3** with a readline interface, keeps `activeFetches: Map<number, {hostname, path, startTime}>`, sets thinking `true` on `fetch-start`, and on `fetch-end` schedules `updateThinking(false)` after a **500ms** debounce only if `activeFetches.size === 0` (comment: `// Small delay to avoid flickering`). It also sets `DISABLE_AUTOUPDATER=1`.

This is a fundamentally better signal than screen-scraping: "busy" means "there is an in-flight HTTP request to the model", which is ground truth, not a rendering artefact. The cost is that it only works if you control the launch and the agent is a Node program.

*Session identity* comes from hooks, not file watching. `packages/happy-cli/src/claude/utils/startHookServer.ts` starts an HTTP server on a random port, and `generateHookSettings.ts` writes `~/.happy/tmp/hooks/session-hook-<pid>.json`:

```json
{ "hooks": { "SessionStart": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "node \"<forwarderScript>\" <port>" } ] } ] } }
```

which is passed as `claude --settings <path>`. The forwarder (`scripts/session_hook_forwarder.cjs`) reads the hook JSON on stdin and POSTs it to `http://127.0.0.1:<port>/hook/session-start`. The server accepts `session_id` or `sessionId`, with a 5-second request timeout, and calls `onSessionHook(sessionId, data)` which updates the session ID, API metadata and the session scanner. The header comment states the reason explicitly:

> **Why Not Use File Watching?** File watching has race conditions when multiple Happy processes run. With hooks, Claude directly tells THIS specific process about its session, ensuring 1:1 mapping between Happy process and Claude session.

That is the correct answer to "how do I know which pane owns which session ID" when running many concurrent sessions, and it is the exact problem you have.

It handles `--continue` / `--resume` / `--resume <id>` / `--session-id <uuid>` by intercepting them from `claudeArgs` and substituting happy's own session storage. A separate `sessionScanner.ts` tails `~/.claude/projects/<encoded-cwd>/*.jsonl` with a file watcher for message content, and skips internal event types `file-history-snapshot`, `change`, `queue-operation` (useful list: those are non-message entries in the transcript). It defends against "phantom session ids whose .jsonl is never written" with a `deadSessions` set and a 60s missing-file timeout, described in-source as "the dead Happy instance bug".

*Remote mode* uses the SDK path (`packages/happy-cli/src/claude/sdk/query.ts`, `claudeRemote.ts`). The README describes it as: run `happy` instead of `claude`, and when you want to control it from your phone "it restarts the session in remote-control mode".

**What to steal:** the fd-3 sidecar channel for out-of-band structured status from a wrapped process; the SessionStart-hook-to-localhost-HTTP handshake for 1:1 pane-to-session-ID binding; the 500ms anti-flicker debounce on the busy→idle edge.

---

## 6. claude-code-templates / aitmpl (davila7/claude-code-templates)

https://github.com/davila7/claude-code-templates — 30,525 stars, 3,457 forks, last push 2026-09-04, https://aitmpl.com. Primarily a component installer (`--agent`, `--command`, `--setting`, `--hook`, `--mcp`, `--skill`, `--plugin`), but it ships the best-known "Claude Code dashboard": `npx claude-code-templates@latest --analytics`, plus `--chats` (mobile conversation monitor, `--chats --tunnel` via Cloudflare Tunnel), `--health-check`, and `--plugins`.

**State detection: include this as the anti-pattern.** `cli-tool/src/analytics/core/ProcessDetector.js` shells out to:

```
ps aux | grep -i claude | grep -v grep | grep -v analytics | grep -v "/Applications/Claude.app" | grep -v "npm start" | grep -v chats-mobile
```

and tries to recover cwd with `fullCommand.match(/--cwd[=\s]+([^\s]+)/)`. Matching a process to a conversation is `process.workingDir.includes(conversation.project) || process.command.includes(conversation.project)`, with a fallback that if `workingDir === 'unknown'` it just picks the most recently modified conversation.

`cli-tool/src/analytics/core/StateCalculator.js` then classifies purely on **timestamps**: JSONL file mtime plus last message role and age. `detectRealClaudeActivity()` returns `'Claude Code working...'` if file mtime is under 1 minute; `'Claude Code working...'` if the last message is a user message under 5 minutes old and the file changed under 10 minutes ago; `'Claude Code finishing...'` if the last message is an assistant message under 2 minutes old. Then a cascade of thresholds producing string states `'Claude Code working...'`, `'Awaiting response...'`, `'Awaiting user input...'`, `'User typing...'`, `'Recently active'`, `'Active session'`, `'Idle'`, `'Inactive'`, `'Waiting for input...'`. Comments in the source literally say "be more generous about active state".

This cannot distinguish "waiting on a permission prompt" from "waiting on you to type", it cannot see background tasks, and it mis-attributes when two sessions share a directory. Do not build on it. It is a useful demonstration of why the hook-based approach won.

Also here: `FileWatcher.js`, `ConversationAnalyzer.js`, `SessionAnalyzer.js`, `AgentAnalyzer.js`, `NotificationManager.js`, `WebSocketServer.js` (the dashboard pushes over WebSocket).

---

## 7. ccusage (ccusage/ccusage) — read this for the transcript schema

**Note the moves:** the repo is now `ccusage/ccusage` (was `ryoppippi/ccusage`) and **has been rewritten in Rust**. 18,355 stars, 818 forks, last push 2026-09-04, https://ccusage.com. Root README is a one-line pointer to `./apps/ccusage/README.md`.

It now reads 18 agent CLIs, not just Claude Code: `ccusage claude|codex|opencode|amp|droid|codebuff|hermes|pi|goose|openclaw|kilo|kimi|qwen|copilot|gemini|antigravity|grok|zcode daily`. Commands: `daily`, `weekly`, `monthly`, `session`, `blocks` (Claude's 5-hour billing windows), `statusline` (Beta, for the Claude Code status bar). Flags: `--json`, `--breakdown`, `--since`/`--until`, `--last N`, `--instances`, `--project`, `--by-agent`, `--sections`, `--compact`, `--offline`, `--timezone`, `--no-cost`.

**Path resolution** (`rust/adapters/claude/src/paths.rs`, verbatim logic): if `CLAUDE_CONFIG_DIR` is set, split on `,` (multiple dirs supported), expand `~`, and if a path ends in `projects` use its parent; each candidate must contain a `projects/` directory or the whole thing errors. Otherwise try `$XDG_CONFIG_HOME/claude` (defaulting to `~/.config/claude`) **and** `~/.claude`, keeping whichever contain `projects/`. Then glob `projects/**` for usage files. That `XDG_CONFIG_HOME/claude` fallback is not in the official docs and is worth knowing.

**Transcript JSONL fields it depends on** (`rust/adapters/claude/src/lib.rs`): it fast-scans each line for the literal `"usage":{` before parsing at all, then deserialises a `UsageEntry` with `timestamp`, `sessionId`, `requestId`, `isSidechain`, `cwd`, `version`, `costUSD`, `isApiErrorMessage`, and `message.{id, model, usage.{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}}`. Deduplication is by `(message.id, requestId, sessionId)`, with a sidechain variant keyed on `(message.id, sessionId, timestamp)`. The session ID is derived from the **filename** and the project from the parent directory name. There is also newer handling for `message.usage.iterations[]` (each with `type`, `model` and flattened token fields) and for `"advisor_message"` lines, i.e. the `--advisor <model>` feature contributes its own usage rows. It scans for the marker string `"Claude AI usage limit reached"` to detect limit events.

**What to steal:** the `"usage":{` prefilter (huge speedup on large transcripts), the exact dedupe key (messages genuinely repeat across resumed/forked transcripts), and the path resolution including the XDG fallback and comma-separated `CLAUDE_CONFIG_DIR`.

---

## 8. Claude-Code-Usage-Monitor (Maciek-roboblog)

https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor — Python, 8,674 stars, 458 forks, **last push 2026-07-05**, so it is the least actively maintained item in this cluster but not archived. Installed as `claude-monitor`.

Multi-source input via `--data-paths`, `CLAUDE_CONFIG_DIR`, and WSL discovery, explicitly "without merging unrelated accounts into one". Plans: `pro`, `max5`, `max20`, `team`, `custom` (default), where custom does P90-based auto-detection over the last 192 hours (8 days). Views via `--view`: `realtime`, `daily`, `monthly`, `session`, `entries`, `sessions`, `burn-rate`.

Two features are directly relevant to a scripted multi-pane setup:

- `--title-format` with template variables, default `"{pct}% {plan}"`, supporting `pct`, `plan`, `used`, `limit`, `cost`, `reset`. It writes the **terminal title**, which in WezTerm gives you per-tab quota display for free.
- `claude-monitor --write-state --state-file ~/.claude-monitor/state/latest.json` — a machine-readable state dump you can poll from bash rather than scraping the TUI. Also `--warehouse --view entries --output json` and `--output csv`.

Config persists at `~/.claude-monitor/last_used.json`. Its own README notes for the `team` plan: "prefer official statusline or `--plan custom`".

---

## 9. claude-flow → **ruvnet/ruflo**

**The repo has been renamed.** `github.com/ruvnet/claude-flow` now redirects to https://github.com/ruvnet/ruflo, branded "Ruflo", 70,424 stars, 8,392 forks, last push 2026-09-03, 903 open issues, homepage Cognitum.One. Description: "The original agent meta-harness. Deploy intelligent multi-player swarms…".

Two install paths: Claude Code plugins (`/plugin marketplace add`, `/plugin install ruflo-swarm@ruflo`, etc, giving slash commands and agent definitions only) or the full CLI (`npx ruflo@latest init wizard`), which the README says gives "98 agents, 60+ commands, 30 skills, MCP server, hooks, daemon". MCP registration is the documented `claude mcp add claude-flow -- npx ruflo@latest mcp start`. Marketing claims ~210-314 MCP tools, HNSW vector memory, SONA self-learning, Queen-led hierarchy with Raft/Byzantine/Gossip consensus, and an agent "federation" layer over WebSocket with WireGuard mesh (`npx claude-flow@latest federation init|join|send|status`).

The README is almost entirely marketing, so the honest mechanism is in the hook manifests. `plugins/ruflo-core/hooks/hooks.json` registers `PreToolUse` (matchers `Bash` and `Write|Edit|MultiEdit`), `PostToolUse` (same matchers), and `PreCompact` (matchers `manual` and `auto`). Every command is a cross-platform Node bootstrap:

```
node -e "process.argv=[process.argv[0],'x','modify-bash'];require(require('path').join(process.env.CLAUDE_PLUGIN_ROOT,'scripts','ruflo-hook.cjs'))"
```

The manifest's own `description` field is unusually candid and is itself a lesson: the shim *"prefers a locally-installed `ruflo`/`claude-flow` binary, falls back to `npx --prefer-offline`, and always exits 0 so a CLI/install failure never surfaces an error or blocks a turn"*, and it resolves `CLAUDE_PLUGIN_ROOT` **inside Node** rather than via shell `${VAR}`/`%VAR%` expansion so the identical command string works on Windows, macOS and Linux with "no bash, sh, cmd.exe, jq, or .sh scripts involved". The legacy POSIX manifest at `.claude-plugin/hooks/hooks.json` shows the older, worse approach it replaced, and is annotated `"_legacy_unaudited_shim": true` with `"_platform": "posix"`:

```
cat | jq -r '.tool_input.command // empty' | tr '\n' '\0' | xargs -0 -I {} "${CLAUDE_PLUGIN_ROOT}/scripts/ruflo-hook.sh" post-command --command '{}' --track-metrics true --store-results true || true
```

**What to steal:** the always-exit-0 discipline for non-gating hooks (a broken hook must never block a turn), and `CLAUDE_PLUGIN_ROOT`. What to be sceptical of: the accuracy percentages and agent counts are unverifiable, and 903 open issues on a 70k-star repo is a maintenance signal.

---

## 10. SuperClaude (SuperClaude-Org/SuperClaude_Framework)

https://github.com/SuperClaude-Org/SuperClaude_Framework — Python, 23,867 stars, 2,008 forks, default branch **`master`**, last push 2026-08-21. Current stable v4.3.0, with v5.0 "in development" and explicitly marked not yet available.

`pipx install superclaude` then `superclaude install`, which installs 30 `/sc:*` slash commands (`/sc:research`, `/sc` to list all), 15-ish agents, behavioural "modes", and optionally MCP servers via `superclaude mcp --list` (Serena, Sequential, Tavily, Context7, via airis-mcp-gateway). It self-describes as *"a meta-programming configuration framework that transforms Claude Code into a structured development platform through behavioral instruction injection"*.

For your purposes: **there is no orchestration mechanism, no state detection, no process management, and no multiplexer integration.** It writes markdown command and agent files into `~/.claude/`. Its claims of "2-3x faster" and "30-50% fewer tokens" are attributed to the optional MCP servers, not to the framework. Nothing here to steal for pane driving; it is a prompt library with an installer.

---

## 11. claude-code-router (musistudio/claude-code-router)

https://github.com/musistudio/claude-code-router — TypeScript, 37,068 stars, 3,116 forks, last push 2026-09-02, **1,110 open issues**, homepage https://ccrdesk.top. Repositioned in 2026 from "route Claude Code to other models" to "One local control plane for every AI agent".

Mechanism: a local model gateway on **`http://127.0.0.1:3456`** which agent CLIs point at, plus a UI on `http://127.0.0.1:3458` (`ccr ui`). It fronts Claude Code, Claude Design, Codex, Grok CLI, Kimi CLI, Kilo Code, OpenCode, Pi, ZCode and WorkBuddy, and speaks OpenAI Chat/Responses, Anthropic Messages, Gemini Generate Content, OpenRouter, DeepSeek, SiliconFlow, Moonshot, Kimi Code, Mistral and Z.AI. Features: routing conditions on headers and bodies, prefixes, rewrites, retries, ordered fallbacks, credential pools, per-client keys with request/token/image limits, and an observability view showing resolved provider/model/credential, status, latency, tokens, estimated cost, tool calls and agent traces. Desktop app and Docker distributions exist.

Relevance to state detection: **indirect but real.** Because it sits in the request path, its request log is a ground-truth busy signal for every pane at once, the same insight happy gets from patching `fetch`, but obtained without wrapping each process. If you already want cost/latency observability across many panes, this is the cheapest place to get "which sessions are mid-request". It does not manage sessions or panes.

Caveat: 1,110 open issues, and the docs have largely moved off GitHub to ccrdesk.top.

---

## 12. omnara (omnara-ai/omnara) — has left this cluster

https://github.com/omnara-ai/omnara — 2,815 stars, last push 2026-09-04, **now written in Go**, Apache 2.0, description "The open-source alternative to Claude Managed Agents".

It has **pivoted away from being a Claude Code wrapper.** The 2026 README describes a general managed-agent platform: YAML agent profiles (`instruction`, `model.provider_config`, `model.name`), `npx omnara login`, `npx omnara profiles create --name agent --file agent.yaml`, `npx omnara agents launch --profile $AGENT_PROFILE_ID`, agent state committed atomically to Postgres, sandboxes from Blaxel/Daytona/Unikraft, bring-your-own model keys through OpenRouter/LiteLLM/Ollama, RBAC, Slack connector, and self-hosting via `docker compose --profile app up -d` on port 8000.

I checked the file tree (1,846 blobs) for Claude-specific wrapper code and found none: no `claude` wrapper module, only provider-agnostic `internal/machinedaemon/process_pty_unix.go` and `process_pty_windows.go` for running processes in a PTY on a connected machine. If you remembered omnara as "the thing that gives Claude Code a mobile UI via an MCP server and a webhook", that product no longer exists in this repo. For mobile control of Claude Code in 2026 the live options are **happy** and Anthropic's own Remote Control (https://code.claude.com/docs/en/remote-control.md) and mobile app.

---

## 13. Smaller tools worth a line each

- **ccstatusline** (https://github.com/sirmalloc/ccstatusline) — TypeScript, **12,764 stars**, pushed 2026-09-03. Highly customisable Claude Code statusline with powerline support and themes. The largest statusline project; consumes the `statusLine` stdin JSON documented in §1.11. Good source if you want per-pane context/cost display without writing your own renderer.
- **cchistory** (https://github.com/eckardt/cchistory) — TypeScript, 137 stars, pushed 2026-06-10. "Like the shell history command but for your Claude Code sessions." Small, still maintained, reads the JSONL transcripts.
- **claude-session-dashboard** (https://github.com/dlupiak/claude-session-dashboard) — local observability over `~/.claude`, nothing sent anywhere.
- **claude-code-cli-ui** (https://github.com/Ngxba/claude-code-cli-ui), **hex/claude-sessions**, **agents-ui** (Nuxt 3 GUI over the `~/.claude` directory) — smaller dashboards in the same shape.
- **wmux** (https://github.com/amirlehmam/wmux) — "The original Windows terminal multiplexer for AI agents", the Windows analogue of cmux.
- **dmux** and **herdr** — a worktree-plus-tmux agent multiplexer and a durable background agent runtime respectively, both catalogued in the 2026 landscape guide at https://amux.io/guides/best-ai-agent-multiplexers-2026/.
- **awesome-agent-orchestrators** (https://github.com/andyrewlee/awesome-agent-orchestrators) — the current curated list, useful for tracking new entrants.

---

## 14. What you should actually steal, concretely

You are running many concurrent Claude Code CLI sessions in WezTerm panes driven by custom bash scripts. Ranked by value.

**1. Stop scraping. Install a `--settings` sidecar with hooks.** Copy agent-view's pattern exactly. Write `~/.myrig/hooks/claude-settings.json` and launch every pane as `claude --settings ~/.myrig/hooks/claude-settings.json ...`, so your own `~/.claude/settings.json` stays clean and the hooks are inert outside your rig. Register at minimum:

- `SessionStart` → record `session_id`, `transcript_path`, `cwd`, `source` against the pane, and return `hookSpecificOutput.sessionTitle` to auto-name the session from the branch or worktree
- `UserPromptSubmit` → mark pane busy
- `Stop` → mark pane idle **but check `background_tasks` first**: non-empty means parked, not done. Use `last_assistant_message` for the summary rather than parsing JSONL.
- `StopFailure` → mark pane failed, with `error` giving you `rate_limit` versus `overloaded` versus `authentication_failed`
- `Notification` with matcher `permission_prompt` → mark pane blocked-on-permission; matcher `idle_prompt` → confirm idle
- `PermissionRequest` → if you want the blocked signal **immediately** rather than after the ~6 second away-gate
- `SessionEnd` → clean up the pane record
- `TeammateIdle` → if you enable agent teams

Guard every script with `[ -z "$MYRIG_SESSION" ] && exit 0`, always `exit 0` unless you genuinely intend to block, and write a per-session signal file atomically. Remember `SessionEnd` has a **1.5 second** default timeout.

**2. Bind pane ID to session ID at SessionStart.** This is the problem you will hit hardest with many panes, and happy already solved it: the hook fires **in the process you launched**, so it can tell you unambiguously which session ID belongs to which pane. Export `MYRIG_PANE=$WEZTERM_PANE` when you spawn, and have the SessionStart hook write `{"pane": "$MYRIG_PANE", "session_id": ..., "transcript_path": ...}`. Do not try to infer this from `ps` or file mtimes, which is where claude-code-templates falls over.

**3. Use `claude agents --json` as your source of truth where you can.** It gives you `state` (`working`/`blocked`/`done`/`failed`/`stopped`), `waitingFor` (`permission prompt` / `input needed` / `sandbox request`), `pid`, `sessionId`, `cwd` and `startedAt` in one call, with no parsing risk. Combine it with your hook signals: hooks give you edges, `agents --json` gives you level. Also copy its model of keeping **task state and process liveness as two separate axes**.

**4. Push into running sessions over the inbox socket instead of `send-keys`.** `CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN` are exported to your hooks and Bash commands. A bash script can connect and write one line to hand a running session new instructions, and the receiving Claude picks it up between tool calls without interrupting a running tool. That is strictly better than `wezterm cli send-text`, which races against the TUI's input handling. Send `{"type":"auth","token":"..."}` first, open the connection only when the payload is ready, and finish within 30 seconds.

**5. Notify through `terminalSequence`, not `/dev/tty`.** Hooks have no controlling terminal, so direct writes fail. Return `{"terminalSequence": "\033]9;Claude needs you\007"}` and let Claude Code emit it. OSC 9 is explicitly documented as working for WezTerm, and `9;4` gives you taskbar progress. Suppress it when the pane is already focused, the way agent-view checks `#{session_attached}`; for you that is `wezterm cli list --format json` and a focused-pane comparison.

**6. Get native agent teams into WezTerm panes with a tmux shim.** This is cmux's trick and it is portable. Put a directory first on `PATH` containing an executable named `tmux` that translates `new-session`, `split-window`, `send-keys`, `display-message`, `list-panes` and `kill-pane` into `wezterm cli` calls; set `TMUX` to a plausible fake socket path and `TMUX_PANE` to a mapped identifier; set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and launch with `--teammate-mode tmux`. Claude Code will then spawn teammates as real WezTerm panes. Steal cmux's key-name table (`enter`/`c-m`/`kpenter`, `c-c`, `escape`/`esc`/`c-[`, etc) for `send-keys` translation. If you would rather not, the fallback is ccmanager's: force `--teammate-mode in-process` so teams never touch tmux at all.

**7. If you must screen-scrape as a backstop, copy ccmanager's rules, not its regexes alone.** The regexes will rot; the structural rules will not. Specifically: read only the visible viewport, never scrollback; isolate content above the prompt box by counting `/^─+$/` borders bottom-up; look only at the last contiguous non-blank block for busy markers; and **never report idle until the content hash has been stable for ~1.5 seconds**. The `esc to interrupt` / `ctrl+c to interrupt` strings and the `/\d+\.\s*deny\s*\(esc\)/` permission marker are the two most durable signals.

**8. For a true busy signal, prefer request-level truth.** Either happy's fd-3 `fetch` interception (if you are willing to launch via a Node shim) or claude-code-router's gateway log (if you are already routing). "Is there an in-flight request" beats any rendering heuristic. If you use stream-json anywhere, the 30-second `tool_progress` heartbeat with `heartbeat: true` is a free liveness beat, and `background_tasks_changed` gives you the full current task set.

**9. Set the right env vars in your spawn script.** `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` if your scripts launch Claude from inside Claude (otherwise transcripts and `claude agents` registration silently vanish); `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` with `CLAUDE_CODE_RESUME_PROMPT` for unattended restart; `CLAUDE_CODE_RETRY_WATCHDOG=1` for panes you do not babysit; `CLAUDE_CODE_TASK_LIST_ID` to share one task list across panes; and `unset CLAUDECODE` before nesting, as agent-view does.

**10. Parse transcripts only as a last resort, and do it ccusage's way.** The docs warn the JSONL format is internal and can break on any release. If you must, prefilter lines for the literal `"usage":{`, dedupe on `(message.id, requestId, sessionId)`, skip the internal entry types `file-history-snapshot`, `change` and `queue-operation`, and resolve paths as `CLAUDE_CONFIG_DIR` (comma-separated) → `$XDG_CONFIG_HOME/claude` → `~/.claude`, then `projects/<cwd with non-alphanumerics replaced by ->/<session-id>.jsonl`.

