# wezterm + the cc-* fleet scripts

Only this file is always in context. `.claude/rules/` loads itself when you read a file it
covers; `.claude/context/` and `docs/` load when a task needs them (`docs/INDEX.md`).
Anything true of one area only belongs there, not here.

## the map

Everything is symlinked into place: **edit the file in this repo, never the link**.
wezterm.lua and the hooks call the scripts by their `~/.claude/bin` paths.

| repo | linked as | what |
|---|---|---|
| `wezterm.lua` | `~/.wezterm.lua` | the config: tab bar, keys, `pane_status` |
| `bin/cc-roster` | `~/.claude/bin/` | who is alive, what state, which pane; names resolve here |
| `bin/cc-peers`, `cc-fleet` | same | plus titles; grouped and aged, `--brief` |
| `bin/cc-board`, `cc-colour` | same | the board (LEADER+b); the identity palette |
| `bin/wz` | same | panes as a queryable surface, the event log, notify |
| `bin/cc-tint`, `cc-note` | same | paints a pane at SessionStart; what a session says |
| `bin/cc-spawn`, `cc-handover` | same | starts a session cleanly; moves work to a fresh one |
| `bin/ccx` | same | closes what a gather (LEADER+G) pulled in, typed `!ccx` |
| `bin/cc-sort`, `cc-watch`, `cc-handovers` | same | Kev: topic sort, output watch (off), digest |
| `bin/cc-toast` | same | built by setup.sh from `toast/`, gitignored |
| `skills/fleet` | `~/.claude/skills/fleet` | the skill sessions use to drive all of it |
| `statusline.sh`, `hooks/*` | `~/.claude/`, `~/.claude/hooks/` | the line under each pane; state |

**Every script needs both links**, `~/.claude/bin/<name>` and `~/.local/bin/<name>`; only
the second is on PATH and a missing one fails silently (full-path callers keep working).
`setup.sh` makes every link and registers the hooks, rerunnable on macOS and Linux.
macOS and Linux run everything; Windows runs the config only (`setup-windows.ps1`).

## rules for every change

- **Two sources of pane state, one precedence.** Hooks fire on edges and miss what has
  none (an Esc, a turn that died); the registry is level-triggered but reads idle for a
  killed turn exactly as for a finished one. Every reader merges both in the order above
  `pane_status` in wezterm.lua, and **an idle registry never overrules a hook record that
  says errored or parked**. Never add a third source (`get-text` on a timer buys nothing).
  Formats and who reads what: `.claude/context/state-files.md`
- **A cold session is never woken or resumed.** Cold is past `expires_at` in the context
  file, else `statusUpdatedAt` + `CACHE_TTL` (1h, in wezterm.lua, cc-board, cc-fleet,
  cc-handover, wz). `wz send`/`key` and `cc-handover --to` refuse one (`--force` is
  Jacob's), resume hints show only while warm, a cold pane restores armed with a handover.
  A successor reads the transcript and output from disk; sessions never brief each other
- A state string you switch on has to be told about every new value Claude writes
  (`waiting`, `shell` both arrived after their readers did)

## do not

- start Claude with `wezterm cli spawn -- claude`. It inherits CLAUDE_CODE_CHILD_SESSION and
  saves no transcript: no title, name, statusLine or handover. Use `cc-spawn`
- change what LEADER+b does without asking (settled; `.claude/rules/wezterm-lua.md`)

## which area are you in

| working on | start here | how it loads |
|---|---|---|
| any script in bin/, hooks/, statusline.sh, setup.sh | `.claude/rules/shell-scripts.md` | automatic |
| wezterm.lua | `.claude/rules/wezterm-lua.md` | automatic |
| the toast (toast/) | `.claude/rules/toast.md` | automatic |
| anything that draws: greys, widths, tab numbers | `.claude/rules/screen.md` | automatic |
| a state file's format, who writes and reads it | `.claude/context/state-files.md` | you read it |
| "is there a way to..." before building a bridge | `.claude/context/dead-ends.md` | you read it |
| colour, the tint, the palette | `docs/colour.md` | you read it |
| the board and tab bar widths | `docs/cc-board.md` | you read it |
| wz, cc-note, cc-handover, cc-spawn, notify, Kev's scripts | `docs/tools.md` | you read it |
| time and token costs, measured | `docs/cost.md` | you read it |
| what Claude Code and others offer | `docs/findings-2026-09.md`, `docs/research/` | you read it |

Attribution: none, per ~/personal/CLAUDE.md.
