# Capabilities survey, 5 October 2026

A docs-based survey of what Claude Code 2.1.289 and wezterm 20260803-054620-6f8b1d41 can
do, checked against this repo. It follows `claude-code-2026-10.md` (2.1.260 to 2.1.286)
and repeats nothing from it, `findings-2026-09.md`, `dead-ends.md` or `state-files.md`
unless it changed. Where to look next time: `sources.md`.

**VERIFIED** means seen on this machine: a file on disk, the local binary's strings, a
command's output, or a test run. **DOCS-ONLY** means from the docs or changelog alone.
Line numbers are against the working tree of 5 October, uncommitted changes included.

The short version: Claude Code moved very little between 2.1.286 and 2.1.289 (no new hook
events, statusLine fields or settings keys, the same 33 events and 13 StopFailure kinds).
The wezterm cli has not changed since 2024. Most of what is below is the survey reading
our own code against the docs and finding it wrong, plus one dead end that is only half
dead.

---

## Built the same day

Jacob asked for five follow-ups from this survey. What landed, uncommitted, on 5 October:

1. **`cc-doctor`**: one script for the invariants that drifted. Links (every `bin/*`
   twice, hooks, config, statusLine, skill), cc-toast built from its current source,
   hooks in settings.json against what setup.sh wants (read from setup.sh, not copied),
   `PARKED_*` and the cache TTL agreeing across their readers, `--no-auto-start` on every
   `wezterm cli` call, wezterm.lua loading, the running Claude Code against
   `sources.md`'s version (a warn, never a fail), and unacknowledged enum changes. About
   0.2s. First run: everything ok but the 39 calls without `--no-auto-start` (item 4,
   left for Jacob) and `auth_storage_failure`, since handled and acknowledged.
2. **The version watch**, `cc-doctor --enums`: on a new binary it extracts hook events,
   `notification_type`, StopFailure kinds, statusLine keys, registry statuses,
   `waitingFor` and `background_tasks` labels from its strings, snapshots them in
   `cache/cc-enums/<version>`, and toasts once what was added or removed. Runs detached
   from `cc-roster --digest`'s hourly reap; a no-op stat when the version has not changed,
   about 1.2s once per version. Two sets are partial: statusLine keys set through a shared
   helper, and a task type missing from Claude's label map, are not seen.
3. **The restore fix and session ids.** `strip_resume_flags` drops everything from `--`,
   and cc-spawn's `--session-id` and `--fork-session` (beside an inserted `--resume`
   either would fork). cc-spawn picks the session id up front (`--print-sid` prints it);
   cc-handover `--new` watches the receiver by it. The brief stays inline in argv: that is
   a deliberate choice (no tool call before work starts), and with the strip it no longer
   leaks into a restore. `--session-id` with `--resume --fork-session` was checked against
   a fake API: the fork lands under the chosen id with the source's context.
4. **SetUserVar**: measured on the live GUI (item 3). Built the poke (`wz go` drains the
   queue at once); not the hook-state transport, which the measurement ruled out.
5. **The small three.** A rate-limited pane reads parked `◌15:40` until its reset, in
   wezterm.lua, cc-roster and cc-board alike, with the quota notifications marking one
   that will not resume (item 6; also item 8's matcher rewrite and type-based state, and
   `auth_storage_failure` as a toast). cc-toast pauses its countdown after 60s with no
   input anywhere and gives at least 8s on return, using the system idle counter rather
   than `list-clients` (item 14); a toast that times out with nothing touched since it
   appeared waits the same way. And `cc-handover <T> --fork`, warm only, via
   `cc-spawn --fork <sid>`.

Tested: the restore and resume rules under luajit, the hook under a pty with planted
payloads in a scratch HOME, cc-roster against a planted registry, cc-board's rule lifted
alone, the fork refusal on a live cold session, setup.sh's jq against a copy of
settings.json (only the matcher changed), and one poke at the focused pane.

Not built, from the ranked list: items 2, 4, 5, 7 (but `wz go`'s client choice), 9's env
scrub and `ultracode`, 10 to 13.

---

## Ranked

### 1. Restoring a cc-spawn pane re-sends its old prompt and drops the fresh brief

VERIFIED. A pane started by cc-spawn keeps its prompt in argv: `ps` shows pid 87485 as
`claude --dangerously-skip-permissions -- # Handover...` and 92429 as `... -- Read
.../fleet/handover/d5-lca-38-20261005-083907.md and continue`. `strip_resume_flags`
(`wezterm.lua:271-283`) removes only `--resume/-r/--continue/-c`, so on restore:

- **Warm** (`wezterm.lua:296-298`, `:403`): arms `claude --resume <sid> ... -- '<old
  prompt>'`. Since 2.1.285 a prompt passed with `--resume` is sent as the next turn, so
  Enter replays the original brief into a session that already did it.
- **Cold** (`wezterm.lua:409-416`): arms `claude ... -- '<old prompt>' "$(cc-handover
  <sid>)"`. Claude takes the first positional only, with no error, so the fresh brief is
  silently lost and the session starts on the stale one. Tested against a local fake API
  in `-p` mode; interactive is expected to match.

Affects every handover successor and every LEADER+G receiver, which is to say every pane
the fleet tools start. **Fix**: `strip_resume_flags` stops at `--` and drops it and
everything after. Effort: tiny. **Built** (below).

### 2. Transcripts are deleted after 30 days, and the rig reads them

VERIFIED on disk; the default is DOCS-ONLY. `cleanupPeriodDays` is unset in
`~/.claude/settings.json`, so the default 30 applies. 582 transcripts, 1.4G, the oldest
dated 7 September (28 days): consistent with a 30-day delete by mtime.

What loses its source when a transcript goes: the restore brief
(`hooks/claude-session-brief.py:124`, "no transcript found"), cc-handover and cc-peers,
`--resume` of an old pane, and the background jobs whose `needs` have sat unanswered for
10 to 22 days (October item 2). Those lose their conversations within three weeks.

**Fix**: `"cleanupPeriodDays": 365` in `~/.claude/settings.json`, about 17G a year at
today's rate. Jacob's call on the number. Effort: tiny.

### 3. SetUserVar's event fires only for the pane on screen

Re-measured on the live GUI the same day (VERIFIED), after a separate-GUI test said the
dead end was wrong. Both were half right:

- `user-var-changed` fired for the focused pane (135) and not for two panes in other
  workspaces (33, 152), from a logging handler added to the live config for the test.
- `get_user_vars()` held the values for all three: the sequence is parsed and stored for
  every pane, on screen or not.
- The 4 September test wrote to panes that were not on screen, so it saw no event; the
  separate GUI's test pane was on screen, so it did. A visible but unfocused pane is
  untested. The value must be base64, or it is dropped silently.

**What that allows.** A poke, not a channel: `wz go` writes its action file as before,
then a `wz_poke` user var to the focused pane's tty, and the handler drains
`fleet/actions.d/` at once instead of on the next 0.1s tick. Lost or not, the file is
still claimed by rename, so an action runs exactly once. **Built**, see below.

**What it does not.** Hook state through a user var to the tab bar: the panes whose tab
entries matter are the ones not on screen, which get no event and so no instant repaint,
and `pane_status` is mostly called with a bare pane id, so reading the var is a mux call
per pane, no cheaper than the memoised state file. Not built; recorded in `dead-ends.md`.

OSC 9;4 progress (`get_progress()`, allowed by `terminalSequence`) stays a fallback
transport if ever needed; Claude sends its own 9;4 while working, so they would collide.

### 4. Most `wezterm cli` calls can start a headless mux server, and two bursts did

VERIFIED in `~/.local/share/wezterm/` logs. Without `--no-auto-start`, a call that cannot
reach the GUI runs `wezterm-mux-server --daemonize` and blocks about 2.5s. On 28 September
15:10 to 15:14, after the GUI crashed, 29 attempts, one server living at least 3.5
minutes; on 2 October 08:35, when the GUI quit, 4 more. The callers were processes that
outlived the GUI; the logs do not name them.

Only `bin/cc-sort:62`, `bin/cc-watch:115` and `toast/cc-toast.swift:169` pass the flag.
About 40 calls in wz (17), cc-board (7), cc-handover (5), cc-spawn (4), cc-fleet, ccx,
cc-tint and cc-roster do not. Likely culprits: `wz events --daemon` (`bin/wz:787`) and the
detached loops in cc-handover (`:436-448`, `:458-474`). The risk while the GUI is down is
cc-spawn or `wz send` landing in a hidden headless pane.

**Fix**: `--no-auto-start` everywhere through one helper per script; the events daemon
exits after repeated failures so `ensure_daemon` restarts it. Effort: small.

### 5. A Monitor-tool watch reaches Stop as `shell`, so the 30-minute cap never fires

VERIFIED in the 2.1.286 and 2.1.289 binaries, found independently by two agents. The
Monitor tool (and plugin monitors) create `local_bash` tasks with `kind:"monitor"`; the
function that builds Stop's `background_tasks` maps every one of them to `type:"shell"`.
Only MCP and WebSocket monitors arrive as `"monitor"`.

So `PARKED_MONITOR_MAX` (`wezterm.lua:1341`, `:1417`; `bin/cc-roster:196`;
`bin/cc-board:32`, `:345`) never applies to the one task type that has a 30-minute limit,
and `state-files.md:40-42` describes a rule that does not happen. A pane parked on a
dead Monitor reads `parked shell` for up to 4h. Less harm than it sounds: a monitor that
ends normally wakes a turn, whose Stop rewrites the record.

**Fix**: the registry's `shell` status is level-triggered for exactly the set Stop calls
`shell`. So when `detail == "shell"`, a registry reading newer than the hook record that
is not `shell` ends the parked record. Subagent, workflow and errored keep today's rule.
One condition in each of the three readers, after a one-minute Monitor test to confirm.
Effort: small.

Also seen in the binary: task labels `dream`, `auto-mode scan` and `memory import`,
undocumented, which would park a pane for 4h. And a trap for backlog item 20: a plugin
monitor with `when: "always"` has no deadline, so every Stop would park and the registry
would read `shell` all session, which `wezterm.lua:1412-1413` shows as parked with no
expiry. None is enabled today.

### 6. Usage-limit auto-resume is on by default and still drawn as dead

The mechanism is now VERIFIED (October item 3 was enum strings only).
`autoContinueAtUsageLimit` defaults to `true`, so every pane that hits the limit is armed
to resume. On resume Claude queues its own prompt (`origin:{kind:"auto-continuation"}`);
the docs say `UserPromptSubmit` fires on turns Claude starts itself, so the pane most
likely flips to working on its own (not seen live).

What is wrong today:
- `quota_auto_resume_*` is not in the Notification matcher (`setup.sh:67`), and even if
  it were, the notify branch exits on any message without "permission"
  (`hooks/wezterm-pane-state.sh:78-87`).
- `wezterm.lua:1637` ("will not resume itself"), `NEED` errored and `CHIME_STATES` treat a
  `rate_limit` errored pane as dead. It should read "resumes HH:MM" from the 5h reset in
  `cache/rate-limits`.
- `quota_auto_resume_stale` (the Mac slept through the reset) waits for Enter, so it is
  waiting-on-Jacob; `quota_auto_resume_disabled` will not resume, so errored is right and
  it is the one worth a toast.

Effort: small. Precedence unchanged: errored still beats an idle registry. **Built**
(below).

### 7. Two workspace bugs in where panes land and where Enter takes you

- **`cc-spawn --window` opens in a workspace called "default".** VERIFIED in `--help` and
  the installed build's source; not run. Without `--workspace`, `spawn --new-window` goes
  to "default"; wezterm.lua sets no `default_workspace`, there are 26 named workspaces and
  no "default", so the new session opens out of sight. `bin/cc-spawn:169`, and through it
  `cc-handover --new --window`. **Fix**: take `.workspace` from the jq at
  `bin/cc-spawn:113` and pass `--workspace`. Tiny.
- **`cc-board --all`: Enter on a pane in another workspace does not go there.** Inferred
  from the code, not run. `jump` is a bare `activate-pane` (`bin/cc-board:2155-2157`,
  called at `:2359`), which the repo's own notes (`bin/wz:485`) say stays on the current
  workspace. **Fix**: call `wz go`. Tiny.
- **`wz go` reads `.[0].workspace`** from `list-clients` (`bin/wz:493`), wrong if a second
  client is attached. Pick the client with the smallest `idle_time`. Tiny.

### 8. The Notification hook: matcher drift and state from message text

VERIFIED.
- **setup.sh never updates a matcher.** It skips any event that already runs the `notify`
  command (`setup.sh:74-77`), so an edited matcher in setup.sh never reaches
  settings.json. Today's settings.json happens to match; the next matcher change (item 6,
  and `auth_storage_failure` below) will not land. **Fix**: rewrite `.matcher` on the
  group holding `notify`. Small.
- **State is decided from the message text.** `*permission*` is tested for every matched
  type (`hooks/wezterm-pane-state.sh:78-79`), so a `push_notification` mentioning
  permission marks the pane `asking`. **Fix**: switch on `$kind`; `permission_prompt` and
  `worker_permission_prompt` mean asking. Tiny.
- **New type `auth_storage_failure` (2.1.288**; cc-doctor's enum diff places it, absent
  from 2.1.286 and 2.1.287), in the binary, not the docs: "Claude Code
  login needs attention: credentials could not be saved". Fires after an in-session
  `/login` that could not save; later sessions die on `authentication_failed`. Add to the
  matcher and the `ping` case at `:76`. Tiny, after the setup.sh fix.

All three **built** (below).

### 9. cc-spawn: env scrub and flags

VERIFIED.
- **The scrub misses what background jobs export.** A `claude --bg` job exports
  `CLAUDE_CODE_SESSION_KIND=bg`, `CLAUDE_CODE_SESSION_NAME`, `CLAUDE_JOB_DIR` and several
  `CLAUDE_BG_*`; the binary reads the first two at start-up as the session's kind and
  name. So cc-spawn or `cc-handover --new` run from inside a job opens a pane registered
  as kind bg, named after the job. `CLAUDE_CODE_SESSION_ATTENDED` and `TRACEPARENT` also
  leak, harmlessly. `bin/cc-spawn:11-16`. **Fix**: unset them, or scrub by prefix.
  `CLAUDE_CODE_CHILD_SESSION` behaves as before, so the scrub is still needed. Tiny.
- **`--effort ultracode` is refused** (`bin/cc-spawn:93-96`, usage `:30`); claude accepts
  it. Tiny.
- **`--session-id <uuid>`** lets cc-spawn choose the sid up front and print pane and sid
  together, so `fleet/gathered` or a note can be written before the session starts,
  rather than cc-handover polling by pane (`bin/cc-handover:451`). Small.
- **`--resume <sid> --fork-session`** clones a warm session into a new pane at
  cache-read price and keeps the source (flag VERIFIED, semantics DOCS-ONLY). Needs
  `--dangerously-skip-permissions` passed explicitly, since a resume never restores
  bypass. A `cc-handover --fork`, refused when cold. Small to medium.

### 10. Fleet skill text that is now out of date

- **A held message is "NOT delivered"** (2.1.288; notice text VERIFIED in the binary):
  "do not report it as delivered, do not wait for a reply, and do not resend while
  held"; a resend "is only held again" while the two permission modes differ. Bypass to
  bypass always delivers, so here it bites only `cc-spawn --ask` panes (cut off both
  ways), a pane switched to auto or acceptEdits, and Desktop sessions. Background jobs all
  carry `--permission-mode bypassPermissions`. cc-handover and wz type into panes and go
  around the policy. Add one bullet to `skills/fleet/SKILL.md:48-52`: held means not
  delivered, do not resend, do not route round it with `wz send` or `--to`, tell Jacob.
- **Duplicate names** (DOCS-ONLY): SendMessage now adds a short identifier and addresses
  by it, so "reaches whichever is listed first" (`SKILL.md:214-215`, comment at
  `bin/cc-fleet:627`) is wrong.
- **`goal proposal`** is a sixth `waitingFor` value (VERIFIED); `SKILL.md:63-67` lists
  five. No code switches on them.
- **Bypassed panes can stop on a dangerous `rm` inside `bash -c`** (2.1.288). CLAUDE.md,
  `docs/tools.md` and `SKILL.md:148` imply a bypassed pane never prompts. One clause each;
  do not set the opt-out variable.

Effort: tiny for all four.

### 11. A safer Enter for scripted sends: Ctrl+X Enter

DOCS-ONLY. Ctrl+X Enter submits even when an autocomplete suggestion is highlighted,
where a bare Enter accepts the suggestion. `bin/wz:453` and `bin/cc-handover:555` send
`\r`. **Fix**: send `\x18\r`. Pairs with October item 8 (`wz send --now`, ctrl+x ctrl+s),
still unbuilt. Tiny.

### 12. The statusLine knows its width; `@name` is what gets cut

`COLUMNS` and `LINES` are in the statusLine command's environment (docs, and set in the
binary). statusline.sh cuts the title at a fixed 64 (`statusline.sh:31`, `:149`) and puts
`@name` last (`:268`), which is what a narrow pane truncates: in a three or four way split
the SendMessage address goes first. **Fix**: fit to `$COLUMNS`, dropping branch, engine
and label before `@name`. Small.

### 13. Corrections to the October doc, and one-line settings

- **`attribution: false` belongs in each repo's settings, not `~/personal/.claude/`.**
  DOCS-ONLY. Settings load from user, `<project>/.claude/settings.json`, `.local.json` and
  managed, with no parent lookup, so a session in `~/personal/wezterm` never reads
  `~/personal/.claude/settings.json` (which does not exist anyway). Put it in each
  personal repo's `.claude/settings.local.json`. Tiny.
- **`fallbackModel` is a setting** (DOCS-ONLY), up to three models, one cold-cache turn
  per switch. It does what October item 11 planned as a cc-spawn `--fallback-model`
  pass-through, in one line. Which model is Jacob's call.
- **`preferredNotifChannel: auto` is now documented to send a Kitty notification**, which
  `TERM_PROGRAM=kitty` (`bin/cc-spawn:16`, the zsh alias) selects. October item 6 called
  this plausible; it is now stated. `notifications_disabled` is still the tidy setting;
  hooks fire either way.
- **SessionStart hook timeout**: the docs now give 600s for most hooks; September's "30s
  on SessionStart" is gone. `wezterm-session-map.sh` has none and holds up the first
  reply; `timeout: 5`, as cc-tint has, is cheap insurance.
- **`update-right-status` is deprecated** in favour of `update-status` since 20220903
  (DOCS-ONLY; it still fires). `wezterm.lua:1071` and `.claude/rules/wezterm-lua.md`.
- **Rules load on Write/Edit too** (2.1.288), so CLAUDE.md's "read or edit" is now
  accurate.

### 14. `list-clients` has `idle_time`

VERIFIED. How long since Jacob last touched wezterm. cc-toast's countdown runs on while
wezterm is in front and he has walked away; a toast could go sticky after a minute or two
of no input. Also `focused_pane_id` would let `wz ls` mark the one pane he is in rather
than every tab's active pane (`bin/wz:96`, about forty `*`). Small, cosmetic.

---

## wezterm since 20260803

VERIFIED: the installed build is 74 commits behind main (`6f8b1d41...37254829`). One
landed since the October survey's 29 September cut, and it is spelling. No pane-close,
exit or output events, no exit status or user vars in `cli list`, no CLI verb that fires
Lua, no macOS toast change. The `wezterm cli` surface is unchanged since May 2024.

**Upgrading the nightly is worth it, with one visible change.** `ae46d3a0` changes
synthesised bold and dim: bold +200 to +400 weight, dim -200 to -300. With JetBrains Mono
Regular, no `font_rules`, and Thin and ExtraBold installed, Claude's dim text goes from
ExtraLight to Thin, and bold (cc-board and cc-fleet's `BOLD`) from SemiBold to
ExtraBold. Widths do not move. If Thin reads badly at 14pt, two `font_rules` entries
restore today's look.

- How: `brew upgrade --cask wezterm@nightly --greedy-latest`; plain `brew upgrade` skips
  this cask. The nightly was rebuilt 2026-10-05.
- Cost: a GUI restart, so every pane is restored (fix item 1 first).
- Re-test after: SetUserVar (item 3), dim and bold, tab bar widths, OSC 8 links with `;`,
  the config-load check in `.claude/rules/wezterm-lua.md`, LEADER+t/T and a toast click.

Open upstream PRs to watch, neither close to landing: #8203 (`start --wait-exit`, pane
exit status; unreviewed, not compiled by its author), #8036 (a `format-tab-title`
speed-up; changes requested).

## Mods: no new evidence against the 2 October decision

2.1.289's `agent.spawn` and `idle`/`waiting` in `$.agent.list()` change none of the three
reasons (VERIFIED in this build's `claude-code.d.ts`):
- **Own session only**: `$.agent.list()` returns "the session's agents so far, subagents
  and teammates" (`pending running waiting idle completed failed killed`). The only
  cross-session call is `$.session.send`, which is SendMessage.
- **Still changing**: the type file still says "EARLY ACCESS: may change without notice",
  and 2.1.289 alone has about fifteen mod and plugin fixes.
- **Errors and Esc covered**: `idle` and `waiting` describe children inside one session,
  which Stop's `background_tasks` and PermissionRequest already cover.

## The October items, re-checked

| # | item | status |
|---|---|---|
| 1 | Monitor 30m, shell 2h | shell half superseded by 2.1.288 (folded in); monitor half moved, see item 5 |
| 2 | jobs `needs` | holds; built |
| 3 | quota auto-resume | holds, mechanism now verified; not built (item 6) |
| 4 | SessionStart resume fields | holds; built |
| 5 | statusLine fields | holds, identical in 2.1.289; `session_name` built, `pr` and `cost` not; `pr.kind` also exists |
| 6 | `push_notification` | holds; built. `preferredNotifChannel` still unset |
| 7 | `--bg --resume` | holds; not built |
| 8 | send-now | holds; `wz send --now` not built |
| 9 | `/skill-doctor`, `/doctor prompt-audit` | holds |
| 10 | `subagentStatusLine` | holds; unused |
| 11 | `--remote-control`, `--fallback-model` | holds; not passed; `fallbackModel` setting is simpler (item 13) |
| - | `attribution: false` | still unset, and the October location was wrong (item 13) |

Unchanged and checked: registry fields and `claude agents --json` keys; job `state.json`
fields (the docs now call `jobs/` "not a stable interface"); transcript markers; name
uniqueness; `--permission-mode default` still an alias of `manual`; `--help` differs only
by `--client-data-url` removed and `project` renamed `purge` (old name works). New
`<pid>.<hash>.key` files sit in `~/.claude/sessions/`; every reader globs `*.json`.

## Outside this repo

kev-mcp `hooks/stop-asks.py` reads the transcript at Stop, which the docs say can lag the
reply, while `last_assistant_message` is in the payload; it may judge the previous reply.
Its fanout guard matches `Task`, a tool name that no longer exists (harmless).

## Not worth building on

- **`async: true` on the pane-state hooks**: saves 35-40ms per prompt, but a slow
  `working` write can land after a fast `done` and leave the pane stuck working.
- **`statusLine.refreshInterval`**: the statusLine already re-runs at cache expiry and
  rate-limit reset; an idle session has no new data to show.
- **OSC 9;4 progress as a working/idle signal**: a third source of state. As a transport
  only, see item 3.
- **`has_unseen_output`** (always true for Claude panes), **`get_metadata`** (password
  entry only), **`window-focus-changed`** (no pane-focus event; only the "wezterm went to
  the back" branch of `unread_tick` could use it), **`exit_behavior = "Hold"`** (global,
  not per spawn).
- **Touching a file on the config-reload watch list as a signal**: re-evaluates the 3.5k
  line config twice.
- **`$.agent.list()`, `agent.spawn`**: one session, early access (above).
- **Hidden CLI flags**: `--prefill` (types a draft unsent; tempting for a `cc-handover
  --review`, but undocumented), `--resume-session-at`, `--rewind-files`,
  `--resume-drops-turn`, `--reply-on-resume`, `--messaging-socket-path`,
  `--inherit-permission-mode`.
- **Undocumented env vars**: `CLAUDE_CODE_HOST_WORKTREE*`,
  `CLAUDE_CODE_CONFIG_WATCH_EVENTS`; and `CLAUDE_CODE_DISABLE_INLINE_SHELL_RM_PROMPT`,
  which removes a safety net.
- **A global `crossSessionInbound: accept`**: any prompting session could steer a
  bypassed one.
- **`~/.claude/daemon/roster.json`**: the docs call it a reconnect list.
- **`auth_storage_failure` as a state**: a toast at most (item 8).
- **Merging `wezterm cli` calls**: 8-12ms each, nothing to win.
- **cwd in `cli list`**: a URL where only `%20` is decoded; an unusual character in a
  directory name would break cc-spawn, but none is open today.
- **Matchers for `elicitation_*`, `agent_needs_input`, `computer_use_*`**: the registry's
  `waitingFor` covers them.
- **`promptCacheTtl`**: all 59 context cache files that record a TTL say 3600; the 1h
  assumption holds.
