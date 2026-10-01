# What changed since the September survey, October 2026

A follow-up to `docs/findings-2026-09.md`, which was written against v2.1.260 and wezterm
20260803. This machine now runs Claude Code 2.1.286 and still wezterm 20260803. Only what
is new, or was known and is newly worth building, is here.

Sources: the CHANGELOG (2.1.260 to 2.1.286), code.claude.com docs (statusline, hooks),
string and schema checks against `~/.local/share/claude/versions/2.1.286`, the files under
`~/.claude/`, and the wezterm commit log since 6f8b1d41.

**VERIFIED** means it was seen on this machine: in a file on disk, in the local binary's
schema strings, or in a command's output. **DOCS-ONLY** means it comes from the changelog
or the docs and was not seen locally.

Out of scope, because agents are building them already: `prompt_cache` warmth,
`rate_limits` in the right status, the registry's `shell` status, background jobs in
cc-fleet, and 20s toasts with completion notices. Fields those agents may have missed are
called out in the item that owns them.

---

## Ranked

### 1. Two constants are now wrong: a Monitor lives 30 minutes, a background shell 2 hours

- **2.1.271**: "Monitor watches always have a deadline (at most 30 minutes)", which
  replaced the `persistent` option. This session's own Monitor schema caps `timeout_ms`
  at 1800000 (VERIFIED).
- **2.1.285**: "background Bash and PowerShell commands stop after a time limit (their
  `timeout` with `run_in_background`, default 30 min, max 2 h); Claude is notified when
  one is stopped" (DOCS-ONLY).

**What breaks.** CLAUDE.md, wezterm.lua, cc-roster and cc-board all expire `parked` at 1h
for a monitor (`PARKED_MONITOR_MAX`) and 4h for anything else (`PARKED_MAX`).
- A parked monitor reads parked 30 minutes after it cannot possibly still be running.
- A parked shell reads parked for 2h too long.
- Subagent, workflow and teammate work has no such cap, so 4h stays right for those types.

**Fix.** Set `PARKED_MONITOR_MAX` to 1800 and add a shell cap of 7200, keyed on `detail`
(the hook already writes the task type there). The registry's new `shell` status is the
level-triggered version of the same fact and should win over either timer when present.
Effort: three constants and one `case` per reader, plus the CLAUDE.md line.

### 2. Background jobs say what they want from you: `needs` in `state.json`

VERIFIED. `~/.claude/jobs/<id>/state.json` carries far more than `claude agents --json`.
The `--json` keys are only `cwd id kind name pid sessionId startedAt state status
waitingFor`. `state.json` adds:

- `needs`: a one-line, Claude-written statement of what the job is waiting on you for.
  Today 3 of the 5 jobs carry one:
  - "pick which voice to use: Noah, Keith or Chris"
  - "say go and I'll run the 13"
  - "decide: wire whisper-off for 1 draft office (Polybound) or skip?"

  All three have been stopped for 10 to 22 days with nobody seeing them.
- `detail`: the last status line, for example "handed non-NTA work to d5-lca-53".
- `tempo`: `idle` and others.
- `inFlight`: `{tasks, queued, kinds, drainableMonitors}`, which is parked detection for
  jobs, free.
- `tokens`, `cliVersion`, `updatedAt`, `lastTerminalAt`.
- `timeline.jsonl` beside it: `{at, state, detail, text}` per transition, including
  `blocked` with the question.

**For agent B.** Show `needs` verbatim as the job's ask, and treat a non-null `needs` as
"wants you" in `--brief`. That is the whole reason the NTA job's four decisions sat
unseen. `~/.claude/daemon/roster.json` lists live workers (`workers: {}` today) if a cheap
"is any job running" check is wanted. Effort: one jq over `jobs/*/state.json`, about 1ms.

### 3. A rate-limited pane is not dead: it resumes itself

VERIFIED in the binary's notification-type enum: `quota_auto_resume_fired`,
`quota_auto_resume_stale` and `quota_auto_resume_disabled`. The string beside them reads
"Usage limit reset, Claude is continuing your task". 2.1.271 added the same for dynamic
workflows: they "pause when you hit your usage limit and continue automatically when it
resets".

**Today.** StopFailure writes `errored` with the error kind, and every surface shows a
dead pane. When auto-resume is armed, that pane is really waiting for
`rate_limits.five_hour.resets_at`.

**Fix.**
- When the errored kind is a rate limit, render "resumes 15:40" from the rate-limits
  cache, not as an error.
- Add a `Notification` hook on matcher
  `quota_auto_resume_fired|quota_auto_resume_stale|quota_auto_resume_disabled`.
  - `fired` flips the pane back to working.
  - `stale` or `disabled` keeps it errored, and is the one worth a toast.

Lands in `hooks/wezterm-pane-state.sh` (one more event), `pane_status`, and cc-roster and
cc-board. Effort: small. The precedence rule is unchanged, because errored still beats an
idle registry.

### 4. Resuming a cold session prices itself: SessionStart's resume fields

VERIFIED in the binary's SessionStart schema, which describes them like this:

- `seconds_since_last_response`
- `context_tokens`: "the resumed transcript's last response input + cache_read +
  cache_creation + output tokens".
- `prompt_cache_likely_expired`: "seconds_since_last_response exceeds the prompt-cache
  TTL, so the first request re-caches context_tokens".
- `estimated_cache_write_usd`.

All four arrive on `source` `resume` and `fork` only.

This is the "handover or resume" decision, priced by Claude Code at the moment it matters.
- **SessionStart.** When `prompt_cache_likely_expired` is true and `context_tokens` is
  large, have the session-map hook write the figure where cc-fleet can show it. It can
  also raise "resuming d5-lca-9a re-caches 460k tokens (~$3.70); LEADER+H for a fresh
  one?". This is the same toast path T is building.
- **Before resuming.** cc-fleet's stale list can use `prompt_cache.recache_tokens_if_cold`
  from the statusLine cache, which is the same number known in advance.

Lands in `hooks/wezterm-session-map.sh` and cc-fleet. Effort: small.

### 5. statusLine fields that retire work we do by hand

Field names are VERIFIED in the binary and the semantics are from the docs.

- **`session_name`** is the custom name, or else the AI-generated title. cc-peers works
  this out by tailing 256KB of every transcript and running awk for `custom-title` and
  `ai-title`, then memoising it in `cache/titles`.
  - **Fix**: statusline.sh writes `session_name` into the same memo file, and cc-peers
    falls back to the transcript only for sessions that never rendered a statusLine.
  - This cuts most of cc-peers' remaining cost and the 544-file titles cache.
- **`pr.number`, `pr.url`, `pr.review_state`** (`approved`, `pending`,
  `changes_requested`, `draft`): the PR badge Claude already computes.
  - **Fix**: a board column, or one glyph next to the name, plus an OSC 8 link.
  - It replaces any `gh` call the board would otherwise make.
- **`cost.total_cost_usd`, `cost.total_lines_added`, `cost.total_lines_removed`**: Warp's
  roster columns for free. A machine total of `total_cost_usd` across live sessions is the
  cost line cc-fleet lacks.
- **`prompt_cache` fields beyond warm, expires_at and recache_tokens_if_cold**, for agent
  L:
  - `last_miss_cause` (`{causes: [...], tools_added, ...}`) and `miss_causes` (2.1.260)
    say *why* a session went cold: `idle past the TTL`, `tools_changed` or
    `system_prompt_changed`. A pane that went cold because an MCP server reconnected is a
    different problem from one that sat too long.
  - `caching_observed: false` means caching is off, not cold.
  - `expires_at` is `null` when the last response had no cache tokens. Guard it.
- **The statusLine re-runs itself at `expires_at`** and at every `resets_at` (DOCS-ONLY:
  "a warm prompt cache in the data your script last received reaches its expires_at
  time"). So `cache/context/<sid>` is rewritten with `warm: false` at the moment of
  expiry, without a prompt. Readers can trust the cached `warm` flag rather than doing
  clock maths, as long as the pane's Claude process is alive.

Lands in statusline.sh, cc-peers and cc-board. Effort: small for the first two, medium for
the board column.

### 6. Sessions can ping you on purpose: the `push_notification` Notification type

VERIFIED. The binary's notification-type enum is wider than the docs list:
`permission_prompt idle_prompt auth_success elicitation_dialog agent_needs_input
agent_completed elicitation_url_dialog worker_permission_prompt push_notification
computer_use_enter computer_use_exit quota_auto_resume_fired quota_auto_resume_stale
quota_auto_resume_disabled model_refusal_fallback`.

- **`push_notification`** fires when a session calls its PushNotification tool. This
  session has that tool as a deferred tool.
  - **Fix**: a Notification hook on that matcher that hands `message` to `wz notify`.
  - This gives every session a deliberate "tell Jacob" channel through the same 20s toast,
    rather than the toast guessing from a Stop.
  - It costs nothing until a session uses it. The fleet skill should say when to use it.
- **`worker_permission_prompt`**: a background worker is waiting on approval. It belongs
  with `asking`.
- **`model_refusal_fallback`**: worth a toast.

**Related, PLAUSIBLE.** The `claude` alias in `~/.zshrc` sets `TERM_PROGRAM=kitty`, to get
synchronised-update markers. The binary picks a notification channel from `tQ = [auto,
iterm2, terminal_bell, iterm2_with_bell, kitty, ghostty, notifications_disabled]` with
`preferredNotifChannel` unset. So "auto" most likely resolves to kitty's OSC 99, which
wezterm drops. Claude Code's own notifications are then silent. That is harmless now that
`wz notify` does the job, but setting `"preferredNotifChannel": "notifications_disabled"`
makes it explicit, and stops a later wezterm that does handle OSC 99 from double-toasting.

Lands in `hooks/` (a Notification matcher), the skill, and `settings.json`. Effort: tiny.

### 7. A cold session does not need a pane: `claude --bg --resume <id>`

DOCS-ONLY, flags VERIFIED in `claude --help`.

- `--bg` with `--resume <session-id>` "continues that session in the background under the
  same ID".
- 2.1.285: `claude --resume <id> "prompt"` sends the prompt "to it as its next turn" when
  the session is already running in the background.
- `claude stop`, `attach`, `logs`, `rm` and `respawn [--all]` complete the set.

**What it allows.** It answers "19 idle panes, all cold" without losing them. Close the
pane, keep the session addressable as a job (item 2 makes jobs visible), and wake it from
cc-fleet or cc-handover with one command, so the pane comes back only when it is needed.

**Upkeep.** `respawn --all` keeps background workers on the current version. The daemon
log shows `worker 2.1.284 (daemon 2.1.286)` for a job retired this morning. `claude rm`
belongs in `cc-fleet --reap` for jobs that are `done` with no `needs`.

Lands in cc-fleet (`--reap`, `--park`) and cc-handover (`--to <job>`). Effort: medium.
Decide the rendering question from backlog item 14 first.

### 8. Interrupt and send at once: send-now

VERIFIED in the changelog.
- 2.1.275 added send-now: ctrl+enter, or ctrl+x ctrl+s.
- 2.1.282 and 2.1.286 changed it to move running tools to the background rather than
  cancel the turn.

So text typed into a busy session can be delivered *now*, without waiting for the turn to
end, and without the Esc that kills the turn.

- **Fix**: `wz send --now <target> <text>` types the text, then sends ctrl+x ctrl+s.
- Use the two-key form, because ctrl+enter needs the kitty keyboard protocol to arrive
  distinctly through wezterm.
- `cc-handover --to` into a working session wants it.

Lands in bin/wz. Effort: tiny.

### 9. Measure the context bill: `/skill-doctor` and `/doctor prompt-audit`

VERIFIED in the changelog.
- `/skill-doctor` (2.1.261) shows "which loaded skills go unused and what they cost in
  context".
- `/doctor prompt-audit` (2.1.283) audits "CLAUDE.md files, skills, agents and commands
  for prompting patterns written for older models".

This repo's CLAUDE.md is about 5k tokens and the fleet skill about 3.3k. Run both once and
take what they say before trimming by hand. Effort: two commands.

### 10. Still unused, and worth more now: `subagentStatusLine`

DOCS-ONLY, setting name VERIFIED in the binary. This was item 22 in September.
- With fork mode and background subagents on by default, a session's children are where
  most of its work happens. This is the only live feed of them.
- Each refresh tick gets `tasks[]` with `id name type status description label startTime
  model effort contextWindowSize tokenCount tokenSamples cwd`.

**Fix.** A command that writes `cache/children/<sid>`, a line per task, and still returns
the default row. The tab bar can then draw Warp's child chips: one dot per running child.
Note it runs only while the agent panel is visible. Effort: small to write, medium to
render.

### 11. Answer from the phone: `cc-spawn --remote`

VERIFIED in `--help`.
- `claude --remote-control [name]` starts a session that the Claude app can drive.
- 2.1.273 lets the app fork it into a background session on this machine.
- `--fallback-model <list>` keeps a pane alive through an overload rather than dying into
  `errored`.

**Fix.** Pass both through cc-spawn, as was done for `--effort` and `--model`. Effort:
tiny.

---

## wezterm since 20260803

VERIFIED from the commit log, 72 commits to 2026-09-29. Nothing structural:
- no output streaming
- no pane-close event
- no pane exit state in `cli list`
- nothing in the log touches OSC 1337 `SetUserVar`

Small but relevant:
- `cab25161` keeps `;` in OSC 8 URIs, so statusLine and board links with query strings
  stop breaking.
- `016b9627` routes OSC 52 clipboard to the pane's own window.
- `2b56c468` adds a bottom fancy tab bar design.
- `5c096095` adds a `command_palette_line_height` option.

Upgrading the nightly is cheap. Re-run the SetUserVar test from CLAUDE.md's dead ends
after it, since the test is quick and the payoff (a CLI-to-Lua bridge without the
action-queue file) is large. Keep `front_end = "WebGpu"`, because nothing in the log
touches glium.

## Community, briefly

Nothing that moves the design.
- `exPardus/fleet` (4 stars, very active) has a supervisor tier, and its "usage-limit
  park/resume" is item 3 done by hand.
- Nick Nisi's tmux Fleet (May 2026) fuses hooks, an event log and scrapes. Each layer is
  "authoritative only for what it can be trusted on", which is this repo's precedence
  rule. It has one idea worth taking: **a permission prompt guard on pane switch**, so a
  key pressed while jumping in cannot answer a dialog. 2.1.284 does the same for Remote
  Control confirmations. Every pane here is bypassed, so this matters only for `cc-spawn
  --ask`.

## Not worth building on

- `CLAUDE_CODE_TERMINAL_RECORDING` and `CLAUDE_PTY_RECORD` exist in the binary's env table
  next to the debug and perfetto variables, undocumented. They are probably internal
  recording for debugging. Do not build durable agent logs on them (backlog item 18); use
  `script -q -F` as planned.
- `"attribution": false` (2.1.281) in `~/personal/.claude/settings.json` would enforce the
  no-attribution rule in ~/personal/CLAUDE.md mechanically. It has nothing to do with the
  fleet, but it is a one-line settings change.
