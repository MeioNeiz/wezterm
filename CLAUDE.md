# wezterm + the cc-* fleet scripts

Everything here is symlinked into place, so edit the file in this repo, not the link:

    wezterm.lua   <- ~/.wezterm.lua
    bin/cc-roster <- ~/.claude/bin/cc-roster   who is alive, what state, which pane
    bin/cc-peers  <- ~/.claude/bin/cc-peers    the same, plus a title per session
    bin/cc-fleet  <- ~/.claude/bin/cc-fleet    same, grouped by workspace, aged by my prompts
    bin/cc-board  <- ~/.claude/bin/cc-board    the board: LEADER+b
    bin/cc-colour <- ~/.claude/bin/cc-colour   which pane is which: the identity palette
    bin/wz        <- ~/.claude/bin/wz          panes as a queryable surface, and the event log
    bin/cc-tint   <- ~/.claude/bin/cc-tint     paints a pane's own colours, SessionStart hook
    bin/cc-note   <- ~/.claude/bin/cc-note     what a session says about itself
    bin/cc-spawn  <- ~/.claude/bin/cc-spawn    starts a session in a pane, cleanly
    bin/cc-handover <- ~/.claude/bin/cc-handover  moves work off a session that is full
    skills/fleet  <- ~/.claude/skills/fleet    the skill Claude reads to drive all of it
    statusline.sh <- ~/.claude/statusline.sh   the line at the bottom of every pane
    hooks/wezterm-pane-state.sh   <- ~/.claude/hooks/  what a pane is doing, five events
    hooks/wezterm-session-map.sh  <- ~/.claude/hooks/  pane -> session, on SessionStart
    hooks/claude-session-brief.py <- ~/.claude/hooks/  the header on a restored pane

wezterm.lua reads the scripts through their ~/.claude/bin paths, so the links matter.

The bottom four arrived late, on 2026-09-04. Everything above them had been version
controlled for weeks while the files that write and render the pane states had not:
`wezterm-pane-state.sh` is the only writer of every state the tab bar, the board and the
fleet read, and it had just gained three events with no history and no way back.
`statusline.sh` sources `cc-colour` and reads
`~/.claude/fleet/notes.tsv` directly, so it moves with the palette and with cc-note's
format; changing either without changing it leaves a pane's own line stale or broken.
`~/.claude/hooks/wezterm-backfill-sessions.py` is still outside, and stays there: nothing
calls it.

**Nested sessions.** A `claude` run from a session's Bash tool inherits `WEZTERM_PANE`
and fires every hook as if it owned the pane. Hooks are detached, but the resident
`claude` has the pane as its controlling tty and a nested one has none, so the hooks and
cc-tint check the nearest claude ancestor's tty (`ps -o tty=`, `??` means nested) and
stay out of it.

State the scripts read, none of it theirs:
- `~/.claude/sessions/<pid>.json`   registry, written by Claude. name, status, cwd, session id,
  and `formerNames`, the addresses the session has been renamed away from. A name is not a
  stable address and cc-roster resolves the old ones; it also emits every name as its key,
  lowercased with spaces folded to hyphens, because Claude names a background session after
  its task and nothing here can take an address with a space in it. `statusline.sh` and
  `cc-colour` read the registry direct and fold the same way, so changing that fold means
  changing all three. The four ways a name moves are in `docs/tools.md`
- `~/.claude/wezterm-sessions/<pane>`  pane -> session id. Written by SessionStart, and
  **rewritten on every state event**, because a second Claude started inside a pane runs
  its own SessionStart, takes the map and exits, leaving the session that lives there with
  no address: `wz last <name>` cannot find it and cc-roster reports its pane as `-`.
  Rewriting it on each turn means the resident session takes it back
- `~/.claude/wezterm-state/<pane>`     `state\tepoch\tdetail\tsid`, five hooks now. States:
  `working` (UserPromptSubmit), `done` and `parked` (Stop, told apart by whether the
  payload carries a non-empty `background_tasks`), `asking` (PermissionRequest, and
  Notification as the slower backstop), `errored` (StopFailure), `ended` (SessionEnd).
  `parked` means the turn is over but the session is waiting on its own background work,
  which since fork mode and background subagents became defaults is the difference
  between finished and not. Nothing writes when that background work ends without a new
  turn, so **every reader expires parked**: 1h for a `monitor` (the most a Monitor can
  live), 4h otherwise, constants in wezterm.lua, cc-roster and cc-board. `errored` exists because **Stop does not fire when a turn
  dies on an API error**, so before it a rate-limited pane held its last state for ever.
  `detail` is the tool for asking, the error kind for errored, the task type for parked,
  and empty otherwise, so **never read this with `IFS=$'\t' read`**: tab is IFS whitespace
  and the empty field folds, handing the sid to `detail`. awk -F'\t' and Lua are fine.
  `sid` is the session that wrote the record, because **panes outlive sessions**: a /clear
  or a restart leaves the next session in a pane wearing the last record of the one before
  it, and nothing rewrites it until the first prompt. SessionStart clears a record that is
  not its own and every reader drops one whose sid is not the pane's. Records written
  before 2026-09-04 carry no sid and are trusted rather than dropped. One pane had spent
  five hours reading as a pane to close while the session actually in it sat on a dialog
- `~/.claude/history.jsonl`         every prompt I have sent, for the age column
- `~/.claude/cache/fleet-rows`      cc-fleet's row cache, 8s
- `~/.claude/session-colours`       hand-pinned hues, `<session-id>\t<hue>`, cc-colour

State these scripts write themselves, all of it theirs:
- `~/.claude/cache/wz-events.jsonl` wz's event log, and `wz-events.pid` beside it
- `~/.claude/session-colours-auto`  same format as the hand pins, written by cc-tint when a
  new session would have reused the colour of the one it replaced. Hand pins win
- `~/.claude/cache/cc-tint-painted/<pane>`  `<session-id>\t<hue>`, what cc-tint last painted
  onto that pane. There is no reading a pane's colour back, so this is the only record
- `~/.claude/cache/context/<sid>`   `used_pct\twindow_size\tepoch`, written by the
  statusLine on every render. Claude hands that number to the statusLine and nowhere
  else: the registry does not carry it, and a transcript gives the tokens in play on the
  last turn without the window size to divide by. cc-board gets the same figure by
  scraping the pane's visible statusLine, which needs the pane to exist and be on screen
- `~/.claude/cache/titles/<sid>`    `mtime\x1fchecked_at\x1ftitle`, cc-peers' title memo
- `~/.claude/cache/fleet-digest`    `#<epoch>`, then `pane\tsid\tstatus\twaitingFor\tseen_ms`
  for every pane holding a live session. `cc-roster --digest` writes it whole and renames
  it; wezterm.lua asks for a rewrite from `update-right-status` when it is over 5s old,
  and nothing else reads it. It is how the registry reaches Lua, which cannot afford a jq
  over 38 registry files on a one-second tick. The epoch is in the file because Lua has
  no stat
- `~/.claude/fleet/notes.tsv`       cc-note: `sid, at, flags, progress, status`, one line
  per annotated session. Read by the statusLine, cc-fleet and the tab bar, so every field
  is written with a `-` placeholder rather than left empty: tab is IFS whitespace and an
  empty column folds into its neighbour
- `~/.claude/fleet/todo/<sid>`, `~/.claude/fleet/log/<sid>`  read only on demand, never
  by anything on a timer
- `~/.claude/fleet/handover/<name>-<stamp>.md`  the briefs cc-handover writes

`statusUpdatedAt` in the registry is when a session's last request finished, so it is the
clock the prompt cache runs on (`CACHE_TTL`, an hour). A transcript's mtime looks like the
same thing and is not - they get appended to long after the last exchange, and by that
measure every session on the machine looks warm. One jq over every registry file is 5ms;
a tail and a jq per session is half a second.

## where the rest of it is

This file is the map and the rules. Everything that is reasoning rather than instruction
lives in `docs/`, because this one is read into the context of every session that opens
this repo and most of them are not here to change the colour system.

- `docs/colour.md`   the two channels, the pane tint, the palette, and four false starts
- `docs/cc-board.md` the board, and how the tab bar divides its width
- `docs/tools.md`    wz, cc-note, cc-handover, cc-spawn, and what each is for
- `docs/cost.md`     where the time and the tokens go, measured
- `docs/findings-2026-09.md`  what else is out there, and what of it is worth taking
- `docs/research/`   the raw agent reports behind that survey, kept because they carry
  payload shapes and URLs the distillation drops

## what it costs, in one paragraph

The human-facing surfaces are cheap and cache in the right places. The agent-facing ones
were not: resolving a session name went through `cc-peers`, which works out a title for
every session before answering, so `wz read <name>` cost 1462ms against 22ms for the same
read by pane id. `cc-roster` is the titleless half and everything resolves through it now
(1435ms -> 130ms for cc-peers, 1462 -> 95 for wz).

Tokens are the other budget and the one that is paid per turn rather than per keypress.
`cc-fleet` was 55% escape codes when piped, which is invisible to a human and about 960
tokens of noise to a session reading it, so it only colours a tty now. `cc-fleet --brief`
answers "what wants me" in about 18 tokens against the dashboard's 767 and `--json`'s
1958. Prefer it. Numbers and method in `docs/cost.md`.

## measured dead ends

Do not go looking again.

- **`luajit` is not a syntax checker for `wezterm.lua`.** It is Lua 5.1 and the file uses
  `//` and `utf8`. Nor is `wezterm cli list`: it exits 0 and prints nothing on a config
  that raises. The check is `wezterm --config-file wezterm.lua ls-fonts 2>&1 | grep ERROR`,
  which reports runtime errors and unknown `config_builder` fields alike. The same trick
  runs any Lua 5.4 snippet: `wezterm.log_error` from a scratch config shows up there.
- **`terminalSequence` will not rescue OSC 1337 either.** Claude Code hooks can return a
  `terminalSequence` field and have it written to the pane with no controlling terminal,
  which looks like the missing half of the bridge below. It is not: the allowlist is OSC
  0/1/2, 9, 99, 777 and BEL, and 1337 is not on it. OSC 9 through that field is the
  supported way to raise a toast from a hook, and needs no tty.
- **`claude agents --json` is not a second source of state.** For interactive sessions it
  is the registry and nothing else: byte-identical on `status`, `waitingFor`, `name`, `cwd`
  and `pid` over three back-to-back runs, at 120-180ms against under 10ms for one jq over
  the same 38 files. It earns its keep for background sessions, which have **no registry file
  at all** and live in `~/.claude/jobs/<id>/state.json`. Nothing here reads those yet.
- **OSC 1337 `SetUserVar` does nothing on this build** (wezterm 20260803). It is the
  obvious CLI-to-Lua bridge and it is not there: no `user-var-changed` event fires and
  `pane:get_user_vars()` stays empty, from inside the pane and from outside it, with
  either terminator. The byte path is fine - an `OSC 0` title write down the same tty
  lands and shows up in `cli list` - so it is the sequence that is unhandled, not the
  write. The bridge that does work is a file drained by the `update-status` handler,
  which already runs once a second.

## rules for editing these

- **two sources of pane state, one precedence.** The hooks fire on edges and are blind to
  anything that happens without one, an Esc or a turn that quietly died; the registry is
  level-triggered and clears itself when a question is answered, but reads idle for a turn
  that was killed, exactly as it does for one that finished. Every reader merges both, in
  the order written out above `pane_status` in wezterm.lua, and **an idle registry never
  overrules a hook record that says errored or parked**, because idle is what both of
  those look like from outside. Do not add a third source: `wezterm cli get-text` on a
  timer buys nothing either of these does not already say, and both wrong answers this
  system was showing came from having only one of them
- **bash 3.2** (macOS): no mapfile, no `${var,,}`, no associative arrays, `read -t` whole
  seconds only. Its parser mistakes a `case` pattern's `)` for the end of an enclosing `$( )`
  or `< <( )` - hoist such a case into a function
- **awk is 20200816 and byte-based**: a bracket expression of multibyte glyphs matches their
  individual bytes and strips one, corrupting the line. No `\x` escapes in regexes. Match
  multibyte text as a literal sequence, or do it in the shell
- lookup tables go in variables named after the key (`printf -v "hk_$k"`, read `${!k:-}`),
  not in one `|k=v|` string. `${map#*"|$k="}` matches character by character in a UTF-8
  locale, so it costs the whole map per call - about 1ms on a 2KB one, and 69 of those per
  scan was 100ms. Keep a list of the names and `unset` them before each rebuild
- **never a pattern substitution on a long string.** `${rows//[$'\n']/}` as an emptiness
  test walked a 4KB string character by character under a UTF-8 locale and cost 3.3s of
  cc-peers' 3.7. Plain `-z`. The same expansion on a *short* string is the right tool and
  beats a fork: `${cwd//[^A-Za-z0-9]/-}` builds a transcript slug 12x faster than the
  `sed` it replaced, with identical output
- **`local a=$1 b="$x/$a"` does not see `a`.** bash 3.2 declares every name in one `local`
  before assigning any of them, so the second expansion gets a local that is still unset
  and `set -u` kills the script. Split the declaration
- **no apostrophes inside a single-quoted awk program.** A comment saying "the hook's
  detail" closes the string, and the error surfaces as a bash syntax error on a line of
  awk twenty lines further down
- `${#var}` counts characters under en_GB.UTF-8, so display width needs no external help.
  **Keep the render path fork-free**: `printf -v` and globals, never command substitution.
  Shelling out to tr/wc for width was a thousand forks a frame and visibly flickered
- `tput cols` inside a command substitution loses the tty and reports 80x24. `stty size </dev/tty`
- build the frame into one string, write it only when it differs, repaint with `\033[K` per
  line and `\033[J` at the end. Never a clear-screen
- `wezterm cli list` reports `tab_id`, not the tab number. The tab bar and LEADER+1..9 count
  positions from one; ascending tab_id within a window is that order
- greys: RULE #585b70 for things that are not text (dividers, empty bar cells), FAINT #7f849c
  and DIM #9399b2 for text. Anything below overlay1 is unreadable on Mocha - surface1 on the
  base background is 1.8:1, and 1.0:1 on a marked row
- **every script needs both symlinks**, `~/.claude/bin/<name>` and `~/.local/bin/<name>`.
  Only the second is on PATH. cc-fleet, cc-board and cc-colour were missing theirs until
  2026-08-26 and cc-tint until 2026-09-04, and the failure is silent: wezterm.lua and the
  hooks call these by full path, so everything keeps working and only a bare call from a
  shell - or from Claude - says "command not found"
- no em-dashes in anything on screen

## do not

- `pane:split{ top_level = true }`. wezterm redistributes the reclaimed width unevenly and
  wedged a 4-pane tab: three panes collapsed to 1 column, further splits failed with "No
  space for split!", and only a window resize cleared it
- start a Claude session with `wezterm cli spawn -- claude` directly. It inherits
  CLAUDE_CODE_CHILD_SESSION from whatever launched it and saves no transcript, which
  costs it a title, a name, a statusLine and any chance of being handed over, and says
  so only in one line of warning nobody reads. `cc-spawn`; see `docs/tools.md`
- change what LEADER+b does without asking. Settled: a left split of the tab's leftmost
  pane (the focused one if that is too narrow), then zoomed; if the tab has nothing live
  in it, run in place

## testing

    CC_BOARD_SIZE=44x50 cc-board --once LCA     ROWSxCOLS, not the other way round
    cc-board --once --rows|--grid|--all
    cc-board --tsv --all                        what the wezterm pickers read, 10 fields

`pane_status` is testable without the GUI, and worth testing, because it is now a
precedence over two sources rather than a lookup: lift its block plus `digest_rows` and
`read_pane_state` out of wezterm.lua with a `wezterm = { home_dir }` stub, point the two
path locals at a temp dir, and drive it from a table of planted digest rows and state
files under luajit. Nine cases covered the ordering when it was written. The fixtures are
time-relative, so regenerate them each run rather than leaving them on disk.

`match_name` in cc-roster is the same shape of thing and tests the same way: lift it out
with `sed -n '/^match_name()/,/^}/p'`, set `US`, and feed it planted ten-field rows. Eight
cases when it was written, and the two that matter are a current name beating a former one
and a former name two live sessions share resolving to neither.

Check nothing overflows: strip the ANSI and measure with Python, not awk - awk counts bytes
and every glyph here is multibyte. The interactive loop needs a real pty to test; drive it
with `pty.fork()` and split the captured output on `\x1b[H` to get a frame at a time.

Attribution: none, per ~/personal/CLAUDE.md.
