# cc-board, and the tab bar

Pointed at from CLAUDE.md.

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
