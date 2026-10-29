# State files: formats, writers, readers

Every field is tab-separated unless said otherwise, and an absent value is written `-`
wherever a reader splits on whitespace (an empty column folds into its neighbour).

## read, written by Claude or by Kev

Every path here is under `~/.claude`, whichever account a session runs on: another
account's folder (`~/.claude-personal`) is links back into it (cc-account), so readers
never look anywhere else. **`~/.claude/accounts`** is the map, `<name> <folder> <email>
<dirs>...`, out of the repo; read by cc-account, and via `--lib` by statusline.sh,
cc-spawn and hooks/cc-limits.sh. Beside it, both out of the repo and written by hand or
cc-account: **`account-overrides`** `<name> <folder> <until epoch>`, a folder lent to
another account, expired lines ignored and dropped on the next write; and
**`account-limits`** `<name|*> <folder|*> <5h|7d> <stop> [warn]`, stop a percentage or one
a calendar day of the window (`11,23,47,65,90`); `<name|*> <folder|*> fallback <account>`
moves a session there at a cap. **`cache/limits/<acct>-<win>-<reset>-<level>`** marks a
toast sent, once a window; **`cache/limits/moving-<sid>`** a fallback switch started,
honoured 15 min; both pruned after 8 days.

- **`~/.claude/sessions/<pid>.json`**, the registry. name, status, cwd, session id,
  `statusUpdatedAt` (when its last request finished), `waitingFor`, and `formerNames`, the
  addresses it has been renamed away from. A name is not a stable address: cc-roster
  resolves the old ones, and emits every name lowercased with spaces folded to hyphens,
  because a background session is named after its task. `statusline.sh` and `cc-colour`
  read the registry direct and fold the same way: change the fold in all three. The four
  ways a name moves: `docs/tools.md`. Statuses include `waiting` (stopped, wants an
  answer) and `shell` (turn over, a background shell still running: level-triggered, so it
  reads as parked with no expiry)
- **`~/.claude/jobs/<id>/state.json`**, background sessions, which have no registry file.
  `needs` is what one wants from Jacob, plus `detail`, `inFlight`. cc-fleet `--jobs`,
  `--job <id>` and a line in `--brief`
- **`~/.claude/history.jsonl`**, every prompt Jacob has sent, for the age column
- **`~/.cache/kev/asks/<sid>`** `verdict\tp\tepoch\tuuid\trank`, the final reply judged blocked,
  offer or done (kev-mcp `hooks/stop-asks.py`). In cc-board a verdict overrules the "?"
  rule both ways; absent means fall back. `~/.cache/kev/drift/<sid>.json` while a run
  looks off task: "drifting?" on a working frame. Both via `read`/`-e`, no fork
- **`~/.claude/session-colours`** hand-pinned hues, `<sid>\t<hue>`, cc-colour

## the pane map and the hook record

- **`~/.claude/wezterm-sessions/<pane>`** pane -> session id. Written at SessionStart and
  **rewritten on every state event**: a second Claude started inside a pane runs its own
  SessionStart, takes the map and exits, leaving the resident session with no address
  (`wz last <name>` fails, cc-roster shows pane `-`). Each turn takes it back
- **`~/.claude/wezterm-state/<pane>`** `state\tepoch\tdetail\tsid`, from five hooks:
  - `working` UserPromptSubmit; `done` and `parked` Stop, parked when a `background_tasks`
    entry is still running, or detail `cron` when `session_crons` has an entry (a /loop
    or wakeup that starts the next turn itself; 4h cap); `asking` PermissionRequest, Notification as the backstop;
    `errored` StopFailure; `ended` SessionEnd
  - **parked** is a finished turn waiting on its own background work, which since fork mode
    and background subagents is the difference between finished and not. Nothing writes
    when that work ends without a turn, so **every reader expires parked**: 30m for a
    `monitor` (its limit since 2.1.271), 4h otherwise (a terminal session's background
    shells have no limit since 2.1.288); constants in wezterm.lua, cc-roster, cc-board.
    The Monitor tool's watch reaches Stop as `shell`, not `monitor` (only MCP and
    WebSocket ones say monitor). A parked `shell` also ends once the registry reads idle
    after it: the registry's `shell` status tracks exactly those tasks (seen 2026-10-05:
    `shell` from the Stop second until the watch ended)
  - **errored** exists because Stop does not fire when a turn dies on an API error.
    Detail `rate_limit` reads as parked "resumes HH:MM" in every reader while
    `cache/rate-limits` holds the first reset after the record, until 5 minutes past it:
    Claude resumes it then (`autoContinueAtUsageLimit`). Notification writes
    `rate_limit_stale` (slept through the reset, waits for Enter) or `rate_limit_disabled`
    when it will not, which stay errored. Rule in wezterm.lua's `rate.resume_at`,
    cc-roster, cc-board
  - an **asking** record is dropped once the registry has moved past it: Esc on a dialog
    ends the turn with no Stop
  - `detail` is the tool for asking, the error kind for errored, the task type for parked,
    empty otherwise: **never `IFS=$'\t' read` it**. awk -F'\t' and Lua are fine
  - `sid` is the writer, because **panes outlive sessions**: a /clear or restart leaves the
    next session wearing the last one's record until its first prompt. SessionStart clears a
    record not its own and every reader drops one whose sid is not the pane's. Records from
    before 2026-09-04 have no sid and are trusted

## written by these scripts

- **`cache/context/<sid>`** `used_pct, window_size, epoch, expires_at, ttl_s,
  recache_tokens, hit_pct, 5h_pct, 5h_resets, 7d_pct, 7d_resets`, by the statusLine on
  every render; the rate fields are only its own memo for `cache/rate-limits`. Claude hands these to the
  statusLine and nowhere else: not the registry, and a transcript has tokens but not the
  window to divide by. Readers: cc-board, cc-fleet, cc-handover, wz, wezterm.lua, kev-mcp
  stop-asks (field 1). Old files have three fields. cc-board can also scrape the visible
  statusLine, which needs the pane on screen
- **`cache/rate-limits`** `epoch, 5h_pct, 5h_resets, 7d_pct, 7d_resets, spend`, for
  `~/.claude`'s login; **`rate-limits-<name>`** the same for each other account
  (cc-account), the statusLine picking by its `CLAUDE_CONFIG_DIR`. `rate-limits.<pid>` is a
  write in progress, skipped. A `rate_limit` record does not say whose account died, so a
  reader takes the earliest reset of any file that fits it. The payload does not name the
  account, so a statusLine writes when
  its figures changed since its own last render (a new response), else at most every 5s
  refreshes the epoch only if it agrees with the file: an idle pane re-renders its last
  response's, maybe another login's. Never merge on "later reset wins": another account's
  window can reset later and sticks.
  Right status: `5h N% HH:MM`, hidden once 10 minutes old or past its reset; `▲ out
  <when>` once a window is 10 points ahead of an even burn (not in its first tenth) or,
  from 75%, on any burn that runs out before the reset; red when that is under a quarter
  of the window away; the 7d figure only then or past 75%
- **`cache/privacy-dots`** `time\tkind app, ...` by cc-privacy, one line per change in
  what holds the privacy dot or location, ignored apps left out; empty field is nothing on.
  Appended forever (a few lines a day). Reader: `cc-privacy`
- **`cache/fleet-digest`** `#<epoch>`, then `pane, sid, status, waitingFor, seen_ms` per
  pane with a live session. `cc-roster --digest` writes it whole and renames it; wezterm.lua
  asks for one when it is over 5s old. It is how the registry reaches Lua, which cannot
  afford a jq over 38 files a second; the epoch is inside because Lua has no stat
- **`cache/pane-read`** `focus\t<pane|->\t<looking>`, then `pane, left_at, marked`: what
  Jacob has read. wezterm.lua writes it on focus moves (it lives in `wezterm.GLOBAL`, this is
  the mirror); cc-board and cc-toast read it. Unread: hook record done or parked with an
  epoch after `left_at`, or marked (LEADER+U), and not the pane he is on. First sight is a
  baseline, never unread. Leaving updates `left_at` only after 2s on the pane
  (`READ_DWELL`): passing through is not reading
- **`cache/kev-pick`** `#<epoch>\tfrom <pane>`, then `n, pane, score, why, name`: LEADER+t's
  ranking of every pane, yours included. Written by the `pick` action and every 2s while
  `cache/cc-toast/` has a slot; cc-toast orders its stack by `score`
- **`cache/notify-log`** `epoch, pane, rank, title, sid, body` per `wz notify`, `-` when
  absent, trimmed to 200; lines before 2026-10-01 stop at title. What LEADER+t (Kev's top
  unseen) and LEADER+T (newest) jump to, skipping a pane that now holds another session,
  and what `wz toasts` lists
- **`cache/cc-toast/<slot>`** `<pid> <height> <sticky 0|1> <started_ms> <rank> <pane|->`,
  space-separated, rewritten when a pill opens. The slot is an id; the stack is ordered by
  the pane's kev-pick score, else rank, newer first on a tie. Past five the last in that
  order goes, non-sticky first
- **`fleet/actions.d/`** the shell -> Lua queue, one file per action, written aside and
  renamed in; Lua drains by name every 0.1s. `jump\t<pane>` is a toast click, run
  in-process like LEADER+t; `goto` is wz go. The old single `fleet/actions` file still drains
- **`fleet/notes.tsv`** cc-note: `sid, at, flags, progress, status`, one line per annotated
  session. Read by the statusLine, cc-fleet and the tab bar. `fleet/todo/<sid>`,
  `fleet/log/<sid>` are read on demand only, never on a timer
- **`fleet/switch/<sid>`** `to\tuntil epoch (0 none)\tname\tqueued epoch`, a queued
  `cc-account switch`, its follow-up prompt in `<sid>.then`; written by cc-account, read
  and removed by its watcher (`.watcher/pid`, a mkdir lock), read by cc-handover --new
- **`fleet/gathered/<receiver pane>`** `pane\tsid\tname\tepoch` per source of a gather (the
  epoch is the handover's, for ccx's grace on a `shell` source), written by cc-handover,
  read and pruned by ccx (it keeps what it could not close); reaped with the pane by
  `cc-roster --digest`. Beside it, a plain `--new`'s `<receiver pane>.name`: the
  source's name, which ccx `/rename`s the receiver to once the list empties
- **`fleet/handover/<name>-<stamp>.md`** cc-handover's briefs, each source's screen
  beside it as `<name>-<stamp>.<source>.scrollback.txt` (cc-handovers globs `*.md`, so
  keep that suffix off it). Reaped by `cc-roster --digest`: screens after 3 days, briefs
  after 14 (only names matching cc-handover's stamp); cc-handovers writes
  `fleet/handover-days/` (`HANDOVER_DAYS` overrides), read by the vault's /weekly-review
- **`cache/wz-events.jsonl`** wz's event log, `wz-events.pid` beside it
- **`session-colours-auto`** hand-pin format, by cc-tint when a new session would reuse the
  colour of the one it replaced. Hand pins win. `cache/cc-tint-painted/<pane>`
  `<sid>\t<hue>`: what was last painted, since a pane's colour cannot be read back
- **`cache/titles/<sid>`** `mtime\x1fchecked_at\x1ftitle`, cc-peers' memo. `checked_at`
  of `sl` means the statusLine wrote it from `session_name` and it needs no transcript read.
  `cache/fleet-rows` cc-fleet's rows, 8s. `cache/jobs-seen/<id>`, `cache/job-rows`
- **`~/.cache/kev/cc-sort-pairs.json`** cc-sort's p(same topic) per pair, a day;
  `cc-sort.jsonl` its plans. `~/.cache/kev/cc-watch/` its pid, run.log, asks.jsonl
- **`cache/cache-write-price`** `cents_per_Mtok\tepoch`, from the last SessionStart resume
  that priced itself (`estimated_cache_write_usd / context_tokens`); cc-fleet's `$` on a
  cold resume, $8/MTok until one has been seen
- **`cache/reap-stamp`** `cc-roster --digest` reaps at most hourly: state and map files for
  panes wezterm no longer has, maps naming an unknown session after a day, titles and
  context a week after their session is gone. Skipped when wezterm answers nothing
- **`cache/cc-enums/<version>`** `set\tvalue`, sorted (`LC_ALL=C`): the value sets cc-doctor
  read from that Claude Code binary. Beside it `<version>.diff`, `#from <prev|->` then
  `+|-|!|*\tset\tvalue` (`!` a set no longer found, `*` one not read before), and empty
  markers `<version>.announced` (toasted, or nothing to toast: the digest's fast path) and
  `<version>.ack` (readers told; the check stops failing). Never pruned; 3KB a version

## dependencies between them

`statusline.sh` sources `cc-colour` and reads `fleet/notes.tsv`, so it moves with the
palette and with cc-note's format. All paths above without `~` are under `~/.claude/`.

## time

Cold is past `expires_at`, which drops to 5m in overage; without it, `statusUpdatedAt` plus
`CACHE_TTL`. Cold greys a session everywhere: tab bar, board, LEADER+; picker, cc-fleet.
`cc-fleet --stale` and `--reap` stay on hours since Jacob's last prompt, because closing a
pane is a different question from what resuming it costs. A transcript's mtime is not this
clock: transcripts are appended long after the last exchange, and by it every session looks
warm.
