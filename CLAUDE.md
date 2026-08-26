# wezterm + the cc-* fleet scripts

Everything here is symlinked into place, so edit the file in this repo, not the link:

    wezterm.lua   <- ~/.wezterm.lua
    bin/cc-peers  <- ~/.claude/bin/cc-peers    roster of live Claude sessions
    bin/cc-fleet  <- ~/.claude/bin/cc-fleet    same, grouped by workspace, aged by my prompts
    bin/cc-board  <- ~/.claude/bin/cc-board    the board: LEADER+b

wezterm.lua reads the scripts through their ~/.claude/bin paths, so the links matter.

State the scripts read, none of it theirs:
- `~/.claude/sessions/<pid>.json`   registry, written by Claude. name, status, cwd, session id
- `~/.claude/wezterm-sessions/<pane>`  pane -> session id, SessionStart hook
- `~/.claude/wezterm-state/<pane>`     `state\tepoch\tdetail`, Stop + Notification hooks
- `~/.claude/history.jsonl`         every prompt I have sent, for the age column
- `~/.claude/cache/fleet-rows`      cc-fleet's row cache, 8s

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

## rules for editing these

- **bash 3.2** (macOS): no mapfile, no `${var,,}`, no associative arrays, `read -t` whole
  seconds only. Its parser mistakes a `case` pattern's `)` for the end of an enclosing `$( )`
  or `< <( )` - hoist such a case into a function
- **awk is 20200816 and byte-based**: a bracket expression of multibyte glyphs matches their
  individual bytes and strips one, corrupting the line. No `\x` escapes in regexes. Match
  multibyte text as a literal sequence, or do it in the shell
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
- no em-dashes in anything on screen

## do not

- `pane:split{ top_level = true }`. wezterm redistributes the reclaimed width unevenly and
  wedged a 4-pane tab: three panes collapsed to 1 column, further splits failed with "No
  space for split!", and only a window resize cleared it
- change what LEADER+b does without asking. Settled after three goes: left split of the
  focused pane, unzoomed; if the tab has nothing live in it, run in place

## testing

    CC_BOARD_SIZE=44x50 cc-board --once LCA     render at a size you have no pane for
    cc-board --once --rows|--grid|--all
    cc-board --tsv --all                        what the wezterm pickers read, 9 fields

Check nothing overflows: strip the ANSI and measure with Python, not awk - awk counts bytes
and every glyph here is multibyte. The interactive loop needs a real pty to test; drive it
with `pty.fork()` and split the captured output on `\x1b[H` to get a frame at a time.

Attribution: none, per ~/personal/CLAUDE.md.
