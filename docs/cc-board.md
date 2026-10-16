# cc-board, and the tab bar

Pointed at from CLAUDE.md and docs/INDEX.md.

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

Label width comes from **whichever ceiling the live tab bar actually imposes**, and the two
bars impose different ones, so `label_width` branches on `FANCY`. Under the fancy bar the
ceiling is per tab and the panes share it between themselves; under the retro bar there is
no per-tab ceiling and every pane on the bar shares one width. Either way the panes
water-fill within their budget - a topic short enough to fit hands its surplus to one that
does not - and the cap stays a single number, so no two clipped labels ever clip at
different widths for reasons invisible from the bar.

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

Then three more, found from the other end - a nine-tab window clipping nine of ten topics
with the right third of the bar visibly empty, and a three-way split showing two of its
three panes:

- **the bar is not measured in terminal cells.** The fancy tab bar draws in
  `window_frame.font` at `window_frame.font_size`, Roboto Bold 12 by default on macOS,
  against a JetBrains Mono 14 terminal. Every width was counted in one unit and spent in
  the other, so the bar was about a fifth wider than the arithmetic believed. `FRAME_CELLS`
  converted, out of the two point sizes and the two advance widths, shaded by
  `FRAME_MARGIN` because a proportional font has no exact answer. (Since replaced by exact
  measurement, below.) The frame font is now
  pinned rather than left to the default, so a wezterm upgrade cannot move the constant's
  premise. Point it at a monospace font and both factors become 1.0.
- **a flat share cannot give space back.** `Call patching process` was handed the same 33
  cells as a 59 character topic and the twelve it could not use went nowhere. Water-filling
  spends them on the topics that are long instead.
- **the binding constraint was never in this file.** `fancy_tab_bar.rs` sets
  `elem.max_width` on every tab to `pixel_width / num_tabs - 1.5 cells`, counting the
  new-tab button in the divisor. It is not conditional on the bar being full, so a tab can
  never use more than its equal share however little its neighbours want, and *no* way of
  dividing the whole bar between panes could have reached it. That is why the two symptoms
  had two different causes: single-pane tabs were short because of the unit and the flat
  share, and the split tab was losing a pane to a ceiling nothing here knew about. It is
  also why raising `tab_max_width` to 320 changed nothing - in fancy mode wezterm sets that
  aside entirely (`tab_width_max = usize::MAX.min(tab_max_width)`).

On a 429 column nine-tab window, per label: **31 -> 41** cells for a single-pane tab, and a
three-way split went from two panes visible to three at 13 each.

**The frame font size is the width lever**, because that ceiling is in pixels: every point
off `FRAME_FONT_SIZE` is characters back, 10.0 buying 51 and 16 against 12.0's 41 and 13.
It stays at 12.0 because 10 reads too small on this display, and an unreadable tab bar is
not a wider one.

The retro bar was tried as the other way out and is a trade, not a win: no per-tab ceiling
at all while the whole bar fits, which suits a split-heavy window, but it draws in the
terminal font, so the bar holds 429 cells rather than about 508, every pane shares those,
and the text is bigger and harder to read for it. `use_fancy_tab_bar = false` switches both
the bar and `label_width`'s model, and the retro path is kept working for exactly that.

What is still not solved: ten tabs in a 111 column window cannot show topics at all - the
`N: ` prefixes alone are 50 of those columns. It renders as a row of status dots, which is
the honest answer, and identity is carried by the pane tint instead. Nor can anything here
buy a split tab more than its ninth of a nine-tab bar; that one is wezterm's rule, and the
levers on it are the frame font size, the retro bar, or fewer tabs.

## measured, not estimated (2026-10)

A 13-tab, 29-pane window (jol, 211 columns) showed the whole right half of the bar empty
and most tabs as bare dots. Every estimate above erred safe, and together they spent about
40% of each tab: the ceiling was computed off a bar shortened by the window buttons,
`PREFIX_CELLS` priced " 13: " at 5 Roboto letters when it draws as 3, and `FRAME_MARGIN`
took another tenth.

Now the fancy bar is measured in the unit it draws in. `frame.width` sums Roboto Bold's
hmtx advances (wezterm's bundled copy, ASCII 32..126, 1/2048 em; anything else is
JetBrains Mono's 0.6 em fallback), `frame.units` turns `get_dimensions()` pixels into the
same unit, and `frame.fit` cuts a label to a budget in it. The prediction matched a
screenshot to 2px. The retro bar runs the same code with every width 1.

Three things that measurement turned up:

- **`max_width` is the border box.** `box_model.rs` takes padding and border out of
  `elem.max_width` before laying out text, so the text cap is the 1.5 cells *and* the
  padding short of `pixel_width / num_tabs`. Measured where wezterm cut the text: 192px of
  a 257px share at 2x, so `tab_ceiling` takes 3 cells, and `TAB_CHROME` is 1.4 cells
  (30px a tab measured, wider than "@" would make it). Overshoot shows as a label that
  ends without its "…".
- **the right status is in the frame font too**, so `reserve` is `frame.width` of it. The
  heartbeat's NBSP is priced as a space, or every label would reflow each second.
- **a window's shared words are noise.** Half of jol's topics began "Meiolol" and a third
  ended "handover", which at a dozen letters a pane was most of every label.
  `shared_words` drops any word in at least 3 topics and a quarter of them (not stop
  words), keeping a topic whole when nothing else would be left. The pane's statusLine
  still has every word.

Fancy prefixes lost their blanks and colon (`5 ●✓`, not ` 5: ●✓ `), since the tab's
padding already separates them. A split whose labels would get under 8 letters with the
dot (`SPLIT_LABEL`) draws its dots plus the neediest pane's topic, because "●● CPU, GPU
and h…" says more than "● CP… │ ● we…". `frame.fit` keeps a word boundary only if it
costs under a tenth of the budget.

What it bought on jol: from dots or 5 letters a tab to 9 to 14 letters of topic, and
nothing clipped. The
right third stays empty because of wezterm's per-tab ceiling, which no labelling can
reach; the levers on that are unchanged (frame font size, retro bar, fewer tabs).
