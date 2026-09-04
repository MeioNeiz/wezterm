# Colour: the two channels, the pane tint, and the palette

Pointed at from CLAUDE.md. Read this before changing anything that puts colour on a
screen; most of it is measurement rather than taste, and four of the approaches in here
were tried and abandoned.

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
