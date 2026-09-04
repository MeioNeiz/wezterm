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

wezterm.lua reads the scripts through their ~/.claude/bin paths, so the links matter.

`~/.claude/statusline.sh` is not in here but sources `cc-colour`, so it moves with the
palette.

State the scripts read, none of it theirs:
- `~/.claude/sessions/<pid>.json`   registry, written by Claude. name, status, cwd, session id
- `~/.claude/wezterm-sessions/<pane>`  pane -> session id, SessionStart hook
- `~/.claude/wezterm-state/<pane>`     `state\tepoch\tdetail`, Stop + Notification hooks
- `~/.claude/history.jsonl`         every prompt I have sent, for the age column
- `~/.claude/cache/fleet-rows`      cc-fleet's row cache, 8s
- `~/.claude/session-colours`       hand-pinned hues, `<session-id>\t<hue>`, cc-colour

State these scripts write themselves, all of it theirs:
- `~/.claude/cache/wz-events.jsonl` wz's event log, and `wz-events.pid` beside it
- `~/.claude/session-colours-auto`  same format as the hand pins, written by cc-tint when a
  new session would have reused the colour of the one it replaced. Hand pins win
- `~/.claude/cache/cc-tint-painted/<pane>`  `<session-id>\t<hue>`, what cc-tint last painted
  onto that pane. There is no reading a pane's colour back, so this is the only record
- `~/.claude/cache/titles/<sid>`    `mtime\x1fchecked_at\x1ftitle`, cc-peers' title memo
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

## what it costs

Measured on a machine with 59 panes and 33 live sessions, because every one of these
runs against the whole fleet and none of them is interesting at n=1.

| path | when | cost |
|---|---|---|
| `statusline.sh` | 0.51/s across the machine | 20-100ms |
| `wezterm-pane-state.sh` | 4 per turn | 10ms |
| `cc-tint` | SessionStart | 30ms |
| the tab bar | 1/s over 59 panes | 1.2% CPU, 124MB RSS |
| `cc-roster` | every `wz` call with a name | 90ms |
| `cc-peers` | humans, and cc-fleet | 130ms |
| `cc-fleet --fresh` | the board's third frame | 220ms |
| `wz read <pane-id>` | - | 20ms |
| `wz read <name>` | the agent path | 95ms |

The human-facing surfaces were never the problem: they cache in the right places and
the Lua side repaints only on invalidation. **The agent-facing path was**, and it was
65x more expensive than it needed to be - `wz read <name>` cost 1462ms against 22ms for
the same read by pane id, because resolving a name went through `cc-peers`, which works
out a title for every session on the machine before answering.

That matters more than it looks. An agent that can check the fleet in 90ms checks it
mid-task; one that costs 1.4s a call does not bother, and then reasons from memory.

Where the 1.4s went, and what replaced it:

- **a jq per registry file.** 34 forks, 76ms. One jq over all of them is 6ms.
- **an `ls -t` over the pane map per session.** 66ms. Reverse the map once instead.
- **`$(<file)` per pane-map and state file.** A command substitution forks a subshell on
  bash 3.2, and 200 of them was 114ms. One `awk` over every file is 10ms.
- **a title per session**, which is a 256KB transcript tail, an awk and a jq each, for a
  string that changes about twice in a session's life. Memoised in
  `~/.claude/cache/titles/<sid>` as `mtime\x1fchecked_at\x1ftitle`, and reused unless
  the transcript has actually moved. An untitled memo is never reused: holding
  "untitled" for a minute is the difference between a new pane naming itself and a new
  pane looking broken.

So `cc-roster` is the cheap half - who is alive, what state, which pane, no titles - and
`cc-peers` is that plus the memoised title. `wz` resolves through `cc-roster --pane`,
which skips the hook state files too.

**`waiting` is a registry status** that Claude started writing after these readers were
built, and it means the session has stopped and wants an answer; `waitingFor` says what
("input needed"). `cc-fleet`'s rank table did not know the word, so it scored 0 - the one
session on the machine that actually wanted attention sorted below thirty idle ones and
drew in the dimmest grey. It ranks with `asking` now. Anything else that switches on a
state string has to be told about it too.

## measured dead ends

Do not go looking again.

- **`luajit` is not a syntax checker for `wezterm.lua`.** It is Lua 5.1 and the file uses
  `//`, so it fails at the first integer division with "unexpected symbol near '/'" -
  at HEAD, and on any edit, which makes it look like whatever you just changed. The real
  check is `wezterm cli list`, which evaluates the config in the CLI process. luajit is
  still right for the *identity block* extracted on its own, which is what it is for.
- **OSC 1337 `SetUserVar` does nothing on this build** (wezterm 20260803). It is the
  obvious CLI-to-Lua bridge and it is not there: no `user-var-changed` event fires and
  `pane:get_user_vars()` stays empty, from inside the pane and from outside it, with
  either terminator. The byte path is fine - an `OSC 0` title write down the same tty
  lands and shows up in `cli list` - so it is the sequence that is unhandled, not the
  write. The bridge that does work is a file drained by the `update-status` handler,
  which already runs once a second.

## two colour channels, and why they cannot be one

Status answers "what does this pane want". Identity answers "which pane is this". They are
told apart by **what carries them**, not by hue:

| surface | status | identity |
|---|---|---|
| the pane itself | - | background hue, cursor, selection (OSC, see below) |
| statusLine | the context % when it warns | the whole line: title bright, metadata muted |
| tab bar | the dot in front of each label | the label text |
| cc-board | state glyph, topic, asking-mauve | name column, cursor, address line |
| cc-fleet, LEADER+; picker | state glyph | name column |
| window status bar | - | the workspace name, from the focused pane |

**Status is a dot.** Only asking and fresh get a shape of their own (`?`, `✓`); everything
else is the same `●` in a different colour. Giving each state its own glyph was tried and it
looked like punctuation - a tab of four panes has to read as one row, and that only happens
when the shape is constant and the colour varies. The bar, `cc-board` and its strip all
use the one alphabet; the board adds `›` for a shell pane, which the bar never sees. Fresh
ages out at 90s in both (`FRESH_SECONDS`, `FRESH_SECS`), and waiting is `#ffd7af` against
fresh's `#f9e2af`, so copying the glyphs without the hues would leave `✓` and `●` both yellow.

### colouring the inside of a pane

wezterm has no per-pane colour setting: `colors`, `inactive_pane_hsb` and `colors.split` are
all global and there is no pane equivalent. But every pane is a separate terminal emulator
with its own palette, and a terminal's palette is settable by the program in it - so an OSC
sequence written to one pane's tty (`wezterm cli list` gives `tty_name`) moves that pane and
nothing else. `bin/cc-tint` does this on SessionStart; `--all` catches panes already running,
`--level off|whisper|faint|subtle|full` dials it, `--reset` undoes it.

**A hook cannot paint its own pane through `/dev/tty`.** Claude Code runs hooks detached
from the pane: `tty` reports "not a tty", the open of `/dev/tty` fails and `ps -o sess=` is
0. The write fails silently, which is exactly what `paint`'s `2>/dev/null` exists to absorb
for panes that have genuinely gone, so hook mode painted nothing at all from the day it was
written and every colour on screen came from a manual `--all`. Hook mode now looks its own
tty up by pane id (`pane_tty`) the way `--all` does, and pays one `wezterm cli list` at
session start.

It hid for so long because **a pane's palette belongs to the pane and outlives the program
in it**: an unpainted session inherits whatever the last one left, so a missed paint reads
as the wrong colour and never as no colour. `/clear` is the everyday trigger. It mints a new
session id, so the statusLine and the tab bar rehue on the spot while the ground kept the
old session's hue, and the two channels disagree until something repaints. Anything that
changes identity without a session start has the same shape, which is why `cc-colour --pin`
and `--unpin` now call `cc-tint --all`: every other surface re-reads the pins on a timer,
a painted pane re-reads nothing.

Two mechanisms that turned out not to be it, measured, so do not go looking again: a split
does **not** inherit its parent's palette (a child of a green pane comes up `#1e1e2e`), and
a config reload does **not** clear an OSC paint.

**Reading a pane's palette back** is the only way to check any of this - wezterm exposes no
colour in `cli list --format json`, and there is no Lua getter. Query OSC 11 with `?` and
read the reply off the tty. It only works from inside the pane, and the reply arrives on the
pane's *stdin*, so never point it at a live Claude pane: it types the answer into the input
box. Give it a pane of its own.

    wezterm cli spawn --new-window --cwd /tmp -- bash -c '
      stty raw -echo
      printf "\033]11;?\033\\" >/dev/tty
      IFS= read -r -s -t 1 -d "\\" r </dev/tty
      stty sane; printf "%s" "$r" >/tmp/bg'

`stty raw` is not optional: in canonical mode the reply has no newline, so nothing is
readable. Read with bash's `read -t` and nothing else - there is **no `timeout` on this
machine** (no coreutils, and no `gtimeout`), and a `cat` killed mid-read loses its pipe
buffer, so both of the obvious ways to bound the read return empty and look like "the
terminal does not answer queries".

**Ground and text rotate together, and that is the whole trick.** What strains the eye is not
a coloured background, it is the chromatic edge between ground and text at every glyph
boundary - and the eye localises a yellow-blue edge about three times worse than a luminance
or red-green one (Wuerger, Owens & Westland, JOSA A 18(6):1231, 2001). Catppuccin's ground is
deliberately hue-matched to its text: #cdd6f4 on #1e1e2e is |d(a,b)| = 0.0142 in Oklab,
almost a pure lightness edge. Rotate the ground alone and every glyph edge lands on the eye's
worst axis, 2.0x to 4.1x baseline. Rotate the text with it and the match is restored: the
shipped pairs run 0.92x to 0.97x, so **every pane is more comfortable than plain #1e1e2e**.

This works here only because Claude Code emits no truecolor and no 256-index colour at all -
343 `SGR 39` (default foreground) against a single dim attribute across twelve live panes. So
OSC 10 moves essentially all of its text, and `SGR 2` dim follows the default foreground for
free. Check that again before trusting this if Claude's rendering ever changes:

    wezterm cli get-text --pane-id N --escapes | grep -o $'\033\[[0-9;]*m' | sort | uniq -c

**The counter-intuitive part: de-chroma toward neutral makes it worse.** A neutral grey at the
same lightness scores 0.0426, 3.0x baseline - worse than six of the nine tints it would be
meant to calm. #1e1e2e is not a grey. Do not "calm" this by reducing chroma.

Levels trade identity, not comfort: worst edge is 0.97x baseline at whisper and 0.92x at full,
while the smallest gap between two grounds goes 1.9 -> 5.4 dE. So `full` is simultaneously the
most distinguishable and the most comfortable, and is the default.

### four false starts worth not repeating

- **a solid block `▉` in its own column, in a saturated palette.** A block is a thing you
  look at rather than something the eye catches in passing, and the saturation it needed in
  order not to be mistaken for status looked garish beside Catppuccin.
- **colour on the statusLine title alone.** Not enough of it; the metadata after it was grey
  and grey was carrying nothing.
- **identity on a tinted chip behind each tab label, with a glyph per status.** Two washes and
  five shapes at once, and it buried the row of status dots that already worked. A tab of four
  panes only reads as a row when the shape is constant and the colour varies.
- **three goes at the pane background before getting it right**: 7% mixed in (raised
  luminance, put Claude's dim text under the floor); 45% mixed in with luminance renormalised
  (contrast provably untouched, still strained, because luminance parity says nothing about
  the chromatic edge); then chroma *reduced* toward neutral to calm it, which is the wrong
  direction entirely. Measuring WCAG or APCA will not find any of this - both are
  luminance-only. Use |d(a,b)| in Oklab between ground and text.

### the palette

Nine Mocha accents in four variants. Full for text; **muted** for metadata, each pinned to
3.6:1 so swapping grey for colour changes the hue and not the weight (a flat mix put mauve
at 2.8 and teal at 5.2); **tint** for a pane background at constant luminance; **sel** for
a selection ground.

Not fourteen accents: rosewater and flamingo read as ordinary text, red reads as an error,
lavender sits too close to blue in a title (dE 11). The nine left are each ≥20 dE from one
another and from the text greys.

Nine hues over forty sessions, so a colour is a hint and not an identifier. `cc-board` flags
a tab where two panes share one (`tab 1 · 4 · 2 alike`) and names the hue in the block under
the cursor, which is what `cc-colour --pin d5-lca-48 teal` wants. Assignment is otherwise
the first 8 hex of the session id mod nine - stateless, so every reader agrees without
coordinating, and a colour survives /rename, --resume and a reboot. It also tells apart two
panes that share a name, which happens.

### a new session has to look like a new session

The hash alone does not deliver that. The nine tints are one hue ring at a single lightness,
so how far apart two grounds look is a function of ring distance and nothing else: adjacent
is 1.64 to 2.89 dE in Oklab, two steps 3.23 to 4.37, three steps 4.83 to 6.24. One to two dE
is where two colours that touch stop being tellable apart, so on a fresh hash a new session
in a pane lands on a ground you cannot tell from the one it replaced **21% of the time, 31%
on an unfocused pane**, against the 11% an exact hue collision would suggest. `/clear` is the
usual way to meet it, since it mints a new session id.

So a new session in a pane that already had one is held at least `ID_MIN_RING` = 3 hues away
from the colour it is replacing (`id_rehue`), which is 4.83 dE at worst - unmistakable rather
than merely different. Four hues sit at three or four steps and which of them is taken comes
out of the id, so a colour is still a property of the session and not of the order sessions
started in. Dial the constant to 2 for a gentler rule; on a ring of nine, 3 rehues 5 slots in
9, so **56% of new sessions take a hue other than their hash**.

Three things this must not break, and does not:

- **stateless agreement.** A rehue cannot be derived by a reader, since it depends on what
  the *pane* was wearing, so it is written to `~/.claude/session-colours-auto` in the pin
  format and every reader that resolves a hue already honours pins. A hand pin for the same
  id wins. `cc-colour --pins` and the file you edit stay yours.
- **a colour surviving --resume.** `id_rehue` is idempotent per id: a session that has been
  rehued once is pinned and keeps that hue, and a resume or a compact fires SessionStart with
  the *same* id, so the rule sees `prev_sid == sid` and does nothing. The one edge: the auto
  file is pruned of ended sessions once it passes 50 lines, because it is read on every
  statusLine render, so a session resumed long after it ended can take a fresh hue.
- **which colour a pane is actually wearing.** The rule needs the hue being replaced, and
  the map file cannot answer it (a sibling hook may already have overwritten it, and it says
  what session is there rather than what was painted). `cc-tint` records its own paints in
  `~/.claude/cache/cc-tint-painted/<pane>`, wiped with the other pane-keyed state on
  gui-startup - a record from the previous mux would have a new session in pane 3 avoid the
  colour that the *old* pane 3 was wearing.

`wezterm.lua` re-reads the pin files every 3s rather than every 10, and a change bumps a
generation that invalidates the resolved-colour cache: the timer is exactly how long the tab
label can disagree with the ground, and that disagreement at the moment you start a session
is the thing this is all for.

The palette lives twice, in `bin/cc-colour` and in `wezterm.lua` (`TAB_IDENTITY`), because
one is bash and the other Lua. **They have to agree.** Check it:

    python3 - <<'EOF'
    import re, subprocess, os, glob
    lua = open('wezterm.lua').read()
    fg = re.findall(r'"(#[0-9a-f]{6})"',
         re.search(r'local TAB_IDENTITY = \{(.*?)\}', lua, re.S).group(1))
    home = os.path.expanduser('~/.claude')
    pinned = {l.split('\t')[0]
              for f in ('session-colours', 'session-colours-auto')
              for l in open(f'{home}/{f}').read().splitlines() if l.strip()}
    for line in subprocess.run(['./bin/cc-colour','--all'], capture_output=True,
                               text=True).stdout.strip().split('\n'):
        sid = line.split()[-1]
        if sid in pinned:   # a pin is meant to override the hash
            continue
        assert fg[int(sid[:8],16) % len(fg)] == subprocess.run(
            ['./bin/cc-colour','--hex',sid], capture_output=True, text=True).stdout.strip()
    EOF

The hash is only half of it now. To check the two agree on a *pinned* id, which is the half
that has no shared code at all, drive the Lua directly: there is a `luajit` on this machine,
and the identity block extracted out of `wezterm.lua` runs under it with three stubs
(`wezterm.home_dir`, `read_session_id`, `TESTHOME`). Rotate a pin file so no id's pin equals
its own hash, or the test passes without proving anything.

## wz

The cc-* scripts answer "which chats want me". `wz` answers "what is in that pane, and make
it do something", which is the half a Claude session needs and could only get before by
composing four `wezterm cli` calls and getting the quoting right.

Nothing in it is a new capability. `wezterm cli` could always do this; what it could not do
was make it cheap enough to reach for mid-task. The parts worth knowing:

- **`grep` and `top` are the two that did not exist in any form.** `wezterm cli list`
  reports no pid, so per-pane CPU comes from joining `tty_name` against one `ps -ax` for the
  whole machine. A `ps -t` per pane would cost more than everything else here put together.
- **Targets resolve through `cc-roster`**, so `wz read d5-lca-48` takes the same address
  SendMessage does. `resolve` asserts the answer is digits before returning: a pane id
  reaches `kill-pane` and once reached an `rm`, and nothing downstream should have to wonder.
  It used to go through cc-peers and cost 1.4s a call; see "what it costs".
- **The event log is polled, not pushed.** wezterm has no outbound event stream, and the
  states worth waking up for (busy, asking, idle) are Claude's rather than wezterm's, so
  they would not appear in one if it existed. `wz events --daemon` diffs a five-field
  snapshot every two seconds. `--cursor-file` makes a reader resumable.
- **`wait --state` deliberately does not use that log.** It polls cc-peers, so it works with
  no daemon running, and cc-peers is what knows "asking" from "idle" in the first place.
- **`pipe` line-diffs a screen**, so it only reads cleanly for output that scrolls. A
  full-screen TUI repaints in place and its "new" lines are whatever the redraw touched.
  Fine for a shell or a log, useless pointed at another Claude pane.

Not built, and why: there is no `swap-pane` or `respawn-pane` because wezterm has no
primitive for either. There is no status/notes store because nothing would render it; that
wants a statusline change in this file, and it should wait until the tab bar work lands.

Truncation happens in bash, never in awk. See the awk rule below: `substr` cuts a multibyte
glyph in half and every tab title starts with one.

## the writable layer

Everything else here is derived: the registry is Claude's, the hook files are Claude's,
the transcript is Claude's. None of them can hold "waiting on the DNS change", "step 3 of
7" or "leave this one alone", which is what `cc-note` is for.

Keyed by session id rather than by pane, so a note follows the conversation through a
pane move, a `--resume` and a reboot - and `/clear` mints a new id, which is exactly when
a note should stop applying. `CLAUDE_CODE_SESSION_ID` is set in every session's shell, so
a session annotating itself costs no lookup at all.

It renders in three places and deliberately not in a fourth:

- **the statusLine**, straight after the title, because the far end of the line is where
  a narrow pane truncates and a note the session left for itself outranks the branch it
  is on. Read with a bash loop rather than a grep - this path stays fork-free.
- **cc-fleet**, where a status note takes the topic column: it is newer than the topic
  Claude derived and it says what is actually holding the work up. Read at render time
  rather than folded into `assemble_rows`, because that result is cached for eight
  seconds and a note is the one field you change and expect to see immediately.
- **the window status bar**, where `mute` means a session stops counting towards the
  "wants you elsewhere" marker. That marker exists to catch a blocked pane in a workspace
  you are not looking at; one you have already decided to leave is noise in the place
  noise is most expensive.
- **not the tab bar.** Four false starts up there are documented above and every one of
  them was adding a channel. Progress and status have somewhere better to live.

## handing work over

`cc-handover` is the one that earns its place daily. The manual version is scrolling back
and copying the last message into a fresh pane, which loses what was actually asked, what
was said mid-turn, the branch, the files it had open, and everything the session recorded
for itself. All of that is already on disk.

Two things that are not obvious and cost a while to find:

- **a session spawned from inside another inherits its whole Claude environment**, and
  `CLAUDE_CODE_CHILD_SESSION` turns transcript saving off. The child then has no
  transcript, so it never gets a title, `cc-peers` cannot name it, its statusLine has
  nothing to show, and it can never be handed over itself - which is the one thing the
  script exists to prevent. It announces itself as one line of warning in a pane nobody
  is watching. `cc-spawn` clears the environment, and is why every launcher goes through
  it rather than calling `wezterm cli spawn -- claude` directly.
- **a message typed while a turn is running is a `queue-operation` record**, not a user
  turn, so every "last prompt" reader is blind to it. It is usually the steer that
  changed what the work was. The brief carries everything queued since the last real
  prompt, in order.

Also: the `last-prompt` record beside the transcript is Claude's own UI copy and arrives
already truncated with an ellipsis, so the brief greps the whole file for the last real
user turn instead. One grep over a 1.4MB transcript is 13ms; the tail is no good here
because a long turn pushes the prompt that started it well past 400KB back.

`wezterm cli spawn -- <argv>` passes arguments straight to exec with no shell in between,
so a multi-KB markdown brief with newlines, backticks and quotes in it arrives
byte-identical. Checked, because the obvious assumption is that it would not.

## the tab bar

Label width is **one number per window**, not a share per tab. `label_width` takes what is
left after chrome, prefixes and dividers and divides it by the panes on the bar, capped at a
whole topic each. Every label in a window is therefore the same width.

The predecessor shared the bar per tab, weighted by pane count, and then divided by pane
count again. Every part of that was defensible - a 4-way split has four topics to name, the
tab you are looking at is worth more room - and the result was the same topic at 13 cells in
one tab and 18 in the next, for reasons invisible from the bar. Consistency turned out to be
worth more than fairness. An active-tab bonus was tried too and was worse still: it made the
whole bar reflow every time you changed tab.

Three things had also been quietly throwing space away:

- **two caps on the same number.** `SOLO_BUDGET` capped a label while the share was also
  capping it, so a window with one tab and four hundred spare columns still wrote
  `Audit and sync HubSp…`. 52 -> 96, and it is the only ceiling now.
- **`tab_max_width` at 160**, which bound before the bar did in every wide window. 320.
- **`TAB_CHROME` at 8**, on the reasoning that unused bar is harmless. True in a two-tab
  window, false in a ten-tab one where it claimed 80 of 111 columns. 5, plus
  `show_close_tab_button = false` for another two a tab. Raise it if tabs start clipping,
  which is the failure it exists to avoid.

Together: 47 -> 96 cells in the wide windows, and zero spread within every window.

What is still not solved: ten tabs in a 111 column window cannot show topics at all - the
`N: ` prefixes alone are 50 of those columns. It renders as a row of status dots, which is
the honest answer, and identity is carried by the pane tint instead.

## the point of cc-board

Only a pane read can tell a session that finished from one that stopped to ask a question:
the Stop hook fires either way, so the tab bar and cc-fleet show both the same. cc-board
reads `wezterm cli get-text` and flags a closing line ending in `?`. Do not lose that.

Two views by width. Grid above 88 columns, rows below, `v` toggles where both fit. Rows put
identity and state on the line and everything that needs a sentence in the block that opens
under the cursor, which is why it survives a 50 column split.

Loads in three frames: `wezterm cli list` + the hook maps (~40ms, navigable), then the pane
reads (~150ms, bars and closing lines), then the roster (names and ages only, and it goes to
the background if its cache is cold). Never make the first frame wait on the roster.

**Two clocks, and which is which.** The age column counts from *your last prompt*, out of
`history.jsonl` via the roster. The column beside it is when the session stopped, and it is
the epoch in `wezterm-state/<pane>` - the same instant Claude prints as `done 16:40` at the
foot of its own pane, to the minute. `statusUpdatedAt` is the fallback for a session no hook
ever wrote for. Nothing at all while a session is working: a start time under a "done"
heading would be a lie, and a blank cell there means working and nothing else does.

Formatted by arithmetic on `TZOFF`, never by a `date` fork - `stamp_now` takes NOW and the
local offset in one call. So a timestamp from the far side of a DST change reads an hour out,
which moves a day name never and a clock face only on the two days a year after one.

**The hook files outrank the roster.** `merge_roster` used to take the roster's state
unconditionally, and the roster is `cc-fleet`'s cache of the registry - eight seconds old at
best and, on the `--stale-ok` path every interactive caller uses, older than that by however
long the rebuild takes. A session that had just stopped went on showing as working until the
cache caught up. Now the roster names the state only where no hook wrote after the roster was
assembled (`ROSTER_AT`, the cache file's mtime, stamped *before* the fetch because
`--stale-ok` rewrites the file behind you). The stale-hook case still corrects itself: a hook
that stopped firing has an epoch that only falls further behind.

**Every frame has to fit its pane.** The grid wrote every cell it had and left the pane to
cope, which for a fleet of thirty is seventy lines: in any shorter pane the top scrolled off
the alternate screen, and once it had, `ESC[H` no longer addressed the first line of the
frame, so the in-place repaint painted over the wrong rows and left the last minute's text
standing. It reads as "it did not load" and as "the status is out of date" and it is one bug.
The grid now clips like the rows do, snapping the window to whole cells through `LINE_POS`,
and group headings clip to the width - a hand-named tab could overrun a narrow board and a
heading that wraps costs a line, which puts every row under it one out of place. `?` clips
too, dropping the notes before the keys. Check both axes after touching a layout:

    python3 - <<'EOF'
    import subprocess, re, os
    ansi = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
    for h in (14, 24, 44):
        for w in (30, 44, 64, 88, 96, 120, 180):
            for view in ('--rows', '--grid'):
                env = dict(os.environ, CC_BOARD_SIZE=f"{h}x{w}")
                out = subprocess.run(['./bin/cc-board', '--once', view],
                                     capture_output=True, text=True, env=env).stdout
                lines = [ansi.sub('', l) for l in out.split('\n')]
                if lines and lines[-1] == '': lines = lines[:-1]
                assert len(lines) <= h and max(map(len, lines)) <= w, (h, w, view)
    EOF

## rules for editing these

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
- change what LEADER+b does without asking. Settled after three goes: left split of the
  focused pane, unzoomed; if the tab has nothing live in it, run in place

## testing

    CC_BOARD_SIZE=44x50 cc-board --once LCA     ROWSxCOLS, not the other way round
    cc-board --once --rows|--grid|--all
    cc-board --tsv --all                        what the wezterm pickers read, 10 fields

Check nothing overflows: strip the ANSI and measure with Python, not awk - awk counts bytes
and every glyph here is multibyte. The interactive loop needs a real pty to test; drive it
with `pty.fork()` and split the captured output on `\x1b[H` to get a frame at a time.

Attribution: none, per ~/personal/CLAUDE.md.
