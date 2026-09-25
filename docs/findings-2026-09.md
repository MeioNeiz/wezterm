# What is out there, September 2026

A survey of agent-control tooling, done because this rig was built against the 2025
picture and most of that picture has changed. Raw agent reports are in `research/`;
this is the distillation.

Three things frame everything below:

- **Claude Code absorbed most of what the third-party session managers existed to do.**
  `claude agents --json`, native worktrees, a per-session message socket, agent teams.
  Several of our scripts now derive by hand what one command returns.
- **The GUI orchestrator category is collapsing.** Crystal deprecated Feb 2026 (now
  Nimbalyst), Vibe Kanban sunsetting, Terragon and Overstory gone. The terminal layer is
  where the work is: herdr 35k stars, cmux 27k, workmux 2.4k.
- **Nothing in the ecosystem is a wezterm fleet controller.** Everything is tmux, Zellij,
  or a desktop GUI. The closest cousins are `sverrirsig/claude-control` (same design,
  process-table discovery plus hooks) and the small wezterm plugins in section 5.

---

## 1. Claude Code's own surfaces

### 1.1 Hooks: 33 events, we use 5

`SessionStart` `Setup` `UserPromptSubmit` `UserPromptExpansion` `PreToolUse`
`PermissionRequest` `PermissionDenied` `PostToolUse` `PostToolUseFailure` `PostToolBatch`
`Notification` `MessageDisplay` `SubagentStart` `SubagentStop` `TaskCreated`
`TaskCompleted` `Stop` `StopFailure` `TeammateIdle` `InstructionsLoaded` `ConfigChange`
`CwdChanged` `DirectoryAdded` `FileChanged` `WorktreeCreate` `WorktreeRemove` `PreCompact`
`PostCompact` `PreModelSwitch` `PostModelSwitch` `Elicitation` `ElicitationResult`
`SessionEnd`

Common stdin: `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`,
`effort.level`, `hook_event_name`, plus `agent_id`/`agent_type` inside a subagent.

`prompt_id` is the join key across hook stdin, the statusLine JSON and OTEL's `prompt.id`.
It is the only identifier that ties a keystroke to its hook events, its status renders and
its telemetry. Nothing here uses it.

**Five handler types, not just `command`:** `command`, `http` (POST, same JSON body),
`mcp_tool`, `prompt` (single-turn LLM eval), `agent` (spawns a subagent to decide).
Handler fields: `if` (a permission rule like `"Bash(git *)"`), `timeout`, `statusMessage`,
`once`, `async`, `asyncRewake`, `args` (exec form, no shell), `shell`.

`asyncRewake: true` runs the hook in the background and **wakes Claude on exit 2**,
delivering stderr as a system reminder. A supported poke-a-running-agent channel.

**Timeouts:** 600s default, 30s on SessionStart and the model-switch pair, 10s on
MessageDisplay, and **SessionEnd hooks share a 1.5s budget** unless one sets a longer
`timeout` (max 60s) or `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` is raised.

**Matcher semantics changed at v2.1.195.** Matchers of only letters, digits, `_`, `-`,
spaces, `,`, `|` are exact string or list; anything else is an unanchored regex.
Hyphenated MCP servers need `mcp__brave-search__.*`. `SessionEnd` reason
`bypass_permissions_disabled` was removed in v2.1.234.

### 1.2 The three state events, with real payloads

**`Stop`** carries far more than we read:

```json
{ "hook_event_name": "Stop", "stop_hook_active": true,
  "last_assistant_message": "I've completed the refactoring...",
  "background_tasks": [ { "id": "task-001", "type": "shell", "status": "running",
                          "description": "tail logs", "command": "tail -f ..." } ],
  "session_crons": [ { "id": "cron-001", "schedule": "0 9 * * 1-5",
                       "recurring": true, "prompt": "check the build" } ] }
```

`background_tasks[].type` is `shell`, `subagent`, `monitor`, `workflow`, `teammate`,
`cloud session` or `MCP task`. This array is how you tell **done** from **parked waiting
for background work to wake it**. With fork mode default since v2.1.232 and subagents
backgrounded by default since v2.1.198, a session with live children looks exactly like an
idle one. `stop_hook_active` is the loop guard.

Use `last_assistant_message` rather than tailing the transcript: **the transcript is
written asynchronously and lags at Stop time.** Warp's plugin sleeps 0.3s before reading
it for exactly this reason.

**`StopFailure`** fires when a turn dies on an API error, and **`Stop` does not fire in
that case**. Field is `error` (one report said `error_type`; treat both as possible),
values `rate_limit`, `overloaded`, `authentication_failed`, `oauth_org_not_allowed`,
`account_on_hold`, `billing_error`, `invalid_request`, `model_not_found`, `server_error`,
`max_output_tokens`, `unknown`. Plus `error_details` and `last_assistant_message` (the
rendered error text). No matcher. Output and exit code are ignored **except**
`terminalSequence`.

**`Notification`** matchers are the state machine: `permission_prompt`, `idle_prompt`,
`agent_needs_input`, `agent_completed`, `elicitation_dialog`, `elicitation_url_dialog`,
`elicitation_complete`, `elicitation_response`, `auth_success`, `quota_auto_resume_fired`,
`quota_auto_resume_stale`, `quota_auto_resume_disabled`.

Timing caveat that matters: `permission_prompt` is gated on you appearing to be away. It
waits ~6s and **every keystroke defers it**; `idle_prompt` waits ~60s. For an instant
blocked signal use `PermissionRequest`. And `agent_needs_input`/`agent_completed` fire
**only while agent view is open in a terminal**, so do not build on them.

### 1.3 `terminalSequence`, and why the OSC work here was a dead end

Hooks run **without a controlling terminal** on macOS and Linux, so writing escapes to
`/dev/tty` fails. Return `{"terminalSequence": "..."}` and Claude Code emits it through its
own terminal write path, race-free. Works even on `Notification` and `StopFailure` where
`systemMessage` and `continue` are discarded. Ignored in `-p` mode and the SDK.

**Allowlist:** OSC `0`/`1`/`2` (titles), OSC `9` (documented as working for wezterm,
including `9;4` taskbar progress), OSC `99` (Kitty), OSC `777`, and bare BEL. Everything
else is rejected and the whole field ignored.

So: **OSC 1337 SetUserVar is not on the allowlist**, which is a second, independent reason
the `SetUserVar` bridge was never going to work here on top of the one already measured in
CLAUDE.md (this wezterm build does not implement the sequence). Two agents independently
recommended `SetUserVar` as the spine of the design. Both were wrong for this machine.
The file-drained action queue stays. OSC 9 via `terminalSequence` is the supported path
for toasts, and needs no tty.

Version gate, from `warpdotdev/claude-code-warp`: `terminalSequence` needs 2.1.141+, and
emitting the unknown field to a `Stop` hook on an older build **fails validation** with
`Stop hook error: JSON validation failed`. Not optional.

### 1.4 `claude agents --json`

Verified on this machine: returns interactive sessions too, not just background ones.

| field | when | meaning |
|---|---|---|
| `cwd`, `kind`, `startedAt` | always | `interactive` or `background`, epoch ms |
| `id` | background | short id for attach/logs/stop |
| `state` | background | `working` `blocked` `done` `failed` `stopped` |
| `pid`, `status` | while alive | |
| `waitingFor` | when waiting | `permission prompt` `input needed` `sandbox request` `worker request` `dialog open` |
| `sessionId`, `name` | when set | full uuid, usable with `--resume` |

`--all` includes completed background sessions, `--cwd <path>` scopes it.

**`waitingFor` is finer than anything we derive.** Our `asking` vs `waiting` split cannot
tell a permission prompt from an open dialog from a sandbox request.

Measured afterwards, and it changes what this command is for rather than dismissing it:
**`--json` is a union of two things on disk.** For interactive sessions it is the registry
and nothing else. Three back-to-back runs, 38 rows against 38 registry files, byte-identical
on `status`, `waitingFor`, `name`, `cwd` and `pid`, at 120-180ms for the CLI against
under 10ms for one jq over the files; and `waitingFor` is itself a registry field, which
`cc-roster` has been reading into `detail` all along (`bin/cc-roster:52`).

For background sessions it is `~/.claude/jobs/<id>/state.json`, and **those have no registry
file at all.** Verified with `claude --bg --exec`: a row in `--json`, a state file under
`jobs/`, nothing in `sessions/`. That file carries more than the CLI exposes - `state`, plus
`detail`, which is the job's own last line of output (`starting`, then `done`), `tempo`,
`children`, `template`, `respawnFlags` and `resumeSessionId`. So the interesting gap is not
`waitingFor`, which we have: it is that nothing here sees background sessions at all.

The UI model worth copying: state (`Working`/`Needs input`/`Idle`/`Completed`/`Failed`/
`Stopped`) and **process liveness are two separate axes**. `✻`/`✽` process alive, `∙`
exited but resumable, `✢` a `/loop` session sleeping between iterations. Most third-party
tools conflate the two. So do we.

Shell surface: `claude attach|logs|stop|respawn|rm <id>`, `claude respawn --all` (restart
every session onto a new binary), `claude daemon status|stop`.

Registry note: `~/.claude/sessions/<pid>.json` is documented only as "used to detect
concurrent sessions and crashes", with no stability contract. It does carry things
`--json` does not, notably `messagingSocketPath`, `peerFeatures` and `nameSource`.

### 1.5 Background sessions and PTY jobs

`claude --bg "prompt"` (positional; rejected with `-p`), `--name`, `--agent <subagent>`,
and `claude --bg --exec 'pytest -x'` for a PTY-backed job with no model that still gets a
row in agent view. State at `~/.claude/jobs/<id>/state.json`, scratch at
`~/.claude/jobs/<id>/tmp/` (writes there never prompt), `CLAUDE_JOB_DIR` exported.

`--exec` output is **memory-only and cleaned up ~5 minutes after exit**. Scrape with
`claude logs <id>` promptly or lose it.

Sessions idle and unattached over an hour have their process stopped and resume on attach.
Pin to prevent.

### 1.6 Cross-session messaging and the inbox socket

Every session binds a Unix socket. Path is in `/status` as `Peer address` (`uds:` prefix),
in the registry as `messagingSocketPath`, and exported as `CLAUDE_CODE_MESSAGING_SOCKET`
with `CLAUDE_CODE_MESSAGING_TOKEN`, **before any hook runs, including SessionStart**.
Fallback dir `/tmp/cc-socks-<uid>`.

Protocol: optional auth line `{"type":"auth","token":"..."}` first (required on Windows),
then the message. **Open the connection only when the payload is ready** - a connection
with no complete line within 30s is closed.

The receiving Claude reads it **between tool calls**, so a running tool is never
interrupted; an idle session starts a new turn. Own-child messages (a hook or Bash command
posting back to its own session) skip the inbound hold.

**`notify_when_idle`** subscribes to a one-shot notice when another local session next goes
idle or exits. No polling on either side, no tokens spent in the watched session, fires
immediately if already idle, expires after 12h, main conversation only.

**The gotcha that will bite us:** `crossSessionInbound` defaults derive from permission
mode. A `bypassPermissions` receiver **holds** every message from a non-bypass sender for
approval. Every pane here runs bypassed. Messages from an ordinary session will silently
sit held, and in a `-p` worker with no dialog they expire at `dialogExpiry` (5 min).

### 1.7 Worktrees, native

`.claude/worktrees/<name>`, branch `worktree-<name>`, base from `worktree.baseRef`
(`fresh` = remote default branch, `head`). `.worktreeinclude` (gitignore syntax) copies
gitignored files in. `--worktree <name>`, `--worktree "#1234"`, subagent
`isolation: worktree`, and background sessions isolate automatically unless
`{"worktree": {"bgIsolation": "none"}}`.

Locking is careful: a `git worktree lock` held for the life of the agent, a sweep that
releases locks from killed sessions but never one you set yourself, and a marker in git
metadata so the sweep can tell its worktrees from yours (v2.1.246+).

`WorktreeCreate` (blocks on non-zero exit) and `WorktreeRemove` hooks let you control
layout, but **the hook replaces `.worktreeinclude` processing**, so copy `.env` yourself.

`.worktreeinclude` is now a de facto standard, shared with ccmanager.

### 1.8 Agent teams

`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. `teammateMode` is `in-process` (default since
v2.1.179), `auto`, `tmux`, `iterm2`. **Split-pane mode does not support wezterm.** Not
VS Code, Windows Terminal or Ghostty either.

State: `~/.claude/teams/session-<first 8 of sid>/config.json` (holds tmux pane ids, do not
hand-edit), inboxes at `.../inboxes/<agent>.json`, tasks at `~/.claude/tasks/<team>/`.
Teams do **not** worktree-isolate teammates; partition files yourself. Teammate permission
prompts surface in the lead session. No nesting. Can leave orphaned tmux sessions.

Gotcha: with teams enabled, **any subagent Claude names launches as a teammate**, so teams
form when you did not ask.

Quality gates: `TeammateIdle` (exit 2 keeps it working), `TaskCreated`, `TaskCompleted`.

### 1.9 statusLine JSON we are not reading

Beyond what `statusline.sh` consumes:

```json
"rate_limits": { "five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
                 "seven_day": {...}, "spend_limit": {...} },
"prompt_cache": { "warm": true, "ttl": "1h", "expires_at": ..., "hit_ratio": 0.91,
                  "misses": 2, "expected_rebuilds": 1, "recache_tokens_if_cold": 45000 },
"cost": { "total_cost_usd": ..., "total_lines_added": ..., "total_lines_removed": ... },
"pr": {"number": 1234, "review_state": "pending"},
"worktree": {"name","path","branch","original_cwd","original_branch"},
"prompt_id": "...", "exceeds_200k_tokens": false, "agent": {"name": "..."}
```

`prompt_cache` and `rate_limits.spend_limit` landed v2.1.251. **`prompt_cache.warm` and
`expires_at` are authoritative cache warmth**, strictly better than our `statusUpdatedAt` +
assumed 1h TTL, because `ttl` can be `5m` and `misses` vs `expected_rebuilds` separates a
real miss from a post-compaction rebuild.

Absence rules: `rate_limits` is Pro/Max only, appears only after the first API response,
and **each window is dropped once its `resets_at` passes**. Guard with `// empty`.
`context_window.current_usage` is null before the first call and again after `/compact`.
`cost.total_cost_usd` resets to $0 on `/clear` (v2.1.211).

`statusLine.refreshInterval` (min 1s) re-runs the command on a timer, recommended in the
docs "when background subagents change git state while the main session is idle".

**`subagentStatusLine`** is a separate, entirely unused surface: one command receives every
visible subagent row (`id`, `name`, `type`, `status`, `model`, `effort`, `tokenCount`,
`contextWindowSize`, `cwd`), and takes back one JSON line per row with ANSI and OSC 8.

### 1.10 Other surfaces

- **Plugin background monitors**: `monitors/monitors.json` with a long-running command;
  every stdout line reaches Claude as a notification for the session's life, no polling, no
  model call to arm it. `when` is `always` or `on-skill-invoke:<skill>`. Personal scope
  only (project skills-dir plugins do not load monitors). Disabled if `DISABLE_TELEMETRY`
  or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` is set.
- **Channels** (research preview): an MCP server that pushes events into an open session,
  arriving as `<channel source="..." severity="...">`. **Permission relay** is the
  standout: Claude sends `permission_request` with a `request_id`, your server replies
  `{request_id, behavior: allow|deny}`. A documented remote-approval protocol.
- **Monitor tool** takes a `ws` input for WebSocket feeds; each message becomes an event.
- **Deep links**: `claude-cli://open?cwd=...&q=...&repo=owner/name`, max 5000 chars.
  **Wezterm is an explicitly supported handler target on macOS** and reuses the terminal
  from the most recent interactive session.
- **OTEL**: `terminal.type` detects wezterm, `session.id` on by default, `prompt.id` for
  correlation. Metrics for token usage, cost, lines of code, active time, commits, PRs.
  Subprocesses no longer inherit `OTEL_*` (so hooks will not pollute the stream). Do not
  use `claude-code-otel`, dead 15 months; use `alibaba/loongsuite-pilot` or
  `vivekchand/clawmetry`.
- **`claude mcp serve`** exposes Claude Code's own tools to other MCP clients.
- **Env vars worth knowing**: `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` (the real fix for
  the nested-launch transcript problem cc-spawn works around by scrubbing the env),
  `CLAUDE_CODE_RESUME_INTERRUPTED_TURN` + `CLAUDE_CODE_RESUME_PROMPT`,
  `CLAUDE_CODE_RETRY_WATCHDOG=1`, `CLAUDE_CODE_TASK_LIST_ID` (share one task list across
  panes), `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20),
  `CLAUDE_CODE_PROJECT_DIR_NAME`, `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` (Task/Todo tools were
  removed on Opus 4.8 / Sonnet 5 / Fable 5+).

### 1.11 Removed or renamed, check any script that assumes otherwise

Ultraplan gone (w32). `/fork` changed meaning at v2.1.212, old behaviour is `/subtask`.
`/output-style` removed at v2.1.91. `SessionEnd` reason `bypass_permissions_disabled`
removed v2.1.234. **Session names are uniqueness-enforced since v2.1.232**: start or rename
into a live name and you silently get `name-graceful-unicorn`, so read the name back rather
than assuming it stuck. There are now three name-like things: a name you set, a default
display name (`my-app-3f`, not a resume handle, not in statusline `session_name`), and a
generated title (is a resume handle, does populate `session_name`).

---

## 2. State detection: the four mechanisms

Every tool surveyed uses one or more of these. Ranked by reliability.

**A. Hooks.** Authoritative, cheap, edge-triggered. Blind to: Esc interrupts, permission
grants, stop-hook continuations, and anything that happens without an event firing.

**B. `claude agents --json`.** Level-triggered truth, no parsing risk, sees sessions
started outside your rig. Hooks give you edges, this gives you level. Use both.

**C. Pane titles.** Claude Code writes its spinner glyph and an LLM-written topic into the
OSC title. herdr's `claude.toml`: idle is `^\x{2733} `, working is
`^[\x{2800}-\x{28FF}\x{25D0}-\x{25D3}] `. **Verified here: 34 panes `✳`, 3 `◐`/`◑`, out of
61.** One `wezterm cli list --format json` call, no polling of content, no hooks. Note
`terminalTitleFromRename: false` keeps the generated topic when you use `--name`, and
`terminalProgressBarEnabled` only emits for ConEmu/Ghostty/iTerm2, never wezterm.

**D. Screen scraping.** Last resort. If you must, copy ccmanager's *structural* rules, not
its regexes, which will rot:

- read only the visible viewport, never scrollback
- isolate content above the prompt box by counting `/^─+$/` borders bottom-up, and keep
  only the **most recent contiguous non-blank block** (xterm buffers retain transient
  redraw fragments outside the latest block, and your own typing can match busy patterns)
- **never report idle until the content hash has been stable ~1.5s** (`IDLE_DEBOUNCE_MS`),
  because Claude Code often looks idle mid-processing
- the two most durable signals are `esc to interrupt` / `ctrl+c to interrupt`, and
  `/\d+\.\s*deny\s*\(esc\)/` for permission menus that carry no question phrasing

**E. Silence timers.** workmux flags a pane **interrupted** when output stalls 10s while
status says working. Catches the "user hit Ctrl+C and it is now sitting at a prompt" case
that hooks miss entirely. tmux gets this natively via `monitor-silence` + `alert-silence`.

Not needed here, and the reason is B. Live on this machine, pane 2 (`aperta-4c`) has held
hook state `working` for 13.4 days while its registry entry has said `idle` since the same
second. Hashing pane content on a timer to derive what one jq already knows is the wrong
trade.

**The rule everyone converged on: one status authority per pane.** herdr states it
explicitly - if hooks are installed they are authoritative and the scraper does not run
concurrently, "avoiding two competing sources of truth". Record a `source` alongside state
and have the weaker source refuse to write when a stronger one wrote recently.

**Worst-state-wins for rollups.** A tab shows the worst state across its panes: blocked
beats working beats idle. (`gentle-agent-state`.) `wezterm-attention` uses
notify > stop > review > thinking.

---

## 3. What the other multiplexers have that wezterm does not

The velocity gap is real: wezterm's last tagged stable is **February 2024**. Nightlies are
current (this machine runs 20260803) but there is no stable release in two and a half
years, while Zellij shipped 0.44 and 0.45 in 2026 and tmux shipped 3.6.

**The single biggest structural gap: wezterm has no output-streaming primitive.**
`get-text` is poll-only. Everyone else has push:

| | streaming primitive |
|---|---|
| Zellij | `zellij subscribe --pane-id X --format json`, NDJSON on change |
| tmux | `pipe-pane -o`, control mode `%output`, `refresh-client -B` format subscriptions |
| kitty | `kitty @ launch --watcher` Python callbacks |
| herdr | socket API `events.subscribe` on `pane.agent_status_changed` |
| wezterm | none |

### Zellij
- `zellij subscribe`, above. Full viewport on connect with `is_initial: true`, then only
  on change, exits when the panes close.
- `attach --create-background` headless sessions.
- **Blocking spawns**: `--blocking`, `--block-until-exit`, `--block-until-exit-success`,
  `--block-until-exit-failure`. `zellij run --block-until-exit-success -- cargo test && ...`
- `dump-screen -p <id>` for any pane, `edit-scrollback` (opens a pane's scrollback in
  `$EDITOR`, trivially portable and genuinely useful for reading a long agent transcript).
- `list-panes --state` reports **exited**. `wezterm cli list` has no exit state and no pid,
  so you cannot tell from the JSON alone which panes run an agent.
- `send-keys` takes **symbolic key names**. Ours sends literal text only.
- `new-pane --no-focus` (spawn without stealing focus), `--start-suspended`,
  `--close-on-exit`, `--near-current-pane`.
- `zellij pipe` is a broadcast bus with backpressure, bidirectional.
- KDL layouts with `pane_template`/`tab_template` and cwd composition.
- Session resurrection on by default, restored commands **staged behind a "Press ENTER"
  banner** so a restore does not fire off twelve agents unattended. Worth copying.
- 0.45 added nested-session handling, OSC 133 scroll-by-command (`copy last command
  output` is a nice `wz` verb), a mobile web UI and a PWA.
- Web client with read-only tokens: `zellij web --create-read-only-token`.

### tmux
- **`pipe-pane`** streams a pane's output to a command. No wezterm equivalent. Closest
  workaround is launching agents under `script -q -F <log>`, which is arguably better
  because it survives pane death.
- **`wait-for`** is a named rendezvous channel, a barrier primitive for "run the reviewer
  only after the three implementers finish". Replaceable with a lock dir or `flock`.
- Hooks include `pane-died`, `pane-exited`, `alert-silence`, `command-error`. Wezterm's
  Lua event set has none of these, and **no pane-close event at all**, which is why
  `wezterm-attention`'s poller has to reap markers for panes that vanished between ticks.
- `monitor-silence` + `alert-silence` is stall detection for free.
- 3.6 added `tiled-layout-max-columns` (cap a tiled layout at N columns; wezterm has no
  auto-tiling at all), per-pane scrollbars, `capture-pane -T` (stop at the last used cell
  rather than padding, i.e. a clean scrape).
- Control mode (`tmux -CC`) format subscriptions: server-side computed, change-only push.

### kitty
- **`kitty @ --match`** is a real match expression language over `id`, `title`, `pid`,
  `cwd`, `cmdline`, `env`, `state`, `recent`, `var` with booleans and regex. Ours has
  `--pane-id` and `--class`. A `wz sel` helper over `list --format json` and `jq` closes
  this and gives broadcast for free.
- `launch --watcher` Python callbacks: `on_cmd_startstop`, `on_set_user_var`,
  `on_title_change`, `on_close`.
- `--hold` keeps a window open at a prompt after the command exits. **Our crashed agents
  vanish and take the error with them.**
- **OSC 99 desktop notifications**, the best notification protocol in the field: ids for
  update and dedupe, urgency levels, per-notification sounds, click-to-focus routing, and
  **buttons whose answer is sent back to the application**. Wezterm does not support it.
  `terminal-notifier -group <pane> -execute '...'` gets the two properties that matter
  (dedupe, click-to-focus).

### Ghostty
Verified in source, and weaker than the release notes suggest. IPC is `new-window` at
v1.3.1, three actions on main, and **`performIpc` returns false for every action on
macOS** - IPC is GTK/D-Bus only. AppleScript (1.3.0, macOS only) is the sole real surface
and `wezterm cli` is a superset of it except for synthetic key events and `perform action`.
**Ghostty does not implement OSC 1337 SetUserVar either** (only Copy and CurrentDir), which
is why Warp's plugin resorts to OSC 777 with a fake title as a routing key. No agent
features at all. The scripting-API tracking issue has been open since Oct 2023, unanswered.

Two ideas worth taking anyway: `shell-integration-features = path` (force the terminal's
own binary dir onto `PATH` inside panes, so orchestration scripts do not fail mysteriously
in the one pane whose `.zprofile` reset `PATH`), and `ssh-terminfo` caching.

### Warp
- **Child-agent status chips**: a compact row of coloured chips per spawned child, next to
  the parent. Maps onto `format-tab-title` rendering one glyph per pane rather than one per
  tab, which is roughly what we do already.
- **Auto-handoff prompt when the machine sleeps.** The most original idea in their 2026
  line-up, and we already have `cc-handover` to wire it to.
- **Queue terminal commands alongside prompts**: enqueue "when this finishes, run the
  tests" without waiting at the keyboard. A marker file the Stop hook drains.
- Vertical tabs as the agent roster, each row carrying branch, cwd, worktree path, PR
  number and status, diff stats, and a status badge. Badge vocabulary: magenta clock in
  progress, green check done, red triangle error, grey stop cancelled, **yellow stop
  blocked**, plus an accent dot for unread.
- **Only parent conversations raise toasts and mailbox entries**; child status goes to the
  orchestration pill bar only. Deliberate anti-spam rule, and the right one for subagents.
- Notification mailbox with All/Unread/Errors filters, tab badges cleared on navigating to
  the tab.
- **Synchronised input syncs the whole command from the input editor, not keystrokes.**
  The right semantics for agent panes; keystroke broadcast into a TUI is useless.
- Permissions: allow and deny lists are regexes, **denylist beats both allowlist and
  "agent decides"**, and `Run Until Completion` is a **time-boxed** escalation for one task
  rather than a standing skip-permissions habit. Worth thinking about given every pane here
  runs bypassed permanently.
- Tab Configs (TOML, replaced the deprecated launch-configuration YAML) with `{{param}}`
  prompting and `repo`/`branch` param types. The shipped worktree example is exactly the
  fleet primitive: prompt for repo, base branch and name, then `git worktree add`.
- `oz` CLI exposes **`oz run message list|read|send|watch|mark-delivered`**, an inter-agent
  mailbox as CLI verbs. Good shape for cc-note.
- Code review with per-hunk revert and **inline comments the agent receives and acts on**.
  Portable: write `path:line: comment` to a file and feed the owning session.

---

## 4. The purpose-built agent multiplexers

**herdr** (github.com/ogulcancelik/herdr, ~35k stars in 105 days). Single Rust binary,
background server, sessions survive lid close and reboot. The reference design.

- Two-tier state detection with the one-authority rule (see section 2).
- Per-agent TOML manifests classify idle/working/blocked from a bottom-buffer snapshot.
  ~19 agent CLIs supported out of the box.
- **`herdr agent wait <pane> --until done`** is the single most useful missing verb. It
  turns a spawner into an orchestrator: `wait api done && send reviewer "api is ready"`.
- **`agent_prompt_stalled`**: a prompt sent from a non-working state must produce a
  lifecycle change within 5 seconds or it fails loudly. Best error-handling idea in the
  whole survey.
- `herdr pane report-agent` and `report-metadata --token summary=...` let an agent
  self-report a **display-only** channel separate from state, so it can say what it is
  doing without lying about whether it is blocked. Exactly what cc-note is for.
- Socket API, NDJSON over a Unix socket, `events.subscribe` on `pane.agent_status_changed`.
- `herdr api schema --json` - a documented machine surface, because the primary consumer is
  another agent.
- Toast delivery is a config choice (`herdr`/`terminal`/`system`/`off`) with a
  `delay_seconds` to suppress flapping.
- Distinguishes `idle` from `done`, where done is unseen finished work, and **CLI reads do
  not mark it seen**.

**cmux** (manaflow-ai/cmux, ~27k). Native macOS app in Swift/AppKit using **libghostty as a
rendering library**, not a fork. No tmux, no containers, **no worktrees**. Reads your
Ghostty config. The important trick: it **impersonates tmux** so that Claude Code's native
agent teams spawn teammates as real native panes rather than hidden processes
(`cmux claude-teams`). Notifications via OSC 9/99/777, embedded scriptable browser pane.

**workmux** (raine/workmux, tmux and Zellij, not wezterm). One worktree plus one window per
task. `workmux add -A "task"` creates branch, worktree and agent; `workmux merge` handles
cleanup. `workmux.yaml` for file copies, symlinks and setup hooks. Auto-detects nine agent
CLIs and installs the right hooks. Three states with **✅ auto-clearing on window focus**,
plus the 10s stall heuristic. Hook discipline worth copying verbatim:
`workmux set-window-status working >/dev/null 2>&1 || true; printf '{}\n'` - never break
the agent, always pass the payload through.

**claude-squad** (smtg-ai, 8.4k). tmux plus a worktree per session. Notable detail:
branches from the **resolved HEAD commit, not the branch name**, which stops uncommitted
changes leaking in.

**hcom** (aannoo/hcom). Single Rust binary, **no background service**: hooks record to
SQLite and deliver from it, `agent → hooks → db → hooks → other agent`. Messages arrive
mid-turn or wake idle agents. Each agent gets a queryable identity: inbox, live screen,
transcript in chunks, event log of every edit and tool call. **Collision detection on by
default: two agents editing the same file within 30s and both get notified.** Supports
wezterm for pane closing.

**FrankenTerm** (Dicklesworthstone). A wezterm-fork mux hypervisor, 83 crates, 1.26M lines.
Not adoptable, but the API shape is the right target: `ft robot state` (AI-readable
snapshot), `ft robot wait-for` (condition-based, never sleep-based), a
`{ok, data, elapsed_ms, version, schema_version}` envelope on every response, and
**secret redaction before returning pane text** so a JWT cannot leak into a notification.

Also: `agent-of-empires` (TUI and web over one fleet), `awslabs/cli-agent-orchestrator`,
`claude_code_agent_farm` (20+ agents, lock-based coordination, adaptive timeouts at
3x median cycle time, heartbeat files), `dmux`, `ccmanager`, `agent-manager`, `ralphex`,
`repomon`, `Tmux-Orchestrator` (historically influential, stale since Jul 2025).

---

## 5. The wezterm plugin ecosystem that already exists

- **`afewyards/wezcld`** - makes Claude Code agent teams work here. A launcher that sets
  `TERM_PROGRAM=iTerm.app`, prepends its `bin/` to `PATH`, and runs
  `claude --teammate-mode tmux`; a shim at `bin/it2` translating `session split` →
  `split-pane`, `session run -s <id>` → `send-text --pane-id`, `session close` →
  `kill-pane`, everything else silent success. Pins `it2 0.2.3`. **The technique
  generalises: any tool that hard-codes tmux or iTerm2 can be redirected by shimming four
  verbs.** cmux does the same thing with a fake `tmux` binary.
- **`pro-vi/wezterm-attention`** - the file-marker contract, and the cleanest integration
  point in the survey. Write `{"type":"thinking"|"stop"|"notify"|"review"}` to
  `~/.local/state/wezterm-attention/$WEZTERM_PANE`, atomically via `.tmp` + rename.
  Poller on `update-status`, **renderer on `format-tab-title` with zero I/O**. Sidecars:
  `.ack` written on focus (acknowledge by writing a sidecar, **never by deleting
  writer-owned state**), `.review`, `.agents` (subagent roster, rendered `✓+2`).
  `publication_id` so an identical repeat payload becomes visible again after ack.
  `ttl_ms` with a 30-minute default for stale `thinking`. Pane-id gated on `/^\d+$/`
  because an unvalidated `../` would clobber outside the marker dir.
  **Caveat: wezterm only runs the first registered `format-tab-title` handler.**
- **`Eric162/wezterm-agent-deck`** - pure Lua, `update_interval = 500`, output pattern
  matching, `terminal-notifier` backend with sound.
- **`wrock/wezterm-agent-cards`** - explicitly cmux-inspired sidebar. Eight hooks writing
  `/tmp/wezterm-hook-<pane>.json`, with a **subagent counter so subagent tool use does not
  clear a waiting status**. Notable architectural choice: **the sidebar is a normal pane
  running a Python curses app, not Lua**, because Lua only gets to paint tab titles and the
  status bar. Same shape as cc-board, which is reassuring.
- **`M-Marbouh/agent-quota.wezterm`** - reads `~/.claude/.credentials.json` and the OAuth
  usage endpoint, renders `Claude: 5h ███░░░░░ 42% (2h31m) ▪ 7d █░░░░░░░ 18%`, per-user
  JSON caches in `/tmp` so parallel windows do not all refresh at once. Now largely
  superseded by `rate_limits` in the statusLine JSON.
- `MLFlexer/resurrect.wezterm` (already in use), `smart_workspace_switcher.wezterm`,
  `srackham/tabsets.wezterm`, `adriankarlen/bar.wezterm`, `michaelbrusegard/tabline.wez`.

---

## 6. Worktree strategies compared

| tool | path | branch | base | merge back |
|---|---|---|---|---|
| Claude Code | `.claude/worktrees/<name>` | `worktree-<name>` | `worktree.baseRef`: `fresh` or `head` | commits and pushes before finishing, draft PR when warranted, never to main, never force |
| claude-squad | `~/.claude-squad/worktrees/<branch>_<hex>` | `<user>/<session>` | **resolved HEAD commit** | `s` commit and push, `c` commit and pause |
| dmux | per pane | AI-generated | configurable per pane | menu: merge with cleanup, or open a PR |
| ccmanager | per worktree | user-chosen | | in-app merge, `.worktreeinclude` |
| agent-farm | none, shared checkout + lock files | | | commits with diff summaries |

---

## 7. Prior art worth reading before building anything

- **`sverrirsig/claude-control`** - the closest cousin to this rig. `ps` discovery, `lsof`
  for cwd, hook-written `~/.claude-control/events/<pid>.json` as the authoritative PID →
  JSONL map with an mtime fallback for sessions that predate its hooks, auto-installs its
  own hooks, walks the process tree to find each session's terminal.
- **`fujibee/agmsg`** - peer-to-peer over a shared SQLite file, no daemon. **A SessionStart
  hook opens the Monitor tool on a blocking SQLite stream**, giving ~5s real-time push into
  a running session. The only production-grade push channel anyone built outside Anthropic.
- **`LiveNL/tmux-claude-status-tabs`** - transcript watchers catching the Esc, permission
  grant and stop-hook-continuation transitions that hooks never report. Same blind spot
  exists here.
- **`warpdotdev/claude-code-warp`** - open source, readable, six hooks. Steal the 0.3s
  transcript-flush sleep on Stop, and the capability negotiation via version gate.
- **`stefanprodan/cctop`** - live subagent and subprocess tree with open and orphaned TCP
  ports. Its statusline writes `usage.json` which the TUI reads: clean decoupling.
- **`kbwo/ccmanager`** - the state detector at `src/services/stateDetector/claude.ts` is
  the best-documented scraping ruleset in the field.
- **`TevvvB/termagitchi`** - stable per-session identity by hashing the session id, one den
  per worktree. Same problem the colour palette solves, same solution.

Ecosystem churn to be aware of: `ryoppippi/ccusage` → **`ccusage/ccusage`** (own org,
rewritten in Rust). `ruvnet/claude-flow` → **`ruvnet/ruflo`** (70k stars). `stravu/crystal`
→ **`nimbalyst/nimbalyst`**. `ColeMurray/claude-code-otel` **dead** since Jun 2025 but still
cited everywhere. `hesreallyhim/awesome-claude-code` rebooted from scratch, old entries
frozen in `README_ALTERNATIVES/`. SuperClaude in maintenance mode, superseded by native
skills and plugins.

---

## 8. Backlog, re-ranked after building the first four

The first four items landed. Building them, and then asking the machine what it actually
reports rather than what the survey said it would, moved most of the rest and took two off
the list entirely. What changed, before the list:

- **`claude agents --json` is a union of two files on disk, and for interactive sessions
  it is the registry.** Byte-identical on `status`, `waitingFor`, `name`, `cwd` and `pid`
  over three back-to-back runs, at 120-180ms against under 10ms for one jq over the same
  files, and `waitingFor` is a registry field `cc-roster` already reads into `detail`.
  Old item 5 was a fork for data that is already on disk. What the CLI sees and we do not is
  background sessions, which have no registry file at all and live in
  `~/.claude/jobs/<id>/state.json` - a file that carries more than `--json` exposes.
- **The registry sees what the hooks miss, which retires stall detection.** Pane 2
  (`aperta-4c`) has held hook state `working` for 13.4 days; its registry entry has said
  `idle` since the same second. That is item 10's whole use case, answered by one jq.
- **`wezterm.lua` is one authority short of `cc-fleet`, and both of those wrong answers are
  on screen right now.** `pane_status` reads the hook state files and the title spinner and
  nothing else. So pane 2 has read as wanting you for thirteen days, and pane 404
  (`digitalfive-40`) reads `stale`, the glyph for a pane to close, while the registry says
  `waiting` / `dialog open` and has for 5.2 hours. The survey's one-authority rule is about
  which source wins, not about having one: cc-fleet merges two and gets both of these
  right.
- **State files are keyed by pane, sessions are not, and nothing writes state at
  SessionStart.** Second cause of pane 404: the record belongs to the session that used to
  be in that pane, and a session that has not been prompted yet never overwrites it.
- **The three files that write and render all of this are not in this repo.**
  `~/.claude/hooks/wezterm-pane-state.sh` and `wezterm-session-map.sh` sit beside
  `statusline.sh` as plain files while all ten scripts in `bin/` are symlinks. The state
  machine that just gained three events has no history, no diff and no way back.
- **`prompt_cache` and `rate_limits` are real on 2.1.260**, from a captured payload:
  `warm`, `ttl: "1h"`, `expires_at`, `hit_ratio`, `recache_tokens_if_cold: 94674`, and
  `five_hour.used_percentage: 79`, `seven_day: 45`. They are two different kinds of fact.
  Rate limits are per account, so every session reports the same pair and it is one figure
  for the machine rather than a column. Cache warmth is per session, and it replaces the
  `statusUpdatedAt` + assumed-1h rule CLAUDE.md documents, which is wrong exactly when it
  matters: `ttl` drops to 5m in overage.

Ranked. Items marked **done** have landed; see git log.

1. **`StopFailure` -> an errored state. done**
2. **Read `background_tasks` in the Stop hook -> parked. done**
3. **`PermissionRequest` for an instant blocked signal. done**
4. **Worktree per session in cc-spawn, opt-in, native pass-through. done**
5. **Version the hooks and the statusLine.** `git mv` into `hooks/`, symlink both ways, the
   same treatment `bin/` has had since the start. Cheap, and everything below that touches
   either file wants doing after it rather than before. **done**, and it took four files
   rather than three: `claude-session-brief.py` is called by wezterm.lua too.
6. **The registry into the tab bar.** `cc-roster` is already the merge and prints the pane
   column; a throttled background child process writes its output to a digest and the
   renderer reads one file with no per-pane I/O, which is `wezterm-attention`'s split and
   the reason that plugin is the cleanest thing in section 5. Fixes both wrong answers
   above. Order the sources explicitly and record which one won: errored, then the
   registry's `waiting`, then asking, then parked, then busy or a spinner, then fresh,
   then stale. **done**, with the order written out above `pane_status` and one rule that
   only became obvious while building it: an idle registry must never overrule a hook
   record that says errored or parked, because idle is what both of those look like from
   outside. The right-status counters go through `pane_status` now too, so they cannot
   disagree with the tab bar beside them. Nine cases under luajit, and both live wrong
   answers flipped: pane 2 grey, pane 404 asking `dialog open`.
7. **A session id on the state record.** Fourth field, and readers drop a record whose sid
   is not the one the pane map holds. Have SessionStart write a state too, so a fresh
   session is not silently wearing its predecessor's. **done** - SessionStart clears a
   foreign record rather than writing one, since with the registry in the merge a pane
   with no record reads correctly on its own. Verification turned up the mirror image of
   the same bug, in the pane it was being written from: **the map was written once, at
   SessionStart, and never again**, so a second Claude started inside a pane takes the map,
   exits, and leaves the resident session with no address at all. Every state event
   rewrites the map now.
8. **Rate limits in the right status bar.** One figure, once, for the machine: `5h 79%`
   with the reset time, red as it closes. It is the only number here that changes what you
   *start*, and at 79% today it would have changed this afternoon.
9. **Cache warmth per session, from `prompt_cache`.** Replaces the assumed TTL in cc-fleet
   and cc-handover, both of which currently guess. `expires_at` is the answer, `ttl` is
   the reason the guess breaks, and `recache_tokens_if_cold` prices the cold start.
10. **A seen/unseen dimension.** herdr's split: `idle` is a chat you have read, `done` is
    finished work nobody has looked at, and a CLI read does not clear it. Cleared by
    entering the pane, via an `.ack` sidecar, never by deleting writer-owned state. This is
    the cheaper half of what the chime was for: the question that sat for twenty hours sat
    there because nothing said it was unread, not because nothing made a sound.
11. **`wz wait --until`** plus herdr's stalled-prompt guard. The verb that turns a spawner
    into an orchestrator, and it is only honest now that `parked` exists, because `done`
    meant "idle with children still running" until last week. Poll the merge, not a socket:
    5ms and level-triggered beats `notify_when_idle` needing a live connection per wait.
12. **A same-file collision guard**, hcom's, and the one item on this list that prevents
    damage rather than describing it. 38 live sessions, several per repo, worktrees opt-in,
    and two of them editing one file is silent lost work. PreToolUse on the write tools
    against a small `file -> sid, epoch` ledger; warn at first, deny later if warning is
    not enough.
13. **`waitingFor`'s values for triage.** The field is already in `detail` and nothing reads
    what it says. `permission prompt` and `input needed` want you now; `dialog open` and
    `sandbox request` are a different urgency, and `worker request` is not about you at all.
14. **Background sessions in the merge.** `~/.claude/jobs/*/state.json` at the same 1ms as
    the registry, and with `detail` carrying the job's last line of output, which is better
    than anything we show for an interactive pane. Nothing here sees them today. Wants
    `cc-spawn --bg` to give it a reason, and a rendering answer first: a background job has
    no pane, and every surface in this repo is keyed by one.
15. **cc-spawn holds on exit** so a crashed agent leaves a visible pane rather than a gap.
    `config.exit_behavior = "CloseOnCleanExit"` may be the whole of it, one line, but it is
    global and a shell pane exits non-zero more often than you would think, so measure the
    nuisance before keeping it.
16. **`wz sel`**, a `--match` expression over `list --format json`, and broadcast on top.
17. **OSC 9 toasts via `terminalSequence`**, which needs no tty and no poller, suppressed
    when the pane is already focused.
18. **`wz scrollback`** (dump to a file, open `$EDITOR`) and durable per-agent logs via
    `script -q -F`.
19. **A documented `--json` snapshot** with FrankenTerm's envelope, because the primary
    consumer of cc-fleet is another Claude.
20. **Push into a session rather than at the desk**: `asyncRewake` hooks, plugin
    `monitors/monitors.json`, the messaging socket. The only channels here that can tell a
    *session* something without it asking, and the honest alternative to a chime. Costs
    tokens in the receiving session, so it wants a real question first.
21. **`wezcld`'s shim technique** if agent teams are ever wanted here.
22. **`subagentStatusLine`**, still an entirely unused surface.
23. **Only parents notify**: suppress toasts for subagents and teammates.
24. **Time-boxed permission escalation** rather than a standing
    `--dangerously-skip-permissions`.

**Off the list.** `claude agents --json` on the hot path (item 5 in the first pass): for
interactive sessions it is the registry, thirty times dearer, and already being read. It
stays the right thing for a one-off check by hand, and for anything that wants the
background half without knowing two file layouts. Content-hash
stall detection (item 10): the registry reports the interrupted pane on its own.
`notify_when_idle` as the basis for `wz wait`: it is in this machine's `peerFeatures`, and
a 5ms poll over the merge needs nothing from it.

**Tried and parked:** a chime for a pane that has been `asking` or `errored` past fifteen
minutes. It is in wezterm.lua behind `CHIME_ENABLED = false`. The gap is real, and it is
the only one left in the state work: every surface here is pull, so a session holding a
question is invisible for exactly as long as nobody looks, and one held one for twenty
hours. The argument against is that cc-note already has two levels because a notification
per pane teaches you to ignore all of them, and this is a third channel. Items 10 and 19
are both cheaper answers to the same gap, so decide the chime after them rather than
before: flip the flag for a week and count how often it was right.
