---
paths:
  - "wezterm.lua"
  - "setup-windows.ps1"
---

# Editing wezterm.lua

State it reads (the digest, hook records, context, rate limits, pane-read, actions.d):
`.claude/context/state-files.md`. Bridges already tried and dead:
`.claude/context/dead-ends.md`.

## checking it

- **The check is `wezterm --config-file wezterm.lua ls-fonts 2>&1 | grep ERROR`**: runtime
  errors and unknown `config_builder` fields alike. `wezterm cli list` exits 0 and prints
  nothing on a config that raises; `luajit` is Lua 5.1 and the file uses `//` and `utf8`
- The same trick runs any Lua 5.4 snippet: `wezterm.log_error` from a scratch config.
  Lua 5.4 traps it catches: `os.date` wants an integer (`//`, not `/`), `%` by zero raises
- A Windows load: a copy with `is_windows = true`, same ls-fonts check. `setup-windows.ps1`
  only sets `WEZTERM_CONFIG_FILE`

## rules

- Every shell-out and cc-* key goes behind `POSIX` (`fleet_key` for bindings): Windows runs
  the config, not the fleet
- Shell-outs run under launchd's bare PATH: prefix `PATH="$HOME/.claude/bin:$HOME/.local/
  bin:/opt/homebrew/bin:$PATH"`, as `notify()` and the handover call do. Toasts go through
  `notify()` (`wz notify`); wezterm's own toasts are invisible on macOS
- The 1s `update-right-status` tick does no per-pane fork: one memoised read per file per
  second. The registry arrives through `cache/fleet-digest`, never a jq here
- Greys, widths and tab numbers: `.claude/rules/screen.md`, which loads with this file
- Strings in `wezterm.GLOBAL` survive a config reload; locals do not
- A reload evaluates the config twice and only one state gets events, so a
  `wezterm.time.call_after` loop started at load can be the dead copy. Start timers from an
  event handler, as `fast_tick_start` does (the 0.1s loop for actions.d and pane-read)

## do not

- `pane:split{ top_level = true }`. wezterm redistributed the reclaimed width unevenly and
  wedged a 4-pane tab: three panes at 1 column, "No space for split!", only a window resize
  cleared it
- change LEADER+b without asking. Settled: a left split of the tab's leftmost pane (the
  focused one if that is too narrow), then zoomed; if the tab has nothing live, run in place

## testing pane_status

It is a precedence over two sources, so test it, without the GUI: lift its block plus
`digest_rows` and `read_pane_state` with a `wezterm = { home_dir }` stub, point the path
locals at a temp dir, and drive it under luajit from planted digest rows and state files
(21 cases at last count: Esc after an ask, `shell`, parked with finished tasks, cold by a
5-minute expiry, an old three-field context file). Fixtures are time-relative: regenerate
them each run.
