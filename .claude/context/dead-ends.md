# Measured dead ends

Each was tried and measured on this machine. Do not go looking again without new evidence
(a new wezterm or Claude Code version that says otherwise).

- **OSC 1337 `SetUserVar` does nothing on this build** (wezterm 20260803). No
  `user-var-changed` fires and `pane:get_user_vars()` stays empty, inside the pane and from
  outside, either terminator. The byte path is fine (`OSC 0` down the same tty lands in
  `cli list`), so the sequence is unhandled. The working CLI -> Lua bridge is a file the
  `update-status` handler drains each second (`fleet/actions.d/`)
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
