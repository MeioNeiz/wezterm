---
paths:
  - "bin/**"
  - "hooks/**"
  - "statusline.sh"
  - "setup.sh"
---

# Editing the scripts and hooks

Formats of every file these read and write: `.claude/context/state-files.md`. Read it
before changing a field, a reader or a writer.

## bash 3.2 and awk 20200816 (macOS)

- No mapfile, no `${var,,}`, no associative arrays, `read -t` whole seconds only. The parser
  mistakes a `case` pattern's `)` for the end of an enclosing `$( )` or `< <( )`: hoist such
  a case into a function
- **`local a=$1 b="$x/$a"` does not see `a`.** One `local` declares every name before
  assigning any, so the second expansion meets an unset local and `set -u` kills the
  script. Split the declaration
- **Never read a tab-separated record with `IFS=$'\t' read`** when a field can be empty:
  tab is IFS whitespace and the empty field folds into its neighbour. Use `\x1f`, awk
  `-F'\t'`, or write `-` placeholders (notes.tsv, the notify log do)
- **awk is byte-based**: a bracket expression of multibyte glyphs matches their bytes and
  strips one, corrupting the line. No `\x` escapes in regexes. Match multibyte text as a
  literal sequence, or do it in the shell
- **No apostrophes inside a single-quoted awk program.** "the hook's detail" in a comment
  closes the string; the error surfaces as bash syntax twenty lines further down

## speed

- Lookup tables go in variables named after the key (`printf -v "hk_$k"`, read `${!k:-}`),
  never one `|k=v|` string: `${map#*"|$k="}` walks the whole map per call under UTF-8
  (1ms on 2KB, 69 per scan was 100ms). Keep the names in a list and `unset` before a rebuild
- **Never a pattern substitution on a long string.** `${rows//[$'\n']/}` as an emptiness
  test cost 3.3s of cc-peers' 3.7 on 4KB. Plain `-z`. On a *short* string it is the right
  tool and beats a fork: `${cwd//[^A-Za-z0-9]/-}` is 12x faster than the `sed` it replaced
- `$(<file)` and every `$( )` fork a subshell on 3.2: 200 of them was 114ms. One awk over
  every file instead. One jq over every registry file is 5ms; a jq per file is 76ms
- **The render path is fork-free**: `printf -v` and globals, never command substitution.
  Width is `${#var}` (`.claude/rules/screen.md`), never tr/wc: a thousand forks a frame
  flickered
- Build a frame into one string, write it only when it differs, repaint with `\033[K` per
  line and `\033[J` at the end. Never a clear-screen
- `tput cols` inside a command substitution loses the tty and says 80x24: `stty size
  </dev/tty`
- Anything an agent calls goes through `cc-roster`, never `cc-peers` (titles cost 1.4s)

## macOS and Linux

- BSD vs GNU is chosen once per script, never tried and fallen back (a fork per call on the
  Mac): `MTIME` for `stat`, since GNU `stat -f` means the filesystem and succeeds
- No controlling tty is `??` from macOS ps and `?` from Linux ps; match both
- A script reached from the GUI runs under launchd's `PATH=/usr/bin:/bin:/usr/sbin:/sbin`.
  Call siblings by `$HOME/.claude/bin/<name>`, never bare. Test with `env -i HOME=$HOME
  PATH=/usr/bin:/bin:/usr/sbin:/sbin <script>`
- Background `git status` takes `--no-optional-locks`, or it can fail a session's commit

## hooks

- **Nested sessions.** A `claude` run from a session's Bash tool inherits `WEZTERM_PANE`
  and fires every hook as if it owned the pane. The resident claude has the pane as its
  controlling tty and a nested one has none, so hooks and cc-tint check the nearest claude
  ancestor's tty (`ps -o tty=`) and stay out of it
- Never break the agent: a hook is detached, exits 0, and is fast (the pane-state hook is
  about 20ms; SessionEnd hooks share a 1.5s budget)
- SessionStart stays silent to the session: nothing into its context. The one exception
  is a `systemMessage` (shown to Jacob, not the model) warning that a resume is cold
- The Notification matcher (settings.json and setup.sh) must list every
  `notification_type` the hook acts on: `permission_prompt`, `push_notification`,
  `worker_permission_prompt`, `model_refusal_fallback`. A type it omits never arrives
- `hooks/claude-session-brief.py` is called by wezterm.lua too, not only by Claude
- `~/.claude/hooks/wezterm-backfill-sessions.py` stays outside the repo: nothing calls it

## testing

    CC_BOARD_SIZE=44x50 cc-board --once LCA     ROWSxCOLS, not the other way round
    cc-board --once --rows|--grid|--all
    cc-board --tsv --all                        what the wezterm pickers read, 11 fields

- `match_name` in cc-roster: lift it with `sed -n '/^match_name()/,/^}/p'`, set `US`, feed
  planted ten-field rows. The two cases that matter: a current name beats a former one, and
  a former name two live sessions share resolves to neither
- Overflow: strip the ANSI and measure with Python, not awk (bytes, and every glyph here is
  multibyte)
- The interactive board needs a real pty: drive it with `pty.fork()` and split the capture
  on `\x1b[H` for a frame at a time
- Fixtures are time-relative: regenerate them each run, in the scratchpad
