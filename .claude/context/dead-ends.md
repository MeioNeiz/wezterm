# Measured dead ends

Each was tried and measured on this machine. Do not go looking again without new evidence
(a new wezterm or Claude Code version that says otherwise).

- **OSC 1337 `SetUserVar` fires its event only for the pane on screen** (wezterm 20260803,
  re-measured 2026-10-05 on the live GUI). `user-var-changed` fired for the focused pane,
  not for two in other workspaces (a visible unfocused pane: untested);
  `get_user_vars()` held the values for every pane, on screen or not.
  The 4 September test wrote to panes that were not on screen and called it dead. So it
  cannot carry an action or a hook's state to Lua for a pane in another tab or workspace,
  and reading it per pane is a mux call each, no cheaper than the memoised state file.
  What it does do: `wz` pokes the focused pane's tty with it (`wz_poke`) so the GUI drains
  `fleet/actions.d/` at once, the file staying the channel. Test: a logging
  `user-var-changed` handler, then `printf '\033]1337;SetUserVar=%s=%s\007' k "$(printf
  v | base64)" > /dev/ttysNNN`; the value must be base64, or it is dropped silently
- **`terminalSequence` will not rescue OSC 1337 either.** A hook can return it and have it
  written with no tty, but the allowlist is OSC 0/1/2, 9, 99, 777 and BEL. OSC 9 through it
  is the supported toast from a hook
- **WezTerm toasts, and OSC 9 through wezterm, are invisible on macOS**: wezterm is not
  registered with Notification Centre. Anything that must be seen goes through `wz notify`
- **Notification Centre banners leave after about five seconds whatever they are told**,
  and draw into one full-screen window, so their positions cannot be read either. Hence
  cc-toast, inside WezTerm
- **`claude agents --json` is not a second source of state.** For interactive sessions it
  is the registry: byte-identical on status, waitingFor, name, cwd, pid over three runs, at
  120-180ms against under 10ms for one jq. Background sessions are `~/.claude/jobs/`
- **`luajit` is not a syntax checker for wezterm.lua** (Lua 5.1; the file uses `//`,
  `utf8`), and `wezterm cli list` exits 0 on a config that raises. The check that works is
  in `.claude/rules/wezterm-lua.md`
- **`wezterm cli get-text` on a timer** as a third source of pane state: it buys nothing the
  hooks and the registry do not already say
