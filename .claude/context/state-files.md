# State files: formats, writers, readers

Every field is tab-separated unless said otherwise, and an absent value is written `-`
wherever a reader splits on whitespace (an empty column folds into its neighbour).

## read, written by Claude or by Kev

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
- **`~/.cache/kev/asks/<sid>`** `verdict\tp\tepoch\tuuid`, the final reply judged blocked,
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
    entry is still running; `asking` PermissionRequest, Notification as the backstop;
    `errored` StopFailure; `ended` SessionEnd
  - **parked** is a finished turn waiting on its own background work, which since fork mode
    and background subagents is the difference between finished and not. Nothing writes
    when that work ends without a turn, so **every reader expires parked**: 30m for a
    `monitor`, 2h for a `shell` (their limits since 2.1.271 and 2.1.285), 4h otherwise,
    constants in wezterm.lua, cc-roster and cc-board
  - **errored** exists because Stop does not fire when a turn dies on an API error
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
  recache_tokens, hit_pct`, by the statusLine on every render. Claude hands these to the
  statusLine and nowhere else: not the registry, and a transcript has tokens but not the
  window to divide by. Readers: cc-board, cc-fleet, cc-handover, wz, wezterm.lua, kev-mcp
  stop-asks (field 1). Old files have three fields. cc-board can also scrape the visible
  statusLine, which needs the pane on screen
- **`cache/rate-limits`** `epoch, 5h_pct, 5h_resets, 7d_pct, 7d_resets, spend`, per account
  so one file, any statusLine at most every 5s. Right status: `5h N% HH:MM`, hidden once 10
  minutes old or past its reset; `▲ out <when>` once a window is 10 points ahead of an even
  burn (not in its first tenth), red when that is under a quarter of the window away; the
  7d figure only then or past 75%
- **`cache/fleet-digest`** `#<epoch>`, then `pane, sid, status, waitingFor, seen_ms` per
  pane with a live session. `cc-roster --digest` writes it whole and renames it; wezterm.lua
  asks for one when it is over 5s old. It is how the registry reaches Lua, which cannot
  afford a jq over 38 files a second; the epoch is inside because Lua has no stat
- **`cache/pane-read`** `focus\t<pane|->\t<looking>`, then `pane, left_at, marked`: what
  Jacob has read. wezterm.lua writes it on focus moves (it lives in `wezterm.GLOBAL`, this is
  the mirror); cc-board and cc-toast read it. Unread: hook record done or parked with an
  epoch after `left_at`, or marked (LEADER+U), and not the pane he is on. First sight is a
  baseline, never unread
- **`cache/notify-log`** `epoch, pane, rank, title` per `wz notify`, trimmed to 200: what
  LEADER+t (Kev's top unseen) and LEADER+T (newest) jump to
- **`cache/cc-toast/<slot>`** `<pid> <height> <sticky 0|1> <started_ms>`, space-separated:
  which toast holds which place, and which the cap of five may not evict
- **`fleet/actions.d/`** the shell -> Lua queue, one file per action, written aside and
  renamed in; Lua drains by name every 0.1s. `jump\t<pane>` is a toast click, run
  in-process like LEADER+t; `goto` is wz go. The old single `fleet/actions` file still drains
- **`fleet/notes.tsv`** cc-note: `sid, at, flags, progress, status`, one line per annotated
  session. Read by the statusLine, cc-fleet and the tab bar. `fleet/todo/<sid>`,
  `fleet/log/<sid>` are read on demand only, never on a timer
- **`fleet/handover/<name>-<stamp>.md`** cc-handover's briefs; cc-handovers writes
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
