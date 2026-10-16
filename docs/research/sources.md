# Survey sources

What the capabilities survey of 5 October 2026 read, so the next one starts from the
changelog since these versions rather than from scratch.

## Versions checked

| what | version | where |
|---|---|---|
| Claude Code | 2.1.289 (changelog ends 2.1.289, 3 Oct) | `~/.local/share/claude/versions/2.1.289` |
| Claude Code, baseline for diffs | 2.1.286 (also 2.1.287, 2.1.288 on disk) | same dir |
| wezterm | 20260803-054620-6f8b1d41 | `/Applications/WezTerm.app`, cask `wezterm@nightly` |
| wezterm main at survey time | 37254829 (74 commits ahead) | GitHub |

Next survey: read the Claude Code changelog from 2.1.290, the wezterm changelog and
commits from 37254829, and diff `strings` of the new binary against 2.1.289 (below).

## Claude Code

Index: https://code.claude.com/docs/llms.txt (about 53KB; every page has a `.md` URL).
Never fetch `llms-full.txt` (8.7MB).

- https://code.claude.com/docs/en/changelog.md
- https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (same
  content; use whichever is current)
- https://code.claude.com/docs/en/hooks.md
- https://code.claude.com/docs/en/statusline.md
- https://code.claude.com/docs/en/settings.md
- https://code.claude.com/docs/en/settings-reference.md
- https://json.schemastore.org/claude-code-settings.json (added nothing the docs lacked)
- https://code.claude.com/docs/en/cli-reference.md
- https://code.claude.com/docs/en/interactive-mode.md
- https://code.claude.com/docs/en/keybindings.md
- https://code.claude.com/docs/en/env-vars.md
- https://code.claude.com/docs/en/sub-agents.md
- https://code.claude.com/docs/en/agents.md
- https://code.claude.com/docs/en/agent-view.md
- https://code.claude.com/docs/en/cross-session-messaging.md
- https://code.claude.com/docs/en/sessions.md
- https://code.claude.com/docs/en/remote-control.md
- https://code.claude.com/docs/en/plugins-reference.md
- https://code.claude.com/docs/en/plugins/components.md, `overview.md`, `create.md`,
  `security.md` (plugin pages moved under `/plugins/`)
- https://code.claude.com/docs/en/plugins/mods/overview.md, `api.md`, `reference.md`

Local:
- The binary: `strings` of 2.1.289 against 2.1.286 for hook events, Notification types,
  StopFailure kinds, settings keys, env vars, flags, statusLine fields. The diff is the
  fastest way to find what the changelog does not say (`auth_storage_failure`, the
  Monitor `kind:"monitor"` to `type:"shell"` mapping, hidden flags).
- `claude --help` and every subcommand's `--help`, diffed against the previous version.
- Mod API, exact for the build: load the `plugin-authoring` skill; it writes
  `types/claude-code.d.ts` (about 20k lines at 2.1.289) into its bundled-skills folder
  under `/private/tmp/claude-501/bundled-skills/<version>/`. Grep it, do not read it.
- `~/.claude/settings.json`, `~/.claude.json`, `~/.claude/keybindings.json`, `~/.zshrc`
  (the `claude` alias)
- `~/.claude/sessions/*.json`, `~/.claude/jobs/*/state.json`,
  `~/.claude/daemon/roster.json`, `~/.claude/plugins/installed_plugins.json`
- `~/.claude/projects/` (transcript ages and size), `~/.claude/cache/context/`,
  `~/.claude/wezterm-state/`
- `claude agents --json [--all]`, `ps` of registered pids (argv of cc-spawn panes)

## wezterm

No llms.txt; the repo's markdown is quicker than the site.

- Changelog: https://raw.githubusercontent.com/wezterm/wezterm/main/docs/changelog.md,
  diffed against the same file at `6f8b1d41` (https://wezterm.org/changelog.html is the
  rendered copy)
- Commits: `gh api repos/wezterm/wezterm/compare/6f8b1d41...main` and `gh api
  "repos/wezterm/wezterm/commits?since=2026-08-03T00:00:00Z&per_page=100"`
- Nightly: `gh api repos/wezterm/wezterm/releases/tags/nightly`
- Doc tree: https://api.github.com/repos/wezterm/wezterm/git/trees/main?recursive=1
- Lua reference: https://raw.githubusercontent.com/wezterm/wezterm/main/docs/config/lua/
  (`pane/get_progress.md`, `PaneInformation.md`, `window-events/`, `mux-events/`,
  `wezterm.time/call_after.md`, `config/exit_behavior.md`)
- CLI: https://github.com/wezterm/wezterm/tree/main/docs/cli/cli, and
  `wezterm/src/cli/list.rs`, `spawn_command.rs`
- SetUserVar handling: `term/src/terminalstate/performer.rs`,
  `wezterm-escape-parser/src/osc.rs` at `6f8b1d41`
- Open PRs: #8203 (`start --wait-exit`), #8036 (format-tab-title speed-up)

Local:
- `wezterm --version`, `wezterm cli --help` and each read-only subcommand's `--help`,
  `wezterm cli list --format json`, `wezterm cli list-clients --format json`
- `strings /Applications/WezTerm.app/Contents/MacOS/wezterm-gui`
- `/opt/homebrew/Caskroom/wezterm@nightly/.metadata/`, `codesign -dv
  /Applications/WezTerm.app`
- `~/.local/share/wezterm/*.txt` (GUI and mux logs; where the auto-start bursts showed)
- SetUserVar test: a separate GUI via `open -g -n /Applications/WezTerm.app --args
  --config-file <scratch> start --always-new-process --class muxtest`, logging events to
  a file, plus a private `wezterm-mux-server` with its own socket. Never point a scratch
  config at the default socket: a syntax error falls back to defaults and binds
  `~/.local/share/wezterm/sock`

## Repo files read against them

`wezterm.lua`, `statusline.sh`, `setup.sh`, `hooks/wezterm-pane-state.sh`,
`hooks/wezterm-session-map.sh`, `hooks/claude-session-brief.py`, every script in `bin/`,
`toast/cc-toast.swift`, `skills/fleet/SKILL.md`, and
`~/personal/kev-mcp/hooks/stop-asks.py`.
