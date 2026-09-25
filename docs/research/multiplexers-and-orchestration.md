

============================== a359354373906c54a ==============================

I have comprehensive findings. Compiling the report now.

Competitor multiplexer agent features worth porting to WezTerm + bash, 2026
==========================================================================

Framing: the velocity gap
-------------------------

WezTerm's last tagged stable release is `20240203-110809-5046fc22`, dated 3 February 2024 (https://github.com/wezterm/wezterm/releases). There is no 2025 or 2026 stable release; development continues only as nightly builds off `main`, and there are open issues explicitly asking the maintainer to resume stable releases (https://github.com/wezterm/wezterm/issues/7825, https://github.com/wezterm/wezterm/issues/7451). Meanwhile Zellij shipped 0.44.0 (23 March 2026) and 0.45.0 (20 August 2026), and tmux shipped 3.6 with 3.6b in May 2026 (https://zellij.dev/news/, https://github.com/tmux/tmux/releases).

The practical consequence: every agent-oriented primitive below has to be hand-rolled in `wezterm.lua` plus bash. The good news is that a real WezTerm agent-plugin ecosystem appeared in 2026 and several of these are already solved (see section 8).

The single biggest structural gap is this: **WezTerm has no output-streaming primitive.** `wezterm cli get-text` is poll-only. Every competitor has push:

| Product | Streaming primitive | Verified at |
|---|---|---|
| Zellij | `zellij subscribe --pane-id X --format json` (NDJSON on change) | https://zellij.dev/documentation/zellij-subscribe.html |
| tmux | `pipe-pane -o`, control mode `%output`, `refresh-client -B` format subscriptions | https://github.com/tmux/tmux/wiki/Control-Mode |
| kitty | `kitty @ launch --watcher` Python callbacks | https://sw.kovidgoyal.net/kitty/launch/ |
| herdr | socket API `events.subscribe` on `pane.agent_status_changed` | https://herdr.dev/docs/socket-api |
| WezTerm | **none** (poll `get-text`, or push via OSC 1337 SetUserVar) | https://wezterm.org/cli/cli/get-text.html |

---

1. Zellij
=========

1a. `zellij subscribe`: the killer primitive (0.44.0, March 2026)
-----------------------------------------------------------------

https://zellij.dev/documentation/zellij-subscribe.html

```
zellij [--session <NAME>] subscribe [OPTIONS] --pane-id <PANE_ID>...
  -p, --pane-id <PANE_ID>     repeatable; accepts terminal_N, plugin_N, or bare N
  -s, --scrollback [<LINES>]  include scrollback in initial delivery; bare = all
  -f, --format <FORMAT>       raw (default) | json
      --ansi                  preserve ANSI styling
```

Emits NDJSON:
```json
{"event":"pane_update","pane_id":"terminal_1","viewport":["line1"],"scrollback":null,"is_initial":true}
{"event":"pane_closed","pane_id":"terminal_1"}
```

Semantics: full viewport delivered immediately with `is_initial: true`, then deliveries **only on content change**; the client exits automatically when all subscribed panes close. Worked examples from the docs:

```bash
zellij subscribe --pane-id terminal_1 --format json | jq --unbuffered 'select(.event=="pane_update") | .viewport[] | select(test("ERROR"))'
zellij --session build-server subscribe --pane-id terminal_1 --format json
```

**Port to WezTerm.** There is no equivalent, and this is the thing your `cc-board` most wants. Two options:

- *Poll loop with change detection.* A daemon that, per pane from `wezterm cli list --format json`, runs `wezterm cli get-text --pane-id N` on a 300 to 1000 ms tick, hashes the tail, and only emits on hash change. This is precisely what `wezterm-agent-deck` does at `update_interval = 500` (https://github.com/Eric162/wezterm-agent-deck). Cost: N subprocess spawns per tick, so cap N or stagger.
- *Push instead of poll (strongly preferred).* Have Claude Code hooks write state out-of-band rather than scraping the screen. See section 7a and 8b.

1b. Programmatic control and headless sessions
-----------------------------------------------

https://zellij.dev/documentation/programmatic-control.html, https://zellij.dev/documentation/cli-recipes.html

Zellij 0.44 added an explicit "create, command, observe, react" scripting story. Notable pieces WezTerm lacks:

- `zellij attach --create-background <name>` creates a **headless session** with no client attached. WezTerm has no headless mux session you can spawn panes into without a GUI window; the nearest is `wezterm cli --class` targeting or a `wezterm-mux-server` domain.
- **Pane-creating commands return the pane ID on stdout**: `PANE_ID=$(zellij --session my-session action new-pane --name worker)`. `wezterm cli spawn` and `wezterm cli split-pane` already print the new pane id, so you have this.
- **Blocking flags** on `zellij run` and `zellij action new-pane` (https://zellij.dev/documentation/zellij-run-and-edit.html):
  ```
  --blocking                   block until command finishes and pane closes
  --block-until-exit           block until exit regardless of status
  --block-until-exit-success   block until exit 0
  --block-until-exit-failure   block until non-zero
  ```
  giving `zellij run --block-until-exit-success -- cargo test && zellij run --blocking -- cargo build --release`.

  **Port:** WezTerm has nothing like this. Build `wz run --wait`: spawn the pane, then poll `wezterm cli list --format json` for the pane's disappearance, or better, wrap the command as `sh -c 'cmd; echo $? > /tmp/wz-exit-$$'` and have bash `wait` on the sentinel file. A cleaner variant: spawn with a trailing `printf '\033]1337;SetUserVar=%s=%s\007' wz_exit "$(printf %s "$?" | base64)"` and have `wezterm.lua`'s `user-var-changed` fire your completion handler (see 1e).

1c. `zellij action` surface worth cloning verbatim
---------------------------------------------------

https://zellij.dev/documentation/cli-actions.html

- `dump-screen [--path <PATH>] [-f|--full] [-p|--pane-id <ID>] [-a|--ansi]` — dump viewport or full scrollback of **any** pane, not just the focused one. WezTerm's `get-text --pane-id N --start-line -10000 --end-line 0 [--escapes]` is the equivalent and you already have it (https://wezterm.org/cli/cli/get-text.html).
- `edit-scrollback [-p|--pane-id <ID>] [-a|--ansi]` — opens a pane's scrollback in `$EDITOR`. **No WezTerm equivalent, trivially portable:** `wezterm cli get-text --pane-id "$1" --start-line -100000 > /tmp/scrollback.$1 && wezterm cli spawn -- "$EDITOR" /tmp/scrollback.$1`. Genuinely useful for reading a long agent transcript with search.
- `list-panes [-t|--tab] [-c|--command] [-s|--state] [-g|--geometry] [-a|--all] [-j|--json]` — the `--state` field reports focused / floating / **exited**. WezTerm's `list --format json` emits only `window_id, tab_id, pane_id, workspace, size{rows,cols}, title, cwd` (https://wezterm.org/cli/cli/list.html). No exit state, no running command. **Port:** join `wezterm cli list --format json` against `ps` by the pane's foreground process, keyed on `WEZTERM_PANE`, or maintain your own registry file written by `cc-spawn`.
- `send-keys [-p|--pane-id <ID>] 'Ctrl c' 'Enter'` — symbolic key names, not raw bytes. WezTerm's `send-text --pane-id N` sends literal text only; `--no-paste` disables bracketed paste. **Port:** a `wz keys` wrapper mapping names to bytes (`Ctrl c` to `\x03`, `Enter` to `\r`, `Escape` to `\x1b`). Important for interrupting a runaway agent from a script.
- `dump-layout` dumps the live layout as KDL to stdout, which round-trips back into `zellij --layout`. WezTerm has no layout serialiser; `resurrect.wezterm` fills this (section 8d).
- `new-pane` flags worth stealing: `--near-current-pane`, `--no-focus` (spawn without stealing focus, essential for a fleet spawner), `--start-suspended` (command staged behind an ENTER press), `--close-on-exit`, `--tab-id`, `--pinned`, `--stacked`. `wezterm cli spawn` has `--new-window`, `--workspace`, `--cwd`, `--pane-id`; there is no `--no-focus`, so `cc-spawn` should re-activate the origin pane afterwards with `wezterm cli activate-pane --pane-id $ORIGIN`.

1d. Plugin pipes: the pub/sub bus
-----------------------------------

https://zellij.dev/documentation/plugin-pipes.html, https://zellij.dev/documentation/zellij-plugin-and-pipe.html

```
zellij pipe [OPTIONS] [--] <PAYLOAD>
  -n, --name <NAME>                  pipe name
  -a, --args <ARGS>                  key=value
  -p, --plugin <PLUGIN>              target plugin URL (omit = broadcast to all plugins)
  -c, --plugin-configuration <CFG>
  -l, --force-launch-plugin
  -f, --floating-plugin <BOOL>
  -i, --in-place-plugin <BOOL>
  -w, --plugin-cwd <CWD>
  -t, --plugin-title <TITLE>
```

With no `--plugin`, the message is **broadcast to every loaded plugin**. It reads stdin when no payload is given, and applies backpressure: the stdin buffer is only released after the plugin has rendered, and plugins can call `block_cli_pipe_input()` / `unblock_cli_pipe_input()` explicitly. Plugins write back to the CLI pipe's stdout via `cli_pipe_output(pipe_id, data)`, so a pipe is genuinely bidirectional:

```bash
tail -f /tmp/logfile | zellij pipe --name logs --plugin https://example.com/plugin.wasm | wc -l
```

**Port.** WezTerm's exact analogue is **OSC 1337 SetUserVar plus the `user-var-changed` Lua event** (https://wezterm.org/config/lua/window-events/user-var-changed.html):

```bash
printf "\033]1337;SetUserVar=%s=%s\007" cc_state "$(printf %s "working" | base64 -w0)"
```
```lua
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name == 'cc_state' then window:set_right_status(value) end
end)
```
Values are readable later with `pane:get_user_vars()`. This is push, per-pane, needs no polling, and survives across `wezterm cli` invocations. It is the correct spine for `cc-board`. Two caveats: `base64 -w0` is required on Linux to avoid line-wrap truncation, and the sequence must reach the pane's tty, so a Claude Code hook must write to `/dev/tty` or to the pane device rather than stdout (which Claude consumes). If that proves fragile, use the file-marker pattern in 8b instead.

1e. Plugin permissions and plugin events
-----------------------------------------

https://zellij.dev/documentation/plugin-api-permissions.html lists 14 capabilities: `ReadApplicationState`, `ChangeApplicationState`, `OpenFiles`, `RunCommands`, `OpenTerminalsOrPlugins`, `WriteToStdin`, `Reconfigure`, `FullHdAccess`, `StartWebServer`, `InterceptInput`, `ReadPaneContents`, `RunActionsAsUser`, `WriteToClipboard`, `ReadSessionEnvironmentVariables`. Plugins call `request_permission` and the user approves interactively.

The plugin event list (https://zellij.dev/documentation/plugin-api-events.html) is the in-process version of `subscribe`: `PaneUpdate` (a `PaneManifest` of every pane with title, size, command, focus), `TabUpdate`, `SessionUpdate` (including **resurrectable dead sessions**), `ListClients`, `CommandPaneOpened(pane_id, ctx)`, `CommandPaneExited(pane_id, exit_code, ctx)`, `RunCommandResult(exit, stdout, stderr, ctx)`, `WebRequestResult`, `Timer`, `Key`, `PastedText`, `PermissionRequestResult`, and `PaneRenderReport` (gated on `ReadPaneContents`).

`CommandPaneExited` with an exit code and a context dictionary is the clean event WezTerm most conspicuously lacks. **Port:** wrap every `cc-spawn`ed command so it emits its own exit event as a user var, as in 1b.

1f. KDL layouts
----------------

https://zellij.dev/documentation/creating-a-layout.html. Declarative, composable, and directly runnable with `zellij --layout /path/to/layout.kdl`:

```kdl
layout {
    cwd "/hi"
    pane_template name="agent" {
        command "claude"
        borderless true
    }
    tab name="fleet" split_direction="vertical" {
        agent { args "--name" "api" }
        agent { args "--name" "web" }
    }
    tab_template name="with-bar" {
        pane size=1 borderless=true { plugin location="zellij:tab-bar" }
        children
    }
}
```
Key attributes: `command`, `args` (must be in child braces, not inline), `cwd` (relative paths compose down the tree; absolute paths override), `start_suspended=true` (stage behind an ENTER press), `close_on_exit=true`, `focus=true`, `name`, `borderless`, `split_direction`, `size`, `hide_floating_panes`, plus `pane_template` / `tab_template` / `default_tab_template` with a `children` insertion point. `zellij setup --dump-layout default` exports.

**Port.** WezTerm has `wezterm.on('gui-startup', function(cmd) ... end)` with `mux.spawn_window` and `tab:split`, which is imperative Lua rather than declarative. Given you already have `cc-fleet`, the higher-value move is a small YAML or TOML fleet spec read by bash and turned into `wezterm cli spawn/split-pane` calls, giving you Zellij's `pane_template` reuse and `cwd` composition. Warp's launch configurations (section 4c) are a good schema to copy.

1g. Session resurrection
-------------------------

https://zellij.dev/documentation/session-resurrection.html. On by default. Zellij serialises layout, per-pane commands, and optionally viewport and scrollback into a KDL layout in the cache dir at intervals. Config keys: `session_serialization`, `pane_viewport_serialization`, `scrollback_lines_to_serialize`, `post_command_discovery_hook`. On resurrect, commands are **staged behind a "Press ENTER to run..." banner** so you do not accidentally re-run `rm -rf`; `--force-run-commands` bypasses it. `zellij ls` shows EXITED sessions; `zellij attach <name>` revives one.

**Port:** `resurrect.wezterm` (section 8d) is the direct equivalent and already exists. The ENTER-gate idea is worth copying explicitly for an agent fleet: you do not want a restore to fire off twelve `claude --dangerously-skip-permissions` sessions unattended.

1h. Web client and remote sessions (0.44.0)
--------------------------------------------

https://zellij.dev/documentation/web-client.html

```bash
zellij web                                    # serves http://127.0.0.1:8082
zellij web --create-token
zellij web --create-read-only-token --token-name "observer-token"
zellij web --list-tokens / --revoke-token / --status
zellij attach https://my-server:8082/my-session --token <login-token> [--remember|--forget|--ca-cert|--insecure]
zellij watch <session-name>                   # read-only local attach
```
Config keys: `web_server true`, `web_server_ip "0.0.0.0"`, `web_server_port 443`, `web_server_cert`, `web_server_key`, `enforce_https_on_localhost true`. HTTPS is mandatory outside 127.0.0.1. Session tokens are httponly cookies; revoking a login token revokes its session tokens. URL path is the session name and will create, attach, or resurrect. 0.45.0 added a **mobile web UI** with touch controls and PWA install, so you can pin a session to a phone home screen.

This is the standout "watch my agent fleet from the sofa" feature and is a lot of work to rebuild. **Port:** do not. Use Claude Code's own Remote Control instead (section 7d), which covers the same use case natively and keeps execution local.

1i. 0.45.0, August 2026
------------------------

https://zellij.dev/news/nested-sessions-kitty-graphics-new-ui/

- **Nested sessions**: detects Zellij-in-Zellij; `Ctrl o f` zooms the nested session, `Ctrl o ]` ascends, `Ctrl o [` descends. Relevant if you ever run tmux inside WezTerm for Agent Teams (section 7a): you get the same prefix-collision problem and no such affordance.
- **Scrolling by command**, driven by OSC 133 shell integration: `Ctrl s [` and `Ctrl s ]` jump between prompts, `Ctrl s m` selects a command with its output, `Ctrl s c` **copies the last command's output**, and Alt plus mousewheel does prompt-jumping. Fish emits OSC 133 natively; bash and zsh need snippets. **Port:** WezTerm supports OSC 133 (https://wezterm.org/escape-sequences.html) and has `ScrollToPrompt` as a key assignment. "Copy last command output" as a `wz` subcommand, built on `get-text` plus OSC 133 zone boundaries, is a small win for grabbing an agent's last tool output.
- Kitty graphics protocol, per-client tab sizes, fullscreen floating panes, focus-last-pane (`Ctrl p ;`), pane frames off by default (`pane_frame_style "full"` restores), `stacked_pane_list`.
- Release notes that offer to rewrite your keybindings on upgrade. A nice touch, not portable.

1j. Zellij's agent plugin ecosystem in the wild
------------------------------------------------

- **claude-code-zellij-status** (https://github.com/thoo/claude-code-zellij-status). Claude Code hooks (`PreToolUse`, `PostToolUse`, `Stop`, `Notification`) pipe into `claude-activity-hook.sh`, which maps events to activity, colour and symbol, persists to `/tmp/claude-zellij-status/{session}.json`, and pushes into zjstatus via `zellij pipe`. 16-plus states: `●` yellow working, `✓` green done, `?` red asking user, `⚡` orange running bash, `◐` grey thinking. **This is the exact architecture to copy for `cc-board`, with `zellij pipe` swapped for OSC 1337 SetUserVar or a marker file.**
- **zjstatus** (https://github.com/dj95/zjstatus) plus its pipe widget (https://github.com/dj95/zjstatus/wiki/4-%E2%80%90-Widgets). The pipe widget is a named status-bar slot an external script can write into:
  ```
  pipe_NAME_format "#[fg=#89B4FA,bg=#181825] {output}"
  pipe_NAME_rendermode "static"   # static | dynamic | raw (raw preserves ANSI)
  ```
  updated with `zellij pipe "zjstatus::pipe::pipe_NAME::your message"` (no newlines allowed). **Port:** in `wezterm.lua`, a table keyed by pane id fed from `user-var-changed`, rendered in `update-status` and `format-tab-title`.
- **falcode-zellij** (https://github.com/victor-falcon/falcode-zellij). A floating popup listing every active AI agent pane **across all Zellij sessions**, with states `idle` (finished, ready for you), `permission` (tool needs approval), `question` (agent is asking). Keys 1-9 jump directly, Enter focuses and switches session if needed, j/k scroll, q/Esc close. Detection is delegated to a user-editable shell script, `detect-active-opencode.sh`, that emits the pane list as JSON, so you can change detection without rebuilding the WASM. Bound with:
  ```kdl
  bind "Alt o" {
      LaunchOrFocusPlugin "file:~/.config/zellij/plugins/falcode-zellij-sessions.wasm" {
          floating true
          state_dir "__YOUR_HOME_DIR__/.local/state/falcode-zellij"
      }
  }
  ```
  **Port:** this is your `cc-board` popup. WezTerm's equivalent is `InputSelector` with dynamically built `choices` (https://wezterm.org/config/lua/keyassignment/InputSelector.html), which renders in an overlay pane and supports `fuzzy = true`, a custom `alphabet` for single-key jumps, `title`, `description`, and a `wezterm.action_callback(function(window, pane, id, label) ... end)`. Build choices from your state files, label them with the state glyph, and have the callback `window:perform_action(wezterm.action.ActivatePaneByIndex...)` or shell out to `wezterm cli activate-pane --pane-id <id>`. The "detection lives in an editable shell script, not the plugin" split is a good design rule to copy.
- **zellij-claude** (https://github.com/715d/zellij-claude). Identifies Claude panes by command starting with `claude` or pane named `claude`, then:
  ```bash
  echo "launch-or-focus" | zellij pipe -p zellij-claude
  echo "message::What is Rust?" | zellij pipe -p zellij-claude   # sends text then 0x0d
  ```
  **Port:** one-liner for you already: `wezterm cli send-text --pane-id N --no-paste "$msg" && wezterm cli send-text --pane-id N $'\r'`. Note the two-step send: text first, then a separate carriage return, which is the reliable way to submit to a TUI prompt. Zellij's own docs recommend `paste` for multi-line safety followed by `send-keys Enter` for the same reason.
- **zellaude** (https://github.com/ishefi/zellaude), a Claude-aware tab bar replacement, and **zellij-send.el** (https://github.com/ichibeikatura/zellij-send.el), Emacs to agent-pane messaging.

**What Zellij gives natively that WezTerm users must hand-roll:** streaming pane subscriptions; headless background sessions; blocking command panes with exit-status gating; per-pane symbolic key sending; `edit-scrollback`; declarative KDL layouts with templates; automatic session serialisation and resurrection; a permissioned in-process plugin runtime with a pane/tab/session event bus; a broadcast message bus (`zellij pipe`); floating and pinned panes as a first-class overlay surface; an authenticated web client with read-only tokens.

---

2. tmux
=======

2a. tmux 3.6 (3.6b, May 2026)
------------------------------

From the 3.6 CHANGES (https://raw.githubusercontent.com/tmux/tmux/3.6/CHANGES, https://github.com/tmux/tmux/releases/tag/3.6):

- `pane-scrollbars`, `pane-scrollbars-position`, `pane-scrollbars-style`: native per-pane scrollbars. Genuinely useful with many agent panes as a visual "how much output has this one produced" cue. WezTerm has a window scrollbar (`enable_scroll_bar`) but not per-pane.
- `capture-pane -M` uses the copy-mode screen; `-T` (from 3.5) stops at the last used cell rather than padding to full width. **`-T` is worth knowing:** it is the difference between a clean scrape and one padded with trailing spaces. WezTerm's `get-text` has no equivalent, so `sed -e 's/[[:space:]]*$//'` your captures.
- `display-popup -k`: any key dismisses the popup once the command has exited.
- `run-shell -E` forwards stderr as well as stdout.
- `command-prompt -l` disables splitting into multiple prompts.
- `tiled-layout-max-columns`: caps columns in the tiled layout. **Directly relevant to fleets:** with twelve agent panes, tmux's tiled layout can now be constrained to, say, three columns. WezTerm has no auto-tiling layout at all; `cc-fleet` has to compute splits itself.
- `initial-repeat-time`, `input-buffer-size`, `no-detach-on-destroy`, `selection-mode`, `codepoint-widths`, `variation-selector-always-wide`, `copy-mode-position-style`, `copy-mode-selection-style`, `copy-mode-position-format`, `prompt-cursor-colour`, `prompt-cursor-style`.
- Formats: `buffer_full`, `sixel_support`. Copy commands gained `-C` (do not send to clipboard) and `-P` (do not add a paste buffer).
- Terminal query support: DECRQSS `SP q` (cursor style), DECRQM `?12`, `?2004`, `?1004`, `?1006` (mouse state), and **mode 2031** for automatic dark/light theme reporting.

3.5 added the `command-error` hook and `capture-pane -T`.

2b. The tmux primitives that matter for agent fleets
-----------------------------------------------------

Verified against https://manpages.debian.org/unstable/tmux/tmux.1.en.html.

**Hooks.** The full list: `alert-bell`, `alert-activity`, `alert-silence`, `client-attached`, `client-detached`, `client-focus-in`, `client-focus-out`, `client-resized`, `command-error`, `pane-died`, `pane-exited`, `pane-focus-in`, `pane-focus-out`, `pane-mode-changed`, `session-created`, `session-closed`, `session-renamed`, `session-window-changed`, `window-layout-changed`, `window-linked`, `window-pane-changed`, `window-renamed`, `window-unlinked`. Set with `set-hook [-ag] [-t target-pane] hook-name command`.

`alert-silence` is the sleeper feature: combined with `monitor-silence`, tmux tells you when a pane has produced **no output for N seconds**, which is a decent proxy for "this agent has stalled or is waiting". `pane-died` plus `remain-on-exit` lets you catch a crashed agent rather than losing the pane.

**Port to WezTerm.** WezTerm's Lua event set is much thinner: `augment-command-palette`, `bell`, `format-tab-title`, `format-window-title`, `new-tab-button-click`, `open-uri`, `update-right-status`, `update-status`, `user-var-changed`, `window-config-reloaded`, `window-focus-changed`, `window-resized` (https://wezterm.org/config/lua/window-events/index.html). There is no `pane-died`, no `pane-exited`, no activity or silence alerting. Build silence detection yourself: in your poll daemon, store `last_change_ts` per pane alongside the content hash, and flag any pane in state `working` whose hash has not changed for N seconds. This is exactly what workmux does (see 2d): its sidebar daemon flags a pane as **interrupted** when output stalls for 10 seconds while status is `working`, catching the "user hit Ctrl+C and the agent is now sitting at a prompt" case that hooks miss.

**`pipe-pane [-IOo] [-t target-pane] [shell-command]`.** Streams a pane's output to a command (`-O`, default) or feeds a command's output into the pane (`-I`), with `-o` toggling. This is tmux's answer to `zellij subscribe`, and is how you would tee an agent's whole session to a log for later grep:
```bash
tmux pipe-pane -o -t %3 'cat >> ~/agent-logs/%3.log'
```
**No WezTerm equivalent.** Closest workaround: launch the agent under `script`, i.e. `cc-spawn` runs `script -q -F ~/agent-logs/$name.log claude ...` (BSD `script` on macOS uses `-F` to flush). That gives you a durable, greppable transcript per agent without polling, and is arguably better than `pipe-pane` because it survives pane death.

**`wait-for [-L|-S|-U] [-t timeout] name`.** A named rendezvous channel: `-S` signals, `-L` locks, `-U` unlocks, plain form blocks. This is a barrier primitive for "run the reviewer agent only after the three implementer agents finish". **Port:** trivially replaced in bash with a FIFO or a lock directory:
```bash
wz_wait()   { while [ ! -e "/tmp/wz-sig/$1" ]; do sleep 0.2; done; }
wz_signal() { mkdir -p /tmp/wz-sig && : > "/tmp/wz-sig/$1"; }
```
or `flock` on a per-channel file for the lock/unlock semantics.

**`display-popup [-BCE] [-b border-lines] [-d x,y] [-h height] [-s style] [-t target-pane] [-w width] [-x x] [-y y] [content]`** and **`display-menu [-c client] [-t pane] [-x] [-y] name key command ...`**. Popup overlays and keyed menus, the surface people build fleet dashboards on. **Port:** WezTerm has no user-scriptable popup pane. Your two options are `InputSelector` (overlay list with fuzzy filter and single-key alphabet, described in 1j) and `PromptInputLine` for free text. For a full dashboard, spawn a small floating window: `wezterm cli spawn --new-window -- cc-board-tui`, with `wezterm.lua` sizing it via a `gui-startup`-style handler or a dedicated `window:set_inner_size()`.

**`run-shell [-b] [-t pane] [-d delay] cmd`** (`-b` background, `-d` delay) and **`if-shell [-bF] [-t pane] cmd then [else]`** give tmux conditional and deferred execution inside its own config language. WezTerm's Lua has `wezterm.run_child_process` and `wezterm.background_child_process`, plus `wezterm.time.call_after(seconds, fn)` for the `-d` case, so you are covered.

2c. Control mode (`tmux -C` / `-CC`)
--------------------------------------

https://github.com/tmux/tmux/wiki/Control-Mode

A persistent text protocol over one connection. Every command returns a block guarded by `%begin ts cmdnum flags` and terminated by `%end` on success or `%error` on failure:
```
%begin 1578923149 270 1
parse error: unknown command: abcdef
%error 1578923149 270 1
```
Asynchronous notifications: `%output %pane data` (non-printables octal-escaped), `%pane-mode-changed %pane`, `%window-pane-changed @window %pane`, `%window-add`, `%window-close`, `%window-renamed`, `%unlinked-window-add/close/renamed`, `%session-changed $session name`, `%session-renamed`, `%sessions-changed`, `%session-window-changed`, `%client-session-changed`, `%subscription-changed`.

Two features are directly stealable in concept:

- **Format subscriptions**: `refresh-client -B name:type:format` where type is empty (session), `%n` (one pane), `%*` (all panes), `@n` or `@*` (windows). tmux then pushes `%subscription-changed` whenever the formatted value changes, at most once per second. Unsubscribe with `refresh-client -B name`. This is a *server-side computed, change-only* push channel, which is far cheaper than scraping. **Port:** this is precisely what `user-var-changed` gives you in WezTerm, for free, per pane, with no rate limit. Use it.
- **Flow control**: `refresh-client -f pause-after=30` switches to `%extended-output %pane milliseconds-behind : data` and pauses panes that fall behind; resume with `refresh-client -A '%pane:continue'`. Relevant if you ever stream twelve chatty agents into one consumer. Your bash equivalent: bound your poll loop's per-tick work and drop frames rather than queueing.

Note that Claude Code's own docs recommend `tmux -CC` under iTerm2 as the suggested entry point into tmux for Agent Teams (section 7a).

2d. tmux ecosystem projects relevant to agents
------------------------------------------------

- **workmux** (https://workmux.raine.dev/, https://workmux.raine.dev/guide/status-tracking). The most complete 2026 reference implementation, and it supports **both tmux and Zellij** (not WezTerm). Model: one git worktree plus one tmux window per task. `workmux add -A "task description"` creates branch, worktree and spawns the agent; `workmux merge` handles the full lifecycle cleanup. Project config is `workmux.yaml` defining file copies, symlinks and setup hooks on worktree creation. `workmux setup` auto-detects installed agent CLIs (Claude Code, Codex, Copilot CLI, Gemini CLI, Grok, Antigravity CLI, OpenCode, Pi, Oh My Pi) and installs the right hooks. Status is written by a hook shaped as `workmux set-window-status working >/dev/null 2>&1 || true; printf '{}\n'` (note: it passes the hook payload through unchanged so it does not break the agent). Three states: 🤖 working, 💬 waiting for input, ✅ finished, with ✅ **auto-clearing on window focus**. It rewrites `window-status-format`, or you opt out and add `#{?@workmux_status, #{@workmux_status},}` yourself. Plus the 10-second output-stall "interrupted" heuristic. It also ships `/merge` and `/worktree` skills, and a `/coordinator` skill for orchestrating parallel worktree agents.

  **Steal:** the auto-clear-on-focus rule (done state should not nag once you have looked at it), the stall heuristic, and the `|| true` plus passthrough hook discipline.

- **gentle-agent-state** (https://github.com/Gentleman-Programming/gentle-agent-state). Per-agent adapters normalise to three canonical states, `working` (prompt submitted, tool running), `blocked` (permission request, user question), `idle` (stopped). Adapters live at `~/.config/opencode/plugins/gentle-agent-state.js`, `~/.pi/agent/extensions/gentle-agent-state.ts`, and merged hooks in the Claude/Codex settings JSON. All of them call one neutral dispatcher, `~/.config/agent-state/scripts/agent-report.sh`, which sniffs the environment and routes to a backend (`tmux-agent-report.sh`, a Ghostty backend, and so on). tmux state is stored in **window user options** and rendered from `~/.config/tmux/agents.conf`, with the crucial rule that **a window shows the worst state across its panes**: blocked beats working beats idle. Sound alerts via `AGENT_SOUND_BLOCKED` (default `Funk.aiff` on macOS, `dialog-warning.oga` on Linux) and `AGENT_SOUND_IDLE` (`Glass.aiff` / `complete.oga`), played with `afplay`, `paplay` or `aplay`, fired on the transition into blocked and on working-to-idle.

  **Steal, hard:** the neutral-dispatcher architecture is exactly right for you. One `cc-state` script that every agent's hooks call, which then decides whether to write a WezTerm user var, a marker file, or a tmux option. It future-proofs you against changing multiplexer. And the worst-state-wins rollup is the correct aggregation rule for `cc-board`'s tab titles.

- **tmux-agent-indicator** (https://github.com/accessd/tmux-agent-indicator). States `running`, `needs-input`, `done`. Installer writes three hooks into `~/.claude/settings.json`: `UserPromptSubmit` to running, `PermissionRequest` to needs-input, `Stop` to done, with the template in `hooks/claude-hooks.json`. Drives `pane-active-border-style` / `pane-border-style`, `window-title-bg` / `window-title-fg`, and a `#{agent_indicator}` status format. Core script is callable directly: `agent-state.sh --agent claude --state running`. Falls back to process detection over `@agent-indicator-processes` when hooks are unavailable.

  **Steal:** colouring the **pane border** by agent state. WezTerm supports this via `config.colors.split` for the divider plus per-pane visual weight through `inactive_pane_hsb`; for a real per-pane border colour you would use `format-tab-title` plus a status glyph instead, since WezTerm does not expose per-pane border styling. The three-hook mapping (`UserPromptSubmit` / `PermissionRequest` / `Stop`) is the minimum viable state machine.

- **tmux-agent-status** (https://github.com/samleeney/tmux-agent-status). Four hooks: `UserPromptSubmit` to working, `PreToolUse` keeps working, `Stop` to done, `Notification` for alerts. Importantly it handles **background tasks**: if a turn ends while a background task is still running, the `Stop` payload's `background_tasks` array keeps the session marked working until a later `Stop` reports it finished. State files in `~/.cache/tmux-agent-status/`: `<session>.status`, `panes/<session>_<pane>.status`, plus `wait/*.wait` and `parked/*.parked` mode overrides. Rendering: working is yellow and **pulsing** (`✳`/`✻`, `⬢`/`⬡`), done green, waiting cyan, and "each working glyph flips frames every second, staggered by position so a row of busy agents pulses rather than blinking in unison".

  **Steal:** the `background_tasks` handling (otherwise every agent running a long background bash looks idle), the `parked` override concept (mark an agent as deliberately parked so it stops nagging, which pairs with your `cc-note`), and the staggered pulse. WezTerm's `update-status` fires on a timer you set with `config.status_update_interval = 500`, so a staggered animation is a few lines of Lua keyed on `pane_id % n`.

- **Claude Squad** (https://github.com/smtg-ai/claude-squad). tmux for isolated sessions plus **git worktrees so each session works on its own branch**, driven by a TUI. Config at `~/.claude-squad/config.json` with named profiles carrying different program launch commands. Supports Claude Code, Codex, Aider. The README does not document a state-detection mechanism, so treat it as worktree-and-TUI rather than a state model.

- **sesh** (https://github.com/joshmedeski/sesh). Config `sesh.toml` in `$XDG_CONFIG_HOME/sesh` or `~/.config/sesh`, with session blocks carrying `name`, `path`, `startup_command`, `preview_command`, `windows`, `icon`, `alias`. `sesh list` merges live tmux sessions with zoxide results, `sesh connect {session}` attaches or creates. It is now multiplexer-agnostic via a `tmux_command` key in `sesh.toml` (documented for psmux). **Port:** `smart_workspace_switcher.wezterm` and `workspace-picker.wezterm` already do the zoxide-fuzzy-workspace thing for WezTerm (section 8d). The `startup_command` plus `preview_command` pair is the bit worth adding to `wz`: a preview command lets your picker show the last 20 lines of the agent pane while you scroll the list, which is what makes `falcode-zellij` and agent view usable.

---

3. Ghostty
==========

Releases: 1.1.0 through 1.1.3 and 1.2.0 through 1.2.3 in 2025; **1.3.0 on 9 March 2026 and 1.3.1 on 13 March 2026** (https://ghostty.org/docs/install/release-notes). Nothing since March 2026 at time of writing.

From the 1.3.0 notes (https://ghostty.org/docs/install/release-notes/1-3-0):

- **AppleScript automation on macOS, preview only.** `tell application "Ghostty"` can send text and inspect windows and tabs. The notes explicitly say it is preview in 1.3 and to expect breaking changes in 1.4. This is Ghostty's first real programmatic control surface, and it is still well behind `wezterm cli` and `kitty @`. **Nothing to port; you are ahead here.**
- **libghostty** has been extracted as a standalone Zig module with a work-in-progress C API, separately versioned from the app. Dozens of projects already consume it. This matters mainly because it is what cmux is built on (section 6b).
- **Command-finished notifications**: `notify-on-command-finish`, `notify-on-command-finish-action` (`bell` or `notify`), `notify-on-command-finish-after` (default 5 s). Built on an improved OSC 133 implementation. **This is a genuinely good idea and directly portable.** In `wezterm.lua`, use the OSC 133 zones plus a timer to detect "a foreground command in an unfocused pane has been running more than N seconds and just ended", and fire a toast. WezTerm supports OSC 9 (`printf "\e]9;%s\e\\" "hello there"`) and the OSC 777 notify extension for toasts (https://wezterm.org/escape-sequences.html), and on macOS toasts go through `UNUserNotificationCenter`.
- **Quick terminal** now exports `GHOSTTY_QUICK_TERMINAL` so your prompt can render differently in the dropdown. **Port:** WezTerm has no built-in dropdown; the pattern people use is a dedicated `--class` window plus a system hotkey (skhd, Hammerspoon). Exporting a marker env var into it so your prompt and `cc-board` know they are in the scratch window is a nice cheap touch.
- Split drag-and-drop on macOS (processes move with the split), `goto_window:next` / `goto_window:previous`, `split-preserve-zoom` with a `navigation` mode, `resize_split` and `toggle_split_zoom` returning false with a single pane so the key passes through to the TUI. **That last one is subtle and worth copying:** with one pane, the split keybinding should fall through to the agent rather than being swallowed. In WezTerm, return `false` from a key-table callback or use `wezterm.action.Multiple` with a conditional in an `action_callback`.
- **Key tables**: modal keybinding via `<name>/<binding>` syntax activated with `activate_key_table:resize`; **chained keybinds** via a `chain` key; `catch_all` for unbound input (e.g. `ctrl+catch_all=ignore`); `end_key_sequence`. WezTerm already has `key_tables` and `wezterm.action.Multiple`, so you are level.
- Kitty `click-events` and `cl=line` extensions for clickable prompts in Fish 4.1+ and Nushell 0.111+.

**Bottom line on Ghostty:** no session API, no IPC comparable to `kitty @` or `wezterm cli`, no agent features. Notably, **Claude Code's Agent Teams split-pane mode explicitly does not work in Ghostty** (https://code.claude.com/docs/en/agent-teams). The only thing worth stealing is `notify-on-command-finish`.

---

4. Warp
=======

4a. Agents and orchestration
------------------------------

https://docs.warp.dev/agents/using-agents. "You can run multiple Agent Mode conversations simultaneously in different windows, tabs, or panes", each with its own context window and token budget. The **Conversation Panel** is the management surface: an *Active* section (conversations you have sent at least one query to) and a *Past* section with timestamps and working directories, searchable by title, with the currently-viewed conversation highlighted.

From the 2026 changelog (https://docs.warp.dev/changelog/2026):

- Earlier 2026: **orchestration with multi-level agent hierarchies** and **orchestrated child-agent status chips**, plus agent CLI commands for memory and runner management, and persistent TUI prompt history.
- 2026.06.17: `/rename-conversation`; git operations over remote sessions; **auto-handoff prompt when the computer sleeps during a local agent run**.
- 2026.06.10: **terminal commands can be queued alongside prompts**; improved shell versus natural-language detection.
- 2026.07.03: **Tab Groups**, collapsible coloured groups of tabs with keyboard shortcuts. 2026.07.23: pin individual tabs and tab groups to keep them front-facing; native `omp` integration; TUI renders alt-screen apps.
- 2026.08.18 and 2026.09.02: Warp Factories in early access, a built-in Factory MCP server, `oz agent run-cloud` with title and parent-run-id, debugging agents in failed cloud runs, live connection indicators, copyable agent thoughts.

There is also a standalone `warp` Agent CLI (https://docs.warp.dev/agents/cli), a terminal program that runs the Warp Agent with shell execution, permissions and **cloud handoff**, with slash commands `/status`, `/upgrade`, `/manage-billing`, `/tui-migrate-setup`.

**UX ideas worth stealing, ranked:**

1. **Child-agent status chips.** A compact inline row of coloured chips showing each spawned child's state, rendered next to the parent. Directly portable to `format-tab-title`: render one glyph per agent in the tab, coloured by state, rather than one glyph for the tab.
2. **Auto-handoff prompt when the machine sleeps.** You already have `cc-handover`. Wire it to a sleep hook: on macOS, `pmset -g log` watching or a `caffeinate`/Hammerspoon sleep callback that snapshots every working agent's state into a handover note before the lid closes. This is the single most original idea in Warp's 2026 line-up.
3. **Queue terminal commands alongside prompts.** A per-pane FIFO in `wz` so you can enqueue "when this agent finishes, run the tests" without waiting at the keyboard. Implement as a marker file the `Stop` hook drains.
4. **Tab Groups, collapsible and coloured, plus pinning.** WezTerm has no tab grouping. Approximate with workspaces (`wezterm cli rename-workspace`, `--workspace` on spawn) plus a colour convention in `format-tab-title`. Pinning maps to your `parked` concept.
5. **Active versus Past split with cwd and timestamp.** The right default sort for `cc-board`: never sort purely alphabetically; sort by state then recency, and always show the working directory, because with many agents the cwd is the only reliable identifier.

4b. Warp Drive and workflows
------------------------------

Warp Drive holds saved workflows, notebooks, environment variables and prompts. The reusable-parameterised-command idea is already served for you by Claude Code skills and slash commands, so there is little to port.

4c. Launch configurations: steal the schema
---------------------------------------------

https://docs.warp.dev/terminal/sessions/launch-configurations. YAML files in `$HOME/.warp/launch_configurations/` on macOS (`${XDG_DATA_HOME:-$HOME/.local/share}/warp-terminal/launch_configurations/` on Linux):

```yaml
---
name: Example Active and Focus
active_window_index: 0
windows:
  - active_tab_index: 1
    tabs:
      - title: Tab 1
        color: Blue           # Red Green Yellow Blue Magenta Cyan
        layout:
          split_direction: vertical
          panes:
            - cwd: /Users/warp-user/Documents
              is_focused: true
              commands:
                - exec: claude --name api
            - cwd: /Users/warp-user/Documents/Projects
```

Keys: top level `name`, `active_window_index`, `windows`; window `active_tab_index`, `tabs`; tab `title`, `color`, `layout`; layout `cwd`, `split_direction`, `panes`, `commands`, `is_focused`; command `exec`. Note the docs give no CLI or URI launcher, which is a weakness.

**Port:** this is a better shape for `cc-fleet` than Zellij's KDL for your purposes, because it is YAML (trivial to emit and consume from bash with `yq`), it has explicit focus and active-index semantics, and `color` per tab gives you a free visual grouping key. Define `~/.config/cc-fleet/*.yaml` in this schema and have `cc-fleet up <name>` walk it emitting `wezterm cli spawn --new-window`, `wezterm cli split-pane --horizontal|--vertical --cwd`, `wezterm cli set-tab-title`, and a final `wezterm cli activate-pane --pane-id` for the `is_focused` pane.

---

5. Kitty
========

5a. Remote control: `kitty @`
-------------------------------

https://sw.kovidgoyal.net/kitty/remote-control/

Enabled in `kitty.conf` with `allow_remote_control yes` (or `password`), `remote_control_password "control colors" get-colors set-colors` for scoped per-password permissions, and `listen_on unix:/tmp/mykitty`. Or at launch:
```bash
kitty -o allow_remote_control=yes --listen-on unix:/tmp/mykitty
```
Then `kitten @ [--to ADDRESS] [--password|--password-file|--password-env] [--match CRITERIA] <cmd>`.

The **match expression language** is the standout feature. Fields `id`, `title`, `pid`, `cwd`, `cmdline`, `num`, `env`, `state`, `recent`, `var`, combined with boolean operators and regex:
```bash
kitten @ send-text --match 'title:^Output' "Hello"
kitten @ ls --match 'title:bash and env:USER=kovid'
kitten @ close-window --match all
```

**Port:** `wezterm cli` has only `--pane-id` and `--class`. Write a `wz sel` helper that reads `wezterm cli list --format json` and filters with `jq`, then feeds pane ids to the real commands:
```bash
wz_sel() { wezterm cli list --format json | jq -r --arg q "$1" '.[] | select(.title|test($q)) | .pane_id'; }
for p in $(wz_sel '^claude'); do wezterm cli send-text --pane-id "$p" --no-paste "$*"; done
```
That single helper gives you kitty's matching and, as a bonus, the broadcast kitten (below).

`kitten @ ls` returns a **JSON tree of OS windows, tabs and windows** with ids, titles, pids and working directories: richer than `wezterm cli list --format json`, which emits only `window_id, tab_id, pane_id, workspace, size{rows,cols}, title, cwd`. Notably WezTerm omits the pid and the foreground command, so you cannot tell from the JSON alone which panes are running an agent. **Fix:** have `cc-spawn` write a registry line per pane (`pane_id`, agent name, cwd, started_at, cmd) to `~/.local/state/cc-fleet/panes/<pane_id>.json`, and have `cc-board` join that against `wezterm cli list`. Prune entries whose pane id no longer appears.

5b. `kitty @ launch --watcher`: push callbacks
------------------------------------------------

https://sw.kovidgoyal.net/kitty/launch/

`--watcher` points at a Python file whose appropriately-named functions are called on window events:

| Callback | Fires on | Data dict |
|---|---|---|
| `on_load` | watcher module first loads | init |
| `on_resize` | window resized | `old_geometry`, `new_geometry` |
| `on_focus_change` | focus changes | `focused` |
| `on_close` | window closes | |
| `on_set_user_var` | user var set or deleted | `key`, `value` |
| `on_title_change` | title changes | `title`, `from_child` |
| `on_cmd_startstop` | shell command starts or stops | `is_start`, `cmdline`, `time` |

`--type` values: `window`, `tab`, `os-window`, `overlay`, `overlay-main`, `background`, `clipboard`, `primary`, `os-panel`. Plus `--hold` (keep the window open at a shell prompt after the command exits), `--var name=value` (set user vars on the new window), `--cwd` with special values `current`, `last_reported`, `oldest`, `root`, and `--copy-env`.

**Port.** `on_set_user_var` maps exactly onto WezTerm's `user-var-changed`, so you already have the important one. `on_cmd_startstop` is derivable from OSC 133 if your bash emits it. `--hold` is the big miss: when a spawned agent crashes, the WezTerm pane vanishes and you lose the error. **Fix in `cc-spawn`:** always wrap, `wezterm cli spawn -- bash -lc 'claude "$@"; ec=$?; printf "\n[exit %d] press enter to close\n" "$ec"; read -r' _ "$@"`. Combine with a user-var emit of the exit code so `cc-board` can render a red state rather than a disappeared pane. `--type=overlay` is the popup-over-this-pane surface WezTerm lacks; nearest is `InputSelector`.

5c. OSC 99 desktop notifications
----------------------------------

https://sw.kovidgoyal.net/kitty/desktop-notifications/. Format `<ESC>]99;metadata;payload<ESC>\` with colon-separated `key=value` metadata; **both semicolons are always required**.

| Key | Values | Default | Purpose |
|---|---|---|---|
| `i` | identifier | unset | notification id, for updates and response routing |
| `d` | 0/1 | 1 | done flag; 0 means more chunks follow |
| `p` | title, body, close, icon, ?, alive, buttons | title | payload type |
| `a` | report, focus (optional `-` prefix to disable) | focus | action on click |
| `o` | always, unfocused, invisible | always | when to show |
| `u` | 0/1/2 | unset | urgency low/normal/critical |
| `c` | 0/1 | 0 | request close event |
| `w` | >= -1 | -1 | auto-close ms |
| `e` | 0/1 | 0 | payload is base64 |
| `f` | base64 UTF-8 | unset | application name |
| `g` | identifier | unset | icon cache id |
| `n` | base64 UTF-8 | unset | icon name (repeatable) |
| `t` | base64 UTF-8 | unset | notification type (repeatable) |
| `s` | base64 UTF-8 | system | sound name |

```bash
printf '\x1b]99;;Hello world\x1b\\'
printf '\x1b]99;i=1:d=0;Hello world\x1b\\'
printf '\x1b]99;i=1:p=body;This is cool\x1b\\'
```
Buttons use `p=buttons` with entries separated by U+2028 Line Separator; a click sends `<ESC>]99;i=<id>;<button_number><ESC>\` back to the application. `a=focus` focuses the originating window on click; `a=report` sends an escape back instead.

**This is the best notification protocol in the field and it is exactly what an agent fleet needs:** urgency levels, per-notification sounds, click-to-focus-the-right-pane, and actionable buttons that route the answer back to the agent.

**WezTerm does not support OSC 99** (https://wezterm.org/escape-sequences.html). It supports OSC 9 (`printf "\e]9;%s\e\\" "hello there"`) and the OSC 777 notify extension, both of which are title-and-body toasts with no id, no urgency, no buttons and no click routing. **Port:** on macOS use `terminal-notifier` from your `cc-state` dispatcher, which supports `-title`, `-subtitle`, `-sound`, `-group` (dedupe and replace, the OSC 99 `i` equivalent) and `-execute` (the click action, where you run `wezterm cli activate-pane --pane-id N`). That gets you click-to-focus and dedupe, which are the two properties that actually matter. `wezterm-agent-deck` already offers `terminal-notifier` as a backend with sound support.

5d. Broadcast and panel kittens
---------------------------------

The broadcast kitten types the same input into many windows at once (https://sw.kovidgoyal.net/kitty/kittens/broadcast/); the panel kitten draws a window as a desktop panel or bar (https://sw.kovidgoyal.net/kitty/kittens/panel/), and 1.3-era kitty exposes `--type=os-panel` on `launch` directly. Custom kittens are plain Python (https://sw.kovidgoyal.net/kitty/kittens/custom/).

**Port broadcast:** three lines of bash on top of `wz sel` (5a). Worth having as `wz all "<message>"` for "every agent, stop what you are doing and re-read CLAUDE.md". **Port panel:** a persistent always-on-top `cc-board` strip is achievable on macOS only via a separate always-on-top window (Hammerspoon) since WezTerm has no panel mode; probably not worth it given the tab-title rendering path.

---

6. New in 2026: purpose-built agent multiplexers
=================================================

An entire product category appeared in 2025-2026 (https://amux.io/guides/best-ai-agent-multiplexers-2026/). The ones with mechanisms worth copying:

6a. herdr: the reference design
---------------------------------

https://github.com/ogulcancelik/herdr, docs at https://herdr.dev/docs/. Single Rust binary, roughly 10 MB, no dependencies, Linux/macOS/Windows beta. Roughly 15,000 GitHub stars in about 105 days, number one on GitHub Trending on 30 June 2026. It is explicitly positioned as a tmux replacement for agents: "every pane is marked working, blocked, or idle. when an agent stops and needs an answer, herdr says so." Runs as a background server with the terminals inside it, `ctrl+b q` detaches and `herdr` reattaches, sessions survive lid close, network drop and machine restart.

**State detection model** (https://herdr.dev/docs/agents/) is the part to copy. Two-tier, with an explicit rule against split-brain:

- Detect the foreground process in each pane. Each pane then has **one status authority**.
- If the agent has complete lifecycle hooks and the integration is installed, hooks are authoritative and **the screen-scraping fallback is not run concurrently**, "avoiding two competing sources of truth".
- Otherwise, read the "live bottom-buffer screen snapshot" and evaluate **TOML manifests** against it to classify `idle` / `working` / `blocked`.

Supported out of the box: Pi, OMP, GitHub Copilot CLI, Devin CLI, Kimi Code CLI, Hermes Agent, Qoder CLI, Qwen Code, Droid, OpenCode, Kilo Code CLI, MastraCode, Claude Code, Codex, Cursor Agent CLI, Amp, Grok CLI, Antigravity CLI, Kiro CLI.

Custom labels and self-reporting:
```bash
herdr agent rename w1:p1 reviewer
herdr agent rename reviewer --clear
herdr pane report-agent w1:p1 --source custom:indexer --agent docs-bot --state working
herdr pane report-metadata w1:p1 --source custom:indexer-display --token summary=indexing
```
where `$summary` is then usable in an Agent sidebar row.

**Socket API** (https://herdr.dev/docs/socket-api) is newline-delimited JSON over a Unix socket at `~/.config/herdr/herdr.sock`, or `~/.config/herdr/sessions/<name>/herdr.sock` for named sessions, resolved in order: `--session <name>` flag, `HERDR_SOCKET_PATH`, `HERDR_SESSION`, default.

```json
{"id":"req_1","method":"ping","params":{}}
{"id":"req_1","result":{"type":"pong"}}
{"id":"req_1","error":{"code":"not_found","message":"pane not found"}}
{"id":"req_input","method":"pane.send_text","params":{"pane_id":"w1:p1","text":"npm test"}}
{"id":"sub_1","method":"events.subscribe","params":{"subscriptions":[{"type":"pane.agent_status_changed","pane_id":"w1:p1"}]}}
```
```bash
herdr pane read w1:p2 --source recent --lines 50
herdr agent wait w1:p1 --until done
herdr api snapshot
herdr api schema --json --output herdr-api.schema.json
```
Method families: workspace, tab, pane (split, swap, move, resize, zoom, read, send input), agent (list, read, prompt, wait, report custom state), session snapshot, events, plugins. Event types cover workspace and tab lifecycle, pane updates, agent state, **output matches**, and layout changes.

Config is TOML at `~/.config/herdr/config.toml` (https://herdr.dev/docs/configuration/), hot-reloaded with `herdr server reload-config`:
```toml
[keys]
prefix = "ctrl+b"
goto = "prefix+g"
new_tab = "prefix+c"

[ui.toast]
delivery = "herdr"      # herdr | terminal | system | off
delay_seconds = 1

[ui.toast.herdr]
position = "bottom-right"

[ui.sidebar.agents]
rows = [["state_icon", "workspace", "tab"], ["agent"]]
```

**What to steal for your bash fleet, concretely:**

1. **`herdr agent wait <pane> --until done`.** This is the single most useful missing verb. Implement `wz wait <pane_id> [--until done|blocked]` as a bash loop over your state files with a timeout. It turns `cc-fleet` from a spawner into an orchestrator: `wz wait api done && wz send reviewer "api is ready, review it"`.
2. **One status authority per pane.** Do not let hook-driven state and screen-scraped state fight. Record a `source` field alongside state, and have the scraper refuse to write when a hook has reported within the last N seconds.
3. **`api snapshot` and `api schema`.** Give `cc-board` a `--json` snapshot mode with a stable, documented shape, so future scripts and Claude sessions can consume it without parsing your TUI.
4. **`report-metadata --token summary=...`** as a display-only channel separate from state. Lets an agent say what it is doing without lying about whether it is blocked. Pairs perfectly with your `cc-note`.
5. **Toast delivery as a config choice** (`herdr` / `terminal` / `system` / `off`) rather than hardcoded. You will want `off` while pairing and `system` while away.
6. **Delivery delay** (`delay_seconds = 1`) to suppress flapping states.

6b. cmux
---------

https://github.com/manaflow-ai/cmux. Native macOS app in Swift and AppKit, **not a fork of Ghostty**: it "uses libghostty as a library for terminal rendering, the same way apps use WebKit for web views". No tmux, no containers, no worktrees; native macOS splits. Reads your existing Ghostty config for themes and fonts. Notifications via OSC 9, 99 and 777. Ships an embedded browser pane with a scriptable API.

Crucially: "When an agent spawns subagents or teammates, cmux turns them into native panes and splits instead of hidden background processes. It supports Claude Code teams", and `cmux claude-teams` "runs Claude Code's teammate mode with one command. Teammates spawn as native splits with sidebar metadata and notifications."

**This is the design target.** The equivalent for you is `wezcld` (section 8a), which achieves the same thing with a 200-line shim.

6c. Others
-----------

- **amux**, an overloaded name with at least four projects: `prettysmartdev/amux` (container-isolated agents, multi-step workflows, fleets of machines), `andyrewlee/amux` (TUI, workspace-first, imports git worktrees, **each agent in its own tmux session** for isolation and persistence), `choplin/amux` (isolated git worktree environments), `jordanwebster/amux`.
- **Conductor**, from the Melty team, launched April 2026 (GUI).
- **workmux** and **Claude Squad**, covered in 2d.

The consistent architecture across all of them: **one git worktree plus one pane or session per task, with hook-driven three-state status rolled up into a sidebar.** If your fleet does not already put each agent in its own worktree, that is the highest-value structural change; note that Claude Code now does this automatically for background sessions (section 7c).

---

7. Claude Code's own multiplexer-shaped features (2026)
=======================================================

This is the most important section for you, because Anthropic has shipped features that overlap directly with what your scripts hand-roll, and one of them has a hard multiplexer dependency that excludes WezTerm.

7a. Agent Teams: split-pane mode requires tmux or iTerm2
----------------------------------------------------------

https://code.claude.com/docs/en/agent-teams

Experimental and off by default; enable with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings `env` or the environment. One session is the lead; teammates are full independent Claude Code sessions with their own context windows, a shared task list with file-locked claiming and dependencies, and a mailbox.

Display modes, set via `teammateMode` in `~/.claude/settings.json` or `claude --teammate-mode <mode>` (the flag is experimental and absent from `--help`):

- `"in-process"` (**the default since v2.1.179**): all teammates in one terminal, navigated with arrow keys in the agent panel below the prompt, Enter to view and message, `x` to stop, Ctrl+T for the task list.
- `"auto"`: split panes if already inside tmux, or iTerm2 with the `it2` CLI installed; otherwise in-process.
- `"tmux"`: split panes, auto-detecting tmux versus iTerm2.
- `"iterm2"` (v2.1.186+): iTerm2 native splits, requires the `it2` CLI (https://github.com/mkusaka/it2) and Python API enabled in iTerm2 Settings, General, Magic.

The docs are blunt: "Split-pane mode isn't supported in VS Code's integrated terminal, Windows Terminal, or Ghostty", and "`tmux` has known limitations on certain operating systems and traditionally works best on macOS. Using `tmux -CC` in iTerm2 is the suggested entrypoint". **WezTerm is not a supported split-pane host.** Community reporting of the underlying tmux calls names `split-window`, `send-keys`, `kill-pane`, `list-panes`, `has-session`, `display-message`.

Team state lives at `~/.claude/teams/{team-name}/config.json` where team-name is `session-` plus the first eight characters of the session id, mailboxes at `~/.claude/teams/{team-name}/inboxes/{agent-name}.json`, task list at `~/.claude/tasks/{team-name}/`. **The team config "holds runtime state such as session IDs and tmux pane IDs, so don't edit it by hand".** The team config directory is removed at session end; the task directory persists under `cleanupPeriodDays`.

Quality-gate hooks: `TeammateIdle` (exit 2 to send feedback and keep the teammate working), `TaskCreated` (exit 2 to block creation), `TaskCompleted` (exit 2 to block completion).

Gotcha worth knowing: with agent teams enabled, **any subagent Claude names launches as a teammate**, so teams form even when you did not ask. Set the env var to `0` to revert; the change applies to a running session on save.

**Action for you:** either use `wezcld` (7 lines below, section 8a) to make split-pane teammates work in WezTerm, or accept in-process mode. Note that `~/.claude/teams/*/config.json` and `~/.claude/tasks/*/` are readable state that `cc-board` can display today with no shimming at all.

7b. Cross-session messaging: you may be able to delete code
-------------------------------------------------------------

https://code.claude.com/docs/en/cross-session-messaging. Requires v2.1.224+ on macOS/Linux/WSL2, v2.1.234+ on native Windows. On by default where available.

Every session binds an **inbox socket**, a Unix domain socket on macOS and Linux, exported to hooks and Bash commands as **`CLAUDE_CODE_MESSAGING_SOCKET`** (before any hook runs, including `SessionStart`), with a per-session token in **`CLAUDE_CODE_MESSAGING_TOKEN`**. `/status` shows the path in a `Peer address` row prefixed `uds:`. If the socket directory is unacceptable Claude Code falls back to a private per-user directory `/tmp/cc-socks-<uid>`.

**A script or hook can post directly into a session:**
```
{"type":"auth","token":"<CLAUDE_CODE_MESSAGING_TOKEN>"}
```
as the first line of the connection (optional on macOS/Linux, required on native Windows), then the message. Open the connection only when the message is ready: Claude Code closes a connection that has not sent a complete line within 30 seconds.

Discovery is `/list-agents` (alias `/peers`), listing subagents, teammates, other local sessions (including background sessions), cloud sessions and Remote Control sessions on other machines, with the first line being this session's own name. Sessions are named with `--name` or `/rename`; duplicates get renamed to a variant. Users address a target by typing `@` plus the first letters, with a typeahead (v2.1.232+).

**`notify_when_idle`** (v2.1.236+): a session can subscribe to a **one-shot notice when another local session next goes idle or exits**, without starting a turn or spending tokens in the watched session, and it fires immediately if that session is already idle. The subscription is dropped after 12 hours. Only the main conversation can subscribe, and only to local sessions.

Inbound controls via `crossSessionInbound`: `accept` / `hold` / `refuse`, selectable in `/config` under "Messages from your other sessions". The default, when nothing is set, keys off permission-mode class: a bypass-permissions session **holds** messages from non-bypass senders for approval, and vice versa. Limits: plain text only, roughly one million characters, burst refusal at the sender, loop throttling with identical-repeat dropping and a 50-message queue cap. `isolatePeerMachines: true` requires approval before any message leaves the machine.

**Action for you:** your `cc-note` and any pane-to-pane message passing in `cc-fleet` may now be redundant. `notify_when_idle` in particular replaces polling `cc-board` for "is agent X done yet". Two practical notes: a `-p` worker needs `crossSessionInbound: "accept"` in its `--settings` to take messages unattended; and if you run agents with `--dangerously-skip-permissions`, the default inbound rule will silently *hold* messages from your ordinary sessions, so set `crossSessionInbound` explicitly across the fleet or you will wonder why messages vanish.

7c. Agent view: a full background-session manager
---------------------------------------------------

https://code.claude.com/docs/en/agent-view. This is, functionally, `cc-board` shipped by Anthropic.

```bash
claude agents                                  # open the view
claude agents --cwd ~/projects/my-app          # scoped
claude agents --json [--all]                   # machine-readable
claude --bg "investigate the flaky test"
claude --bg --name "flaky-test-fix" --model opus "..."
claude --bg --agent code-reviewer "address review comments on PR 1234"
claude --bg --exec 'pytest -x'
claude attach <id> | claude logs <id> | claude stop <id> | claude kill <id>
claude respawn <id> | claude respawn --all | claude rm <id>
claude daemon status | claude daemon stop --any [--keep-workers]
```
From inside a session: `/bg [instruction]`, `/fork [instruction]`, and `←` on an empty prompt backgrounds the session and opens agent view.

State icons: `✽` animated working, `✻` yellow needs input, `∙` dimmed idle, green tick completed, red failed, grey stopped. Process shapes distinguish a live process (`✻`/`✽`) from an exited one that resumes on reply (`∙`) from a `/loop` session sleeping (`✢`).

Keys: arrows to move, Enter to attach or dispatch, **Space to open the peek panel** (shows the question or result, type a reply and Enter, number keys for predefined choices, Tab for a suggested reply, `!` prefix to send a Bash command, arrows to peek adjacent sessions, `→` to attach), Ctrl+S to toggle grouping between state and directory, Ctrl+T to pin (keeps the process running), Ctrl+R rename, Ctrl+G open the dispatch input in `$EDITOR`, Ctrl+X stop (twice within 2 s to delete), Shift+arrows reorder, `?` for all shortcuts. Alt+1 to Alt+9 attach to sessions 1-9 in the current directory.

Grouping by default: Pinned, Ready for review, Needs input, Working, Completed. Filters in the dispatch input: `a:<name>` by agent, `s:<state>`, `#<number>` or PR URL, any URL.

**File isolation:** background sessions automatically move into git worktrees under `.claude/worktrees/` before editing, unless already in a linked worktree or not in a git repo. Disable with `{"worktree": {"bgIsolation": "none"}}`.

Supervisor state: `~/.claude/daemon.log`, `~/.claude/daemon/roster.json`, `~/.claude/jobs/<id>/state.json`, `~/.claude/jobs/<id>/tmp/`. Sessions idle and unattached for over an hour have their process stopped and resume on attach; pin to prevent.

`claude agents --json` schema:
```json
{"cwd":"/path/to/repo","kind":"background","startedAt":1234567890000,"id":"7c5dcf5d",
 "state":"working","pid":12345,"status":"working","sessionId":"uuid","name":"flaky-test-fix"}
```
with `state` in `working|blocked|done|failed|stopped` and a `waitingFor` field carrying `permission prompt`, `input needed`, `sandbox request`.

Disable with `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` or `{"disableAgentView": true}`.

**Action for you, and this is the biggest one in the report: `claude agents --json --all` is a free, authoritative, structured feed of every agent's state, and it requires no hooks, no screen scraping and no multiplexer support.** `cc-board` should consume it directly. What it does *not* give you is the mapping from session to WezTerm pane, so keep your own `pane_id` to `sessionId` registry (written by `cc-spawn` from `$WEZTERM_PANE` and the session id) and join on that. Steal the peek panel (reply without attaching), the state grouping order, and the `waitingFor` reason string.

7d. Remote Control
--------------------

https://code.claude.com/docs/en/remote-control. `claude remote-control` runs a **server** that serves sessions on demand to claude.ai/code or the mobile apps, with execution staying local:
```
--name "My Project"
--remote-control-session-name-prefix <prefix>   (default: hostname, giving myhost-graceful-unicorn)
--spawn <mode>      same-dir (default) | worktree (each session gets its own git worktree) | session (single-session)
--capacity <N>      max concurrent sessions, default 32
-c, --continue      or --session-id <id> to bring back a session
```
Press `w` at runtime to toggle `same-dir` versus `worktree`, spacebar for a QR code. Or `claude --remote-control` / `--rc [name]` for an interactive session that is also remotely controllable, showing a `/rc active` footer indicator linking to the session, with `/remote-control` opening a status panel with URL and QR.

**This is Zellij's web client, done better and with worktree isolation built in.** If "watch the fleet from my phone" is on your list, `claude remote-control --spawn worktree --capacity 8` is the answer, not a WezTerm web gateway.

7e. Hooks: the full event surface
-----------------------------------

https://code.claude.com/docs/en/hooks. Every agent-status tool surveyed above is built on a handful of these. The complete list:

`SessionStart`, `Setup`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `MessageDisplay`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `DirectoryAdded`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `Elicitation`, `ElicitationResult`, `SessionEnd`.

Config schema:
```json
{"hooks": {"EVENT_NAME": [{"matcher": "Bash|Edit", "hooks": [
  {"type": "command", "if": "Bash(git *)", "command": "/path/to/script.sh",
   "args": [], "async": false, "asyncRewake": false, "shell": "bash",
   "timeout": 600, "statusMessage": "Running validation..."}]}]}}
```
Matchers vary by event: tool name for tool events; `startup|resume|clear|compact|fork` for `SessionStart`; `permission_prompt|auth_success|elicitation_dialog` for `Notification`; agent type for `SubagentStart`/`SubagentStop`; `rate_limit|authentication_failed|server_error` for `StopFailure`; literal filenames for `FileChanged`. `UserPromptSubmit`, `PostToolBatch`, `Stop`, `CwdChanged`, `MessageDisplay` take no matcher and always fire.

Common stdin JSON: `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `agent_id`, `agent_type`, `effort.level`; tool events add `tool_name`, `tool_input`, `tool_use_id`. Env vars available: `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_EFFORT`, `CLAUDE_PLUGIN_OPTION_<KEY>`, plus `CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN` from 7b. There is no `$CLAUDE_MODEL`.

Note `"async": true` and `"asyncRewake"` on the hook object: a status-writing hook should be async so it never adds latency to the agent's turn. None of the surveyed projects mention using it, and they should.

**Minimum viable state machine, as used by every tool above:** `UserPromptSubmit` and `PreToolUse` to `working`; `PermissionRequest` and `Notification` to `blocked`; `Stop` to `idle` or `done`; `SubagentStart`/`SubagentStop` to maintain a counter so a subagent's tool use does not clear a `blocked` state; and check `Stop`'s `background_tasks` array so a turn ending with a live background task stays `working`.

---

8. The WezTerm agent ecosystem that already exists (2026)
=========================================================

Most of the porting work has been done. From https://github.com/michaelbrusegard/awesome-wezterm and direct repo reads.

8a. wezcld: Agent Teams split panes in WezTerm
------------------------------------------------

https://github.com/afewyards/wezcld. **This closes the gap in 7a.** Three parts: a launcher that sets `TERM_PROGRAM=iTerm.app`, puts the shim's `bin/` first on `PATH`, and execs `claude --teammate-mode tmux`; a shim at `bin/it2` that intercepts iTerm2 CLI calls and translates them; and a layout engine arranging agent panes in a 3-column grid with the leader pane at the bottom.

| `it2` call | translated to |
|---|---|
| `--version` / `app version` | prints `it2 0.2.3` |
| `session split [-v]` | `wezterm cli split-pane` (grid layout) |
| `session run -s <id> <cmd>` | `wezterm cli send-text --pane-id <id>` |
| `session close -s <id>` | `wezterm cli kill-pane --pane-id <id>` |
| `session list` | minimal session table |
| everything else | silent success, exit 0 |

Install: `curl -fsSL https://github.com/afewyards/wezcld/releases/latest/download/install.sh | sh`

The technique generalises: **any tool that hard-codes tmux or iTerm2 can be redirected to WezTerm by shimming the four verbs split, run, close, list.** Worth reading the shim and vendoring the idea into `wz` rather than depending on the project, since it pins `it2 0.2.3` and Claude Code's iTerm2 support is a moving target.

8b. wezterm-agent-cards
------------------------

https://github.com/wrock/wezterm-agent-cards. Explicitly cmux-inspired: a sidebar of navigation cards highlighted when an agent needs you.

State comes from two priority-ordered sources. Primary: **eight Claude Code lifecycle hooks auto-registered from `hooks/hooks.json`, all running `hooks/status-hook.sh`, which writes per-pane status to `/tmp/wezterm-hook-<pane_id>.json`.** `UserPromptSubmit` and `PostToolUse` to working; `PermissionRequest`, `Notification` and `Stop` to waiting; `SubagentStart`/`SubagentStop` maintain a counter so subagent tool use does not clear a waiting status. Fallback: the agent-deck plugin's output pattern matching, used until hooks have fired.

```lua
local agent_cards = dofile(os.getenv('HOME') .. '/.claude/plugins/wezterm-agent-cards/wezterm/init.lua')
agent_cards.apply_to_config(config, { agent_deck = agent_deck, sidebar_cols = 26 })
```
The sidebar itself is a **Python curses app** (`wezterm/sidebar.py`) spawned into a pane, reading both status sources: green working, pink waiting, dim inactive.

**Note the architectural choice: the sidebar is a normal pane running a TUI, not Lua.** That is the right call for WezTerm, since Lua only gets to paint tab titles and the status bar. Your `cc-board` should be the same shape: a pinned narrow pane running a bash or Python TUI.

8c. wezterm-agent-deck
-----------------------

https://github.com/Eric162/wezterm-agent-deck. Monitors Claude Code, OpenCode, Aider and others; status dots in tabs plus notifications.

```lua
local agent_deck = wezterm.plugin.require('https://github.com/Eric162/wezterm-agent-deck')
agent_deck.apply_to_config(config)
```
Detection is pure output pattern matching on a timer:
```lua
status_patterns = { working = { 'thinking' }, waiting = { 'y/n' } },
update_interval = 500,
```
States working / waiting / idle / inactive render as `{ working = '●', waiting = '◔', idle = '○', inactive = '◌' }` through `format-tab-title`:
```lua
wezterm.on('format-tab-title', function(tab)
  local state = agent_deck.get_agent_state(pane_info.pane_id)
  table.insert(formatted, { Foreground = { Color = agent_deck.get_status_color(state.status) } })
```
Public API: `get_agent_state(pane_id)`, `update_pane(pane)`, `count_agents_by_status()`. Notifications via native WezTerm toasts or `terminal-notifier` on macOS with sound, triggered by `on_waiting = true`.

8d. The rest, mapped to their tmux/Zellij equivalents
-------------------------------------------------------

| WezTerm plugin | Equivalent to | Mechanism |
|---|---|---|
| `pro-vi/wezterm-attention` | tmux `alert-*` hooks, zellij-attention | **File markers.** Any process writes `{"type":"<state>"}` to `~/.local/state/wezterm-attention/<WEZTERM_PANE>`. Poller runs on `update-status` (default 1000 ms), caches, requests redraw; renderer runs on `format-tab-title` with **zero I/O**. States `thinking` (animated `◌◔◑◕`, violet), `stop` (`✓`, mint), `notify` (`!`, rose), `review` (`◆`, gold, Alt+B). **Focusing a pane acknowledges only that pane's `stop` and `notify`** via plugin-owned `.ack` sidecars; `thinking` persists until its writer removes it or a 30-minute TTL expires. Options: `renderer` ("tab" or "manual"), `dir`, `colors`, `indicators`, `stale_after_ms`, `review_key`, plus `attention.wrap_title_formatter()` for custom tab formatting. |
| `MLFlexer/resurrect.wezterm` | tmux-resurrect + continuum, Zellij session serialization | Saves workspace/window/tab/pane layout, per-pane cwd, running processes, and shell output text as JSON. `resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())`; `resurrect.workspace_state.restore_workspace(resurrect.state_manager.load_state(id, "workspace"), opts)`; `resurrect.state_manager.periodic_save(opts)` every 15 min; `wezterm.on("gui-startup", resurrect.state_manager.resurrect_on_gui_startup)`; `change_state_save_dir(path)`; encryption via `set_encryption({enable=true, method="age", private_key=..., public_key=...})` supporting age, rage or gpg. |
| `MLFlexer/smart_workspace_switcher.wezterm`, `isseii10/workspace-picker.wezterm`, `vieitesss/workspacesionizer.wezterm`, `mikkasendke/sessionizer.wezterm` | sesh, tmux-sessionizer | zoxide-backed fuzzy workspace switching |
| `srackham/tabsets.wezterm` | tmuxinator | load, save, rename, delete named sets of tabs |
| `abidibo/wezterm-sessions`, `ryanmsnyder/workspace-manager.wezterm`, `JuanraCM/wsinit.wezterm` | tmuxinator / sesh | session save-restore and project navigation |
| `M-Marbouh/agent-quota.wezterm` | no competitor equivalent | Reads `~/.claude/.credentials.json` and calls the Anthropic OAuth usage endpoint; for Codex runs `codex app-server --listen stdio://` and reads `account/rateLimits/read`. Default `poll_interval_secs = 60`. Renders `Claude: 5h ███░░░░░ 42% (2h31m) ▪ 7d █░░░░░░░ 18% (4d12h)` with 8-cell bars (`bars.width`), green under 50%, yellow 50-79%, red 80%+, `compact = true` to hide countdowns, per-user JSON caches in `/tmp` to stop parallel windows all refreshing at once. |
| `EdenGibson/wezterm-quota-limit` | | Claude quota in the status bar with colour thresholds and token refresh |
| `adriankarlen/bar.wezterm`, `michaelbrusegard/tabline.wez`, `yriveiro/wezterm-status` | zjstatus, tmux status | configurable status and tab bars |

`wezterm-attention`'s **poller/renderer split with zero-I/O rendering** is the correct performance architecture, and its **file-marker contract** ("any CLI tool can signal by writing `{"type":"<state>"}` to `~/.local/state/wezterm-attention/$WEZTERM_PANE`") is the cleanest integration point in the whole survey. `$WEZTERM_PANE` is already in every pane's environment, so a Claude Code hook needs no arguments and no tty access to report. **This solves the OSC-to-tty problem cleanly and is what I would build on.**

---

9. What to build, in priority order
====================================

1. **Consume `claude agents --json --all` in `cc-board`** (7c). Free authoritative state with `state`, `status`, `waitingFor`, `cwd`, `name`, `pid`, `sessionId`. Join to WezTerm panes via a registry `cc-spawn` writes keyed on `$WEZTERM_PANE`.
2. **Adopt the file-marker contract** at `~/.local/state/cc-fleet/<WEZTERM_PANE>.json`, written by async Claude Code hooks, read by a poller on `update-status`, rendered zero-I/O in `format-tab-title` (8b, 8d). Use the minimum viable hook set from 7e, including the `background_tasks` and subagent-counter corrections.
3. **One neutral dispatcher script**, `cc-state`, that every hook calls and that decides the backend: marker file, WezTerm user var, notification, tmux option (2d, gentle-agent-state). Worst-state-wins rollup per tab: blocked beats working beats idle.
4. **`wz wait <pane|agent> --until done|blocked`** with a timeout (6a). Turns `cc-fleet` into an orchestrator. Consider `notify_when_idle` (7b) instead where the target is a Claude session, since it is push and costs no tokens.
5. **`wz sel` selector** over `wezterm cli list --format json` plus `jq`, giving you kitty's `--match` and broadcast for free (5a, 5d).
6. **Fix `cc-spawn` to hold on exit** and emit the exit code as a user var (5b). A crashed agent must leave a red pane, not vanish.
7. **A fleet picker on `InputSelector`** with `fuzzy = true`, single-key alphabet jumps, state glyphs in labels, and a preview of the last N lines (1j, 2d, 7c peek panel).
8. **Declarative fleet spec in Warp's launch-configuration YAML shape** (4c) driving `wezterm cli spawn/split-pane`, replacing imperative `cc-fleet` logic.
9. **Notifications with dedupe and click-to-focus** via `terminal-notifier -group <pane_id> -execute 'wezterm cli activate-pane --pane-id N'`, since WezTerm lacks OSC 99 (5c). Add a delivery mode setting and a 1 s debounce (6a).
10. **`wz scrollback <pane>`** dumping to a file and opening `$EDITOR` (1c), and **`wz logs`** by wrapping agents in `script -q -F` for durable per-agent transcripts (2b).
11. **Silence/stall detection**: flag any `working` pane whose content hash has not changed for 10 s as possibly interrupted (2b, 2d).
12. **If you want Agent Teams split panes**, vendor the `wezcld` `it2` shim (8a). If you want phone access, use `claude remote-control --spawn worktree` (7d) rather than building a web gateway.
13. **Worktree-per-agent** if you are not already doing it; Claude Code does it automatically for `--bg` sessions under `.claude/worktrees/` (7c), and every serious 2026 orchestrator does it (6).

Caveats on verification: everything above with an inline URL was fetched and read this session. Kitty coverage here is from `remote-control`, `launch` and `desktop-notifications` pages plus the changelog index; I did not independently verify the broadcast and panel kitten pages beyond their existence, and I did not read the full kitty 0.40-to-current changelog, so treat "recent kitty releases" as unverified. Ghostty coverage is the 1.3.0 release notes and the release-notes index; I did not read 1.1.x, 1.2.x or 1.3.1 individually. Warp coverage is `using-agents`, `launch-configurations`, `agents/cli` and the 2026 changelog index; the `oz` CLI referenced in changelog entries is not documented on the page I fetched, so its subcommand surface is unverified.

----

The Warp and Ghostty research has come back with source-verified detail that **corrects several points in my report above**. The kitty and tmux-ecosystem agent is still running.

Addendum and corrections
========================

C1. Correction, important: Claude Code hooks CAN emit escape sequences directly
-------------------------------------------------------------------------------

I hedged earlier that a hook cannot easily emit OSC to the pane because its stdout is consumed by Claude. That is only true on older versions. **Claude Code 2.1.141+ added a `terminalSequence` JSON output field for hooks**, letting a hook emit an escape sequence without a controlling terminal. Verified by reading `plugins/warp/scripts/emit-terminal-sequence.sh` in `github.com/warpdotdev/claude-code-warp`.

Their decision tree, worth copying verbatim:
- version >= 2.1.141: print `{"terminalSequence": "<seq>"}` on stdout
- version < 2.1.141: write the raw sequence to `/dev/tty`
- version unknown: try `/dev/tty`, fall back to the JSON field

The gotcha they document: emitting the unknown `terminalSequence` field to a `Stop` hook on a pre-2.1.141 version **fails validation** with `Stop hook error: JSON validation failed`. So the version gate is mandatory, not optional.

**This upgrades my recommendation.** OSC 1337 SetUserVar from hooks is now the first-class path, not the fallback, and the file-marker pattern becomes the compatibility shim rather than the primary design.

C2. The single most portable artefact in the whole survey: `warpdotdev/claude-code-warp`
-----------------------------------------------------------------------------------------

Warp open-sourced its client on 28 April 2026 (https://www.warp.dev/blog/warp-is-now-open-source), and its Claude Code integration is a readable open-source plugin at `github.com/warpdotdev/claude-code-warp`. Requires `jq`. Installed with:
```
/plugin marketplace add warpdotdev/claude-code-warp
/plugin install warp@claude-code-warp
/reload-plugins
```

Hooks registered, read verbatim from `plugins/warp/hooks/hooks.json`:
`SessionStart` (matcher `startup|resume`), `Stop`, `Notification` (matcher `idle_prompt`), `PermissionRequest`, `UserPromptSubmit`, `PostToolUse`.

Transport is **OSC 777 with the title field abused as a routing key**. `plugins/warp/scripts/legacy/warp-notify.sh` is literally:
```bash
printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY" > /dev/tty 2>/dev/null || true
```
called as `warp-notify.sh "warp://cli-agent" "$BODY"` where the body is JSON built by `build-payload.sh`:
```json
{"v":1,"agent":"claude","event":"stop|idle_prompt|...","session_id":"...","cwd":"...","project":"<basename cwd>"}
```

Two details to steal outright:
- **`on-stop.sh` sleeps 0.3 s before reading the transcript.** The `Stop` hook fires *before* the transcript is flushed to disk. It then jq-parses `.transcript_path` for the last human prompt and last assistant text block, truncating each to 200 chars as `query` and `response`. If your `cc-handover` or `cc-note` reads the transcript on `Stop`, you have this bug.
- **Capability negotiation**: `should-use-structured.sh` reads `WARP_CLI_AGENT_PROTOCOL_VERSION` and `WARP_CLIENT_VERSION` from the environment and falls back to plain text for old clients. Your equivalent is gating on `claude --version`.

There is a second plugin in the same repo, `plugins/oz-harness-support`, which bridges a child Claude run to a parent. `oz-parent-common.sh` gates on `OZ_CLI`, `OZ_RUN_ID`, `OZ_PARENT_RUN_ID`, and keeps a per-session state dir at `${OZ_PARENT_STATE_ROOT:-$HOME/.claude-code/oz-parent-bridge}/<session_id>/` with `staged/`, `surfaced/` and `pending-hook-output.json`. **That is a working, file-backed parent/child mailbox between Claude Code sessions with no server**, and it is a better reference design than anything I found earlier.

C3. Correction: Warp launch configurations are deprecated
----------------------------------------------------------

My section 4c gave the YAML launch-configuration schema. Warp's docs now say plainly "Launch Configurations have been replaced by Tab Configs". **Use the TOML Tab Config schema instead** (https://docs.warp.dev/terminal/windows/tab-configs/), stored one file per layout in `~/.warp/tab_configs/` (macOS), `%APPDATA%\warp\Warp\data\tab_configs\`, or `${XDG_DATA_HOME:-$HOME/.local/share}/warp-terminal/tab_configs/`.

Top level: `name` (required, appears in the `+` menu), `title` (supports `{{param}}`), `color`.
Leaf pane: `id` (required), `type` (`"terminal"`, `"agent"`, `"cloud"`), `directory` (supports `~` and `{{param}}`), `commands` (array, run **sequentially, each waiting for the previous**), `shell`, `is_focused`.
Split node: `id`, `split` (`"horizontal"` = left-to-right, `"vertical"` = top-to-bottom), `children` (pane ids, minimum 2).
Params: `[params.<name>]` with `type` of `"text"`, `"branch"` or `"repo"`, plus `description` and `default`. Reserved `{{autogenerated_branch_name}}`.

The shipped worktree example is exactly the fleet primitive you want:
```toml
name = "New Worktree"
title = "{{branch_name}}"
[[panes]]
id = "main"
type = "terminal"
directory = "{{repo}}"
commands = [
  "git worktree add -b {{branch_name}} ../{{branch_name}} {{base_branch}}",
  "cd ../{{branch_name}}",
]
[params.repo]
type = "repo"
[params.base_branch]
type = "branch"
[params.branch_name]
type = "text"
default = "my-feature"
```
Caveat flagged by the researcher: the schema table lists `type = "agent"` and `type = "cloud"` but ships no example of either, and whether an agent pane accepts an initial prompt is **unverified**.

Deep link: `warp://tab_config/<name>` and `warp://tab_config/<name>?new_window=true`, name matching case-insensitive with `.toml` optional. There is **no** `warp://` verb for splitting a pane, sending text or enumerating panes; Warp has no `wezterm cli` equivalent.

C4. Warp's roster and inbox UX, which is the part actually worth stealing
--------------------------------------------------------------------------

**Vertical tabs as the agent roster** (Settings, Appearance, Tabs, "Use vertical tab layout"). Each row carries git branch, working directory, worktree path, PR number and status (needs `gh`), diff stats, and an agent-status badge. Badge vocabulary from https://docs.warp.dev/terminal/windows/vertical-tabs/: magenta clock in progress, green check done, red triangle error, grey stop cancelled, **yellow stop blocked/awaiting approval**, plus an accent dot for unread activity. Third-party CLI agents get their brand icon inside the badge. Density Compact or Expanded; "Pane title as" is Command/Conversation, Working Directory or Branch.

**Agent Management Panel** (https://docs.warp.dev/agents/using-agents/managing-agents), shipped 2026: one list of interactive agents and cloud runs, with run status, **origin** (local conversation, CLI, API, integration, schedule), parent/child relationship, and credits. Status set Working / **Blocked (awaiting user input)** / Canceled / Failed / Success. Filters by source, date, creator, status.

**Notifications** (https://docs.warp.dev/agents/capabilities/agent-notifications/): three categories, **Complete**, **Request** (command approval, permission request, idle waiting) and **Error**, over four surfaces: in-window toasts when an agent in *another tab* needs attention (auto-dismiss, pause on hover, click to jump, max two at once); a **notification mailbox** behind a bell icon with All / Unread / Errors filters and arrow-key navigation; tab status icons with an unread badge cleared on navigating to the tab; and desktop notifications when backgrounded. Settings keys in `settings.toml`: `[agents.warp_agent.other] show_agent_notifications`, `[notifications.preferences] is_agent_task_completed_enabled`, `[notifications.preferences] is_needs_attention_enabled`.

**The design rule worth copying most: only *parent* conversations raise toasts and mailbox entries.** Child agent status goes to the orchestration pill bar only, deliberately, to avoid mailbox spam. Apply this to subagents in your fleet.

Orchestration itself (https://docs.warp.dev/platform/orchestration/) is driven by `/orchestrate` and `/plan`, with documented topologies supervisor/worker, fan-out/fan-in, critic/verifier, review swarm, DAG and swarm. The multi-agent guide's practical advice is prosaic and portable: give each agent a written ownership contract ("You own `src/auth/` and `tests/auth/`. Do not edit `src/billing/`"), one tab per agent, worktree per agent, no auto-merge.

**Synchronised inputs** (https://docs.warp.dev/terminal/entry/synchronized-inputs/): three modes, all panes in all tabs, all panes in current tab (`⌘+Option+I`), stop. Crucially it syncs the **whole command from the input editor, not individual keystrokes**. That is the right semantics for agent panes, since keystroke broadcast into a TUI agent is useless.

**Code review** (https://docs.warp.dev/code/code-review/): live-updating diff as agents edit, per-hunk revert, and **inline comments that the agent receives and acts on**, working with third-party CLI agents including Claude Code. Portable without terminal support: write comments as `path:line: comment` into a file and feed the owning session with `wezterm cli send-text --pane-id N --no-paste`.

**Agent profiles and permissions** (https://docs.warp.dev/agent-platform/capabilities/agent-profiles-permissions/): autonomy per capability as Agent Decides / Always Ask / Always Allow; command allow and deny lists are **regexes** (allow examples `ls(\s.*)?`, `grep(\s.*)?`, `find .*`; deny defaults `rm(\s.*)?`, `curl(\s.*)?`, `wget(\s.*)?`); **denylist beats both allowlist and Agent Decides**; and `Run Until Completion` (`⌘+Shift+I`) grants *temporary* full autonomy for one task, which by default bypasses the denylist. The transferable design lesson is denylist-wins plus a **time-boxed** escalation keystroke rather than a persistent skip-permissions habit.

Rules (https://docs.warp.dev/agent-platform/capabilities/rules/): `AGENTS.md` with `WARP.md` supported for backwards compatibility and **taking precedence when both exist in the same directory**; filename must be all caps; precedence is current subdirectory > repo root > global.

C5. The `oz` CLI is the real API, and it exposes an inter-agent mailbox
------------------------------------------------------------------------

My earlier note that `oz` was undocumented was wrong; it is at https://docs.warp.dev/reference/cli/. Binary `oz`, `brew install --cask oz`. Auth `oz login|logout|whoami`, or `WARP_API_KEY`.

- Agents: `oz agent run` (local, cwd), `oz agent run-cloud`, `oz agent list|get|create|update|delete`, `oz agent skills`
- Runs: `oz run list|get`, `oz run conversation get <ID>`, and critically **`oz run message list|read|send|watch|mark-delivered`**
- Shared flags `--prompt`, `--mcp <SPEC>`, `--model`, `--skill`, `--file <PATH>`; local-only `--cwd`, `--profile`, `--share`; cloud-only `--environment` (required), `--name`, `--title`, **`--parent-run-id <ID>`** (attach as an orchestration child), `--agent <UID>`, **`--harness [oz|claude|codex]`**, `--host <WORKER_ID>`, `--attach`, `--computer-use`, `--open`
- SDKs: `warpdotdev/oz-sdk-python`, `warpdotdev/oz-sdk-typescript`

`oz run message send / watch / mark-delivered` is an **inter-agent mailbox exposed as CLI verbs**, and it is the contract behind the file-backed `oz-harness-support` bridge in C2. If you want parent/child coordination beyond what Claude Code's own `SendMessage` gives you, that verb set (`send`, `watch`, `mark-delivered`) is the right shape for `cc-note`.

Separately, the standalone `warp` Agent CLI (renamed from `warp-tui` in 2026.07.23) is described as **"a native terminal multiplexer"** with its own PTY, running inside Ghostty, iTerm2, VS Code or plain Terminal. Flags `--api-key`, `--auto-approve`, `--resume <CONVERSATION_TOKEN>`; env `WARP_API_KEY`, `WARP_TUI_DISABLE_AUTOUPDATE`. No headless or JSON mode; headless work goes through `oz`.

C6. Ghostty: much weaker programmatically than I reported
----------------------------------------------------------

The researcher read the Ghostty source directly, and it is worse than the release notes suggest.

**IPC is three actions, and none of them work on macOS.** The CLI action enum in `src/cli/ghostty.zig` at `v1.3.1` contains exactly one IPC action, `new-window`. On unreleased `main` that grows to three: `new_window`, `new_tab`, `toggle_quick_terminal`. And in `src/apprt/embedded.zig` (the macOS apprt) on `main`, `performIpc` returns `false` for **every** action; IPC is implemented only in `src/apprt/gtk/ipc/` over `org.gtk.Actions` D-Bus. There is no IPC to create a split, focus a pane, send text or list panes.

The scripting-API tracking issue https://github.com/ghostty-org/ghostty/discussions/2353 was opened on 1 October 2023, has 119 comments, explicitly cites `wezterm cli` as the model, and is **still unanswered as of 10 July 2026**. Correspondingly, https://github.com/anthropics/claude-code/issues/24189 requests Ghostty as a `teammateMode` backend and is blocked on exactly this.

**AppleScript is the only real surface, macOS only, new in 1.3.0** (https://ghostty.org/docs/features/applescript). Object model Application, Windows, Tabs, Terminals. Commands: `new surface configuration`, `new window`, `new tab`, `split` (right/left/down/up), `focus`, `activate window`, `select tab`, `close`, `input text`, `send key` (with modifiers), `send mouse button|position|scroll`, and `perform action` taking an action string such as `"set_tab_title:..."`. Enabled by default, gated by macOS TCC, disabled with `macos-applescript = false`. `new surface configuration` supports font size, initial cwd, command, initial input, wait-after-command, and env vars as `KEY=VALUE`.

**`wezterm cli` is a superset of this** except for two things: synthetic `send key` events with modifiers (as opposed to pasted text), and `perform action <string>`. For the latter, the standard WezTerm trick is to drive it off a user var and a `wezterm.on('user-var-changed')` handler rather than the CLI.

**Critical negative finding, verified in source: Ghostty does not implement OSC 1337 SetUserVar.** `src/terminal/osc/parsers/iterm2.zig` on `main` implements only `Copy` and `CurrentDir`; everything else, including `SetUserVar`, `RequestAttention`, `SetMark`, `SetBadgeFormat` and `StealFocus`, hits a catch-all that logs `unimplemented OSC 1337` and returns `.invalid`. So Ghostty has **no per-pane user-variable channel and no OSC-driven attention request beyond the bell**. That is precisely why the Warp plugin resorts to OSC 777 with a fake title as a routing key, and it is the single biggest reason WezTerm remains the better host for an agent fleet despite its release drought.

What Ghostty *does* parse (`src/terminal/osc.zig` at `v1.3.1`): OSC 7, 8, 9 and 777 desktop notifications, 21 (Kitty colour), 22 (mouse shape), 52 (clipboard), 66 (Kitty text sizing), 133, 3008, the full ConEmu OSC 9;1 through 9;11 family including **9;3 change tab title** and **9;4 progress**, and OSC 4/5/10-19. New on `main` since 1.3.1: **OSC 99 (Kitty desktop notifications)** and OSC 72 (Kitty drag-and-drop).

Bell handling is the whole "unread output" story, and it is bell-triggered only. `bell-features` packed struct: `system` false, `audio` false, `attention` true, `title` true, `border` false. The `title` feature **prepends a 🔔 to the alerted surface's title until refocused or given keyboard input**. There is no per-tab activity or silence monitoring, no unread counter, no mailbox.

`notify-on-command-finish` (`never` default / `unfocused` / `always`), `notify-on-command-finish-action` (`bell` on, `notify` off, negatable as `no-bell,notify`), `notify-on-command-finish-after` (default `5s`). **Note the limitation I did not flag earlier: it fires on OSC 133 command boundaries, so it does not fire for a long-lived agent TUI that never returns to a prompt.** Its usefulness for agent work is therefore low.

`title-report` (`CSI 21 t`) defaults to **false**, and the doc comment calls it "a common security issue" that "can expose sensitive information at best and enable arbitrary code execution at worst". Do not build anything on reading titles back.

**libghostty**: at `v1.3.1` the C headers were `ghostty.h`, `ghostty/vt.h` and ten files under `ghostty/vt/`. On `main` today that has grown to roughly thirty, adding `terminal.h`, `screen.h`, `snapshot.h`, `search.h`, `render.h`, `selection.h`, `kitty_graphics.h`, `mouse/encoder.h`, `formatter.h` and more. API groups per `vt.h`: Terminal, Render State, Formatter (plain text / VT / HTML), Snapshot, Search including scrollback, OSC parser, SGR parser, Paste, Unicode, Allocator, byte-stream I/O, WebAssembly. Stability, quoted from the header: "WARNING: This is an incomplete, work-in-progress API. It is not yet stable and is definitely going to change." So it is genuinely usable as an embeddable **VT parsing and state library**, which is what cmux uses it for, but it is not a GUI toolkit and the C API will break.

**Ghostty has no AI or agent features at all.** Confirmed against the 1.2.0, 1.3.0 and 1.3.1 release notes, the full config option list, the full keybind action list on both `v1.3.1` and `main`, the CLI action enum on both, and the docs nav (four feature pages: applescript, shell-integration, ssh, theme). The only agent-adjacent items are incidental: 1.3.0 "fixed a major memory leak affecting **Claude Code users** since Ghostty 1.0" (named explicitly), and threaded scrollback search.

Ghostty release state confirmed via `gh api repos/ghostty-org/ghostty/tags`: latest tag `v1.3.1`, only rolling `tip` prereleases since. **1.4.0 has not shipped**, despite the stated March/September cadence. `main` is active with commits on 2026-09-03.

C7. Two Ghostty ideas that are still worth porting
----------------------------------------------------

- **`shell-integration-features = path`**: Ghostty forces its own binary directory onto `PATH` inside its panes so the terminal's CLI stays callable after init scripts clobber `PATH`. Do the same for `wezterm` in your agent panes; otherwise an orchestration script fails mysteriously in exactly the pane where a `.zprofile` reset `PATH`.
- **`ssh-terminfo`**: installs the terminal's terminfo on remote hosts using local `infocmp` and remote `tic`, cached and managed by `ghostty +ssh-cache`. If you drive agents over SSH, `infocmp wezterm | ssh host tic -x -` once per host, cached, saves a recurring class of breakage.

Also worth wiring: Ghostty's **`command-palette-entry`** (`title:`, `description:`, `action:`) maps to WezTerm's `augment-command-palette` event returning custom entries. With a large `wezterm.lua` and a set of orchestration scripts, making them discoverable by name in the palette beats remembering chords. Ghostty's 1.3.0 **key tables** map to WezTerm's existing `key_tables` plus `ActivateKeyTable{name, one_shot, until_unknown, prevent_fallback}`, which is strictly more expressive (WezTerm has timeouts); `catch_all` maps to `prevent_fallback = true`.

C8. One useful data point on WezTerm's actual state
-----------------------------------------------------

The researcher verified `wezterm cli` locally against **`wezterm 20260803-054620-6f8b1d41`**, an August 2026 nightly. So the picture is: no stable tag since February 2024, but nightlies are current and the CLI surface is intact and confirmed to include `list`, `list-clients`, `spawn`, `split-pane` (with `--left/--right/--top/--bottom`, `--cells`, `--percent`, `--cwd`, `--top-level`, `--move-pane-id` and trailing `PROG...`), `send-text`, `get-text`, `activate-pane`, `activate-pane-direction`, `get-pane-direction`, `adjust-pane-size`, `zoom-pane`, `kill-pane`, `move-pane-to-new-tab`, `activate-tab`, `set-tab-title`, `set-window-title`, `rename-workspace`. `split-pane` returning the new pane id makes your layout scripts strictly more capable than Warp's Tab Configs, which have no such handle.

Revised top of the build list
------------------------------

Replacing items 1 and 8 of my earlier priority list:

1. **Port `warpdotdev/claude-code-warp`'s six hooks, emitting `OSC 1337 SetUserVar` instead of OSC 777**, with their `terminalSequence`-versus-`/dev/tty` version gate and the 0.3 s transcript-flush sleep on `Stop`. Read the state in `wezterm.lua` via `user-var-changed` and `pane:get_user_vars()`. Keep OSC 9 or 777 alongside for the desktop toast.
2. Five-state badge vocabulary from Warp's vertical tabs (working, blocked, done, error, cancelled) plus an unread dot, rendered in `format-tab-title`.
3. "Jump to next blocked pane" on one keystroke, which is what Warp's toast-click and management panel both reduce to.
4. **Only parents notify.** Suppress toasts for subagents and teammates.
5. Declarative layouts in Warp's **Tab Config TOML** shape (not the deprecated launch-configuration YAML I gave earlier), with `{{param}}` prompting and a `repo`/`branch` param type, driving `wezterm cli spawn` and `split-pane` and capturing the returned pane ids.
6. Whole-command synchronised input scoped to a tab, not keystroke broadcast.
7. Denylist-beats-allowlist permissions plus a **time-boxed** escalation keystroke rather than a standing `--dangerously-skip-permissions`.
8. Force `wezterm` onto `PATH` inside agent panes (Ghostty's `shell-integration-features = path` trick).

Still outstanding: the kitty and tmux-ecosystem agent has not reported yet, so my kitty coverage (OSC 99, `launch --watcher`, `kitty @` basics) and the tmux project surveys above remain as I originally verified them, without its deeper pass. I will pass on its findings when they arrive.

============================== ac674897d9f3fb3b6 ==============================

I have comprehensive primary-source coverage. Compiling the report now.

Research complete. Three parallel research streams (hosted/GUI orchestrators, worktree managers, Claude Code ecosystem tools) are still running; everything below is from my own fetches, and I covered the highest-value items from their areas as insurance.

---

# Terminal-multiplexer-native agent orchestration, 2026

## 0. The headline: the ground moved under this whole category in 2026

Two things dominate. First, **Claude Code absorbed most of what these tools existed to do** (agent view, worktrees, cross-session messaging, agent teams). Second, **the standalone GUI orchestrator category is collapsing**: Crystal (stravu/crystal, 3.1k stars) was **deprecated in February 2026** and replaced by Nimbalyst (https://github.com/stravu/crystal, README now reads "Crystal Is Now Nimbalyst … Deprecated: February 2026", https://nimbalyst.com/); **Vibe Kanban (BloopAI/vibe-kanban, 28k stars) is sunsetting** (https://github.com/BloopAI/vibe-kanban, "Vibe Kanban is sunsetting", https://www.vibekanban.com/blog/shutdown, last push 2026-04-24). Meanwhile the *terminal* layer is thriving: herdr (35.2k stars, pushed today), cmux (26.8k), workmux (2.4k), dmux (1.8k), agent-manager (392, pushed today).

The single most useful discovery for you: **your WezTerm already exposes complete fleet state today, and you are not reading it.** Verified live on your machine below.

---

## 1. What is native in Claude Code now (verified on your machine, v2.1.260)

This is the biggest steal, because it replaces large parts of cc-board/cc-fleet/cc-note with zero maintenance.

### 1.1 `claude agents --json` is a ready-made fleet feed

Docs: https://code.claude.com/docs/en/agent-view (see "List sessions as JSON"). I ran it on your machine:

```
36 sessions
fields: cwd, kind, name, pid, sessionId, startedAt, status, waitingFor
status counts: idle=30, busy=4, waiting=2
kind counts: interactive=36
waitingFor values seen: "dialog open", "input needed"
```

It enumerates **interactive sessions too**, not just background ones. Documented `state` values for background sessions are `working | blocked | done | failed | stopped`; `waitingFor` is one of `permission prompt`, `input needed`, `sandbox request`, `worker request`, `dialog open`. Flags: `--all` (include completed background sessions), `--cwd <path>` (scope), `--json`.

That is cc-board's data model, already computed, already correct, already tracking sessions started outside your scripts.

### 1.2 Shell control surface

From https://code.claude.com/docs/en/agent-view#manage-sessions-from-the-shell:

| Command | Purpose |
|---|---|
| `claude agents` | Open agent view TUI |
| `claude agents --json` / `--all` / `--cwd <path>` | Machine-readable list |
| `claude attach <id>` | Attach a background session to this terminal |
| `claude logs <id>` | Print recent output |
| `claude stop <id>` (alias `kill`) | Stop, conversation kept |
| `claude respawn <id>` / `--all` | Restart onto an updated binary, resumes saved conversation |
| `claude rm <id>` | Delete session + its worktree when safe |
| `claude daemon status` | Supervisor pid, version, socket dir, worker count |
| `claude daemon stop --any [--keep-workers]` | Stop/restart supervisor |

Dispatch: `claude --bg "prompt"` (long form `--background`; prompt is positional, rejected with `-p`/`--print`), `--name <name>`, `--agent <subagent-name>` to run a named subagent as the session's main agent, `claude --bg --exec 'pytest -x'` to run a plain PTY-backed shell job that appears as a row.

On-disk state (https://code.claude.com/docs/en/agent-view#where-state-is-stored):

- `~/.claude/daemon.log` supervisor log
- `~/.claude/daemon/roster.json` running background sessions (I confirmed: `{"proto":1,"supervisorPid":…,"updatedAt":…,"workers":{}}`)
- `~/.claude/jobs/<id>/state.json` per-session state
- `~/.claude/jobs/<id>/tmp/` scratch, exported to the session as `$CLAUDE_JOB_DIR`
- Transcripts: `~/.claude/projects/<cwd-slug>/<sessionId>.jsonl` (confirmed on your machine; last line of a finished session is a summary record with `totalCostUSD`, `totalDuration`, `totalLinesAdded`, `totalLinesRemoved`, `modelUsage`)

Turn it all off with `disableAgentView: true` or `CLAUDE_CODE_DISABLE_AGENT_VIEW`.

### 1.3 Cross-session messaging: there is a socket per session and bash can write to it

https://code.claude.com/docs/en/cross-session-messaging. Verified on your machine:

```
CLAUDE_CODE_MESSAGING_SOCKET=/tmp/cc-socks/62789.sock
CLAUDE_CODE_MESSAGING_TOKEN=<set>
/tmp/cc-socks/ contains 36 sockets, named <pid>.sock, mode srw------- 
```

The docs' section "The session's inbox socket" says a script can post into a session's socket, optionally sending `{"type":"auth","token":"<token>"}` as the first line (optional on macOS/Linux, required on native Windows). Claude Code closes a connection that has not sent a complete line within 30 seconds, so build the message first, then connect. Own-child messages (a hook or Bash command posting back to its own session) are delivered without `crossSessionInbound` approval, verified by process evidence on Linux, or by the token on macOS after the writer exited.

Because `claude agents --json` gives you `pid` and `/tmp/cc-socks/<pid>.sock` is the address, **you can map name to socket entirely from bash**. That is a direct upgrade path for cc-note and cc-handover: instead of `wezterm cli send-text` into a pane (which races with whatever the user is typing), you post to the session's inbox and it is delivered between tool calls without interrupting a running tool, or starts a new turn if idle.

Other pieces: Claude also has `ListAgents` and `SendMessage` tools, `/list-agents` shows what this session can reach, `@name` typeahead addressing (v2.1.232+), and `SendMessage`'s `notify_when_idle` input for a one-shot "tell me when that session goes idle" subscription that expires after 12 hours (v2.1.236+). Requires v2.1.224+ on macOS/Linux. `-p` sessions bind a socket too (bare mode does not), so a headless worker is addressable; start it with `crossSessionInbound: accept` in its `--settings` to take messages unattended.

### 1.4 Native worktrees

https://code.claude.com/docs/en/worktrees:

- `claude --worktree <name>` / `-w` creates `.claude/worktrees/<name>/` at repo root on branch `worktree-<name>`. Omit the name and it generates one like `bright-running-fox`.
- `claude --worktree "#1234"` branches from a PR/MR: fetches `pull/<n>/head` (github.com) or `merge-requests/<n>/head` (gitlab.com) into `.claude/worktrees/pr-<number>`.
- `worktree.baseRef`: `"fresh"` (default, branch from remote default branch, refetches `origin/HEAD` if older than 24h, capped at 5s) or `"head"` (branch from local HEAD).
- `.worktreeinclude` at project root, gitignore syntax: copies matching **gitignored** files (`.env`, `config/secrets.json`) into each new worktree. Applies to `--worktree`, subagent worktrees, and desktop parallel sessions.
- Reusing a name reopens the existing worktree; with `"fresh"` base it resets to the default branch only if clean, still on its created branch, and with no commits of its own or a merged-and-deleted remote branch.
- Cleanup: interactive exit prompts if there is work; `-p` runs never clean up. Claude Code holds a `git worktree lock` while an agent runs and releases it when finished; a periodic sweep removes subagent and background-session worktrees older than `cleanupPeriodDays`, and it writes a marker into git metadata so it never deletes a worktree you made yourself.
- Worktrees share the repo's `.git`, project-scope plugins, and permission approvals (saved to the main checkout's `.claude/settings.local.json`, v2.1.211+).
- Subagents: `isolation: worktree` in frontmatter, or `isolation: "worktree"` at spawn.
- Background sessions auto-move into `.claude/worktrees/` before their first edit; disable per repo with `{"worktree":{"bgIsolation":"none"}}`.
- Replace git entirely with a `WorktreeCreate` hook (below).

`claude --worktree --tmux` exists locally: "Create a tmux session for the worktree (requires --worktree). Uses iTerm2 native panes when available; use `--tmux=classic` for traditional tmux." **No WezTerm path** (see §3.3 for the shim that fixes this).

### 1.5 Agent teams

https://code.claude.com/docs/en/agent-teams. Enabled by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Architecture:

- Mailbox: `~/.claude/teams/{team-name}/inboxes/{agent-name}.json`, one JSON file per agent, validated on read, malformed entries removed
- Team config: `~/.claude/teams/{team-name}/config.json` with a `members` array (lead carries agent type `team-lead`), holds session IDs and **tmux pane IDs**; removed when the session ends
- Task list: `~/.claude/tasks/{team-name}/`, persists across resume; claiming uses file locking
- Team name is `session-` + first eight chars of the session ID

Display modes via `teammateMode` in `~/.claude/settings.json` or `--teammate-mode` (experimental, hidden from `--help`): `"in-process"` (default since v2.1.179), `"auto"`, `"tmux"`, `"iterm2"` (v2.1.186+, requires the `it2` CLI, https://github.com/mkusaka/it2). **Split-pane mode requires tmux or iTerm2. Explicitly unsupported: VS Code integrated terminal, Windows Terminal, Ghostty. WezTerm is not on the supported list.**

Quality gates via hooks: `TeammateIdle` (exit code 2 sends stderr as feedback and keeps the teammate working), `TaskCreated`, `TaskCompleted`.

Limitations worth knowing: no session resumption of in-process teammates, one team per session, no nested teams, teammates are not worktree-isolated (you must partition files yourself), lead is fixed for the session's lifetime.

### 1.6 The comparison Anthropic itself draws

https://code.claude.com/docs/en/agents: subagents (delegated workers in one session) vs agent view (`claude agents`, hand off and check back) vs agent teams (lead + shared task list + messaging) vs dynamic workflows (a JavaScript script the runtime executes, "dozens to hundreds of agents per run", `/workflows` to list runs, https://code.claude.com/docs/en/workflows). Also `/batch`, a bundled skill that splits one change into 5-30 worktree-isolated subagents that each open a PR.

---

## 2. State detection: the four mechanisms, and the actual rulesets

This is the part worth your attention. There are exactly four approaches in the wild, and the best tools combine two.

### 2.1 Mechanism A: hooks (authoritative, cheap, blind to some states)

Relevant events from https://code.claude.com/docs/en/hooks:

**`Notification`** matchers include `permission_prompt` (fires ~6s after the prompt appears, deferred by each keystroke), `idle_prompt` (~60s after Claude finishes and you have not typed), **`agent_needs_input`** and **`agent_completed`** (v2.1.198+, but these fire only while agent view is open in a terminal), plus `quota_auto_resume_fired` / `_stale` / `_disabled` (v2.1.234+, usage-limit resume). Payload:

```json
{"session_id":"abc123","transcript_path":"…jsonl","cwd":"/Users/…",
 "hook_event_name":"Notification","message":"Claude needs your permission",
 "title":"Permission needed","notification_type":"permission_prompt"}
```

Note: "You receive these hook events even with desktop notifications turned off". For an *immediate* signal on a permission ask, use `PermissionRequest` rather than waiting six seconds for `Notification`.

**`Stop`** now carries `last_assistant_message`, plus **`background_tasks[]`** and **`session_crons[]`**. Those two arrays are the key to telling "session is done" from "session is paused waiting for background work". Each `background_tasks` entry has `id`, `type` (`shell`, `subagent`, `monitor`, `workflow`, `teammate`, `cloud session`, `MCP task`), `status`, `description`, and type-specific `command` / `agent_type` / `server` / `tool` / `name`. Docs explicitly say to use `last_assistant_message` rather than reading `transcript_path`, because the transcript is not guaranteed to contain the final message at Stop time.

**`SubagentStart`** / **`SubagentStop`**: `agent_id`, `agent_type`, `agent_transcript_path` (nested `subagents/` folder), `last_assistant_message`. SubagentStart can inject `additionalContext`.

**`WorktreeCreate`** / **`WorktreeRemove`**: WorktreeCreate *replaces* git worktree creation entirely (so `.worktreeinclude` is not processed and you must copy `.env` yourself). Input is `{…, "hook_event_name":"WorktreeCreate", "name":"feature-auth"}`; the hook must print the worktree path as the last non-empty line of stdout (ANSI stripped; absolute paths with `.`/`..` or paths through a repo-internal symlink are refused since v2.1.216). WorktreeRemove receives `worktree_path`. Documented example:

```json
{"hooks":{"WorktreeRemove":[{"hooks":[{"type":"command",
  "command":"bash -c 'jq -r .worktree_path | xargs rm -rf'"}]}]}}
```

This is how you would put worktrees somewhere other than `.claude/worktrees/` while keeping every native feature.

### 2.2 Mechanism B: screen scraping with a versioned rule pack

**herdr** (https://github.com/herdrdev/herdr, Apache-2.0, Rust, 35.2k stars, pushed 2026-09-04) has the best-engineered version of this: per-agent TOML manifests at `src/detect/manifests/*.toml` covering amp, antigravity, claude, cline, codex, cursor, devin, droid, gemini, github-copilot, grok, hermes, kilo, kimi, kiro, maki, opencode, pi, qodercli, qwen. The Claude manifest (`src/detect/manifests/claude.toml`, `version = "2026.08.31.1"`) is a priority-ordered rule list with named regions. Verbatim highlights:

```toml
[[rules]]
id = "osc_title_working"
state = "working"
priority = 1100
region = "osc_title"
# Braille covers <= 2.1.227; half-circles are the 2.1.228 busy spinner.
regex = ['^[\x{2800}-\x{28FF}\x{25D0}-\x{25D3}] ']

[[rules]]
id = "live_turn_working"
state = "working"
priority = 970
region = "bottom_non_empty_lines(12)"
any = [
  { line_regex = ['^\s*[⏸⏵].*esc to interrupt(?:\s|·|$)'] },
  { line_regex = ['^\s*[\x{002A}\x{00B7}\x{2722}\x{2736}\x{273B}\x{273D}]\s+\S.*…(?:\s+\(\d+[smh](?:\s|·)|\s*$)'] },
]

[[rules]]
id = "live_blocked_form"
state = "blocked"
priority = 980
region = "after_last_horizontal_rule"
contains = ["esc to cancel"]
any = [
  { contains = ["enter to confirm"] },
  { contains = ["enter to select"], any = [ … navigate hints … ] },
]

[[rules]]
id = "live_prompt_box"
state = "idle"
priority = 950
region = "prompt_box_body"
line_regex = ['^\s*❯']
not = [ { contains = ["enter to select"] }, { contains = ["esc to cancel"] }, … ]

[[rules]]
id = "osc_title_idle"
state = "idle"
priority = 250
region = "osc_title"
regex = ['^\x{2733} ']

[[rules]]
id = "osc_progress_idle"
state = "idle"
priority = 250
region = "osc_progress"
regex = ['^4;0']
```

Plus `bash_permission_prompt` (priority 850, `contains = ["do you want to proceed?"]` plus `bash(` / `tab to amend` / `ctrl+e to explain` and a `1. yes` / `2. no` line), `mcp_elicitation_prompt` (gated on `MCP server "…" requests your input` plus Accept/Decline lines, added because elicitation dialogs have no Enter hint), `dynamic_workflow_prompt`, `background_agents_working` (`Waiting for N background agents to finish`), `background_mcp_task_working` (`· N MCP tasks still running`), and `transcript_viewer` / `model_picker_menu` with `skip_state_update = true` so overlays do not corrupt the state.

Herdr's design rule, from https://herdr.dev/docs/agents/: "Blocked detection is deliberately strict for screen-manifest agents. Herdr only marks `blocked` when the live bottom-buffer snapshot matches known visible approval, question, or permission UI."

### 2.3 Mechanism C: screen scraping done carefully (the debouncing problem)

**ccmanager** (https://github.com/kbwo/ccmanager, TypeScript, 1.2k stars, pushed 2026-09-02) has no tmux dependency and drives its own PTYs. Its `src/services/stateDetector/claude.ts` solves the three failure modes you will hit:

1. **False idle during redraw.** `IDLE_DEBOUNCE_MS = 1500`: idle is only returned when the last 30 lines have been byte-identical for 1.5s. Comment: "Claude Code sometimes appears idle in terminal output while still actively processing (busy)."
2. **Your own typing matching busy patterns.** Busy detection runs only on `getRecentContentAbovePromptBox()`, which walks up from the bottom, finds the two `─` border lines that delimit the prompt box, then keeps only the *most recent contiguous non-blank block* above it. Comment: "xterm's buffer can retain transient fragments from those redraws outside the latest visible content block."
3. **Permission menus with no question phrasing.** Beyond `/(?:do you want|would you like).+\n+[\s\S]*?(?:yes|❯)/` and `esc to cancel`, it matches `/\d+\.\s*deny\s*\(esc\)/` because "the numbered `Deny (esc)` option is the stable marker across variants".

Busy markers: `esc to interrupt`, `ctrl+c to interrupt`, a spinner-activity line `^[✱✲✳✴✵✶✷✸✹✺✻✼✽✾✿❀❁❂❃❇❈❉❊❋✢✣✤✥✦✧✨⊛⊕⊙◉◎◍⁂⁕※⍟☼★☆·•⏺▸▹∙⋅○●] \S+ing.*…`, and a token-stats line `/\([^)]*\d[^)]*tokens\s*\)/i`. It also counts background tasks with `/(\d+)\s+(?:background\s+task|local\s+agent)/` (falling back to `(running)` meaning at least one) and counts agent-team members by finding the `shift+↑ to expand` line and matching `@[\w-]+`. Overlay guard: `ctrl+r to toggle` and `⌕ Search…` return the current state rather than reclassifying.

### 2.4 Mechanism D: silence timers

**FrankenTerm** (https://github.com/Dicklesworthstone/frankenterm, Rust, 110 stars but 1.26M LoC and pushed 2026-09-04, by the agent-farm author) ships plain thresholds you can copy wholesale:

```toml
[agent_detection]
enabled = true
active_output_threshold_ms = 5000     # Output within 5s → Active (green)
thinking_silence_ms = 5000            # Input sent, no output for 5s → Thinking (yellow)
stuck_silence_ms = 30000              # No output for 30s after input → Stuck (red)
idle_silence_ms = 60000               # No activity for 60s → Idle (gray)
```

It also gates sending into a pane on OSC 133 prompt markers: `[safety] require_prompt_active = true` needs `ft setup shell` (bash/zsh/fish) installed, and until then "an untrusted caller's first send to a pane returns `RequireApproval` with rule `policy.prompt_unknown`". Plus `block_alt_screen = true`, `rate_limit_per_pane = 30`, `rate_limit_global = 100`.

**claude_code_agent_farm** (https://github.com/Dicklesworthstone/claude_code_agent_farm, 916 stars, pushed 2026-09-01) has an adaptive version. From `claude_code_agent_farm.py`:

- `calculate_adaptive_timeout()`: idle timeout is `3 × median cycle time`, clamped to 30-600s, and only updated when it differs by more than 20%. Cycle time is measured from the `working → ready` transition.
- Heartbeat files at `<project>/.heartbeats/agent<NN>.heartbeat` containing an ISO timestamp, written on every `tmux_send` and on every poll where the agent is working or ready. `needs_restart()` returns `"error"` when `heartbeat_age > 120`, `"context"` when `last_context <= context_threshold` (send `/clear` instead of a full restart), `"error"` on `status == "error"` or `errors >= max_errors`, `"idle"` on prolonged idleness.
- `detect_context_percentage()` tries `Context left until\s*auto-compact:\s*(\d+)%`, `Context remaining:\s*(\d+)%`, `(\d+)%\s*context\s*remaining`, `Context:\s*(\d+)%`.
- Live status is written to the tmux pane title: `run(f"tmux select-pane -t {pane_target} -T {shlex.quote(title)}")` with `[{id:02d}] {emoji} Context: ⚠️ 15%`, alongside `set-option -g pane-border-status top` and `pane-border-format ' #{pane_title} '`. Monitor state also goes to `.claude_agent_farm_state.json` so `claude-code-agent-farm monitor-only` can render a dashboard from a separate process.
- A shell-readiness probe worth stealing: after 3s of failed passive prompt detection it sends `echo AGENT_FARM_READY_<random 6 digits>` and waits for the marker to come back, proving the shell accepts commands regardless of how exotic your prompt is.
- Ctrl+R broadcasts `/clear` to every agent: `tmux bind-key -T root -n C-r \; display-message … \; send-keys -t <pane> '/clear' Enter \; …`

### 2.5 Mechanism E: the hybrid, which is what you should build

**agent-manager** (https://github.com/YoanWai/agent-manager, Go, Apache-2.0, 392 stars, pushed 2026-09-04) does exactly this. From https://github.com/YoanWai/agent-manager/blob/main/docs/usage.md#status:

> "For Claude Code, status comes first-hand from hook events instead of pane guessing: sessions launch with a generated `--settings` file whose hooks write the lifecycle state (`working`, `waiting`, `finished`, `idle`) to a per-session status file that the poller reads first. A `StopFailure` of `rate_limit` writes `errored`. Pane rules still refine it — hooks cannot see a plain-text question, an Esc interrupt, or an error line, so a matching pane verdict upgrades the hook status — and they take over fully as fallback when the hook file is missing or stale. Enabled per tool with `status_source = "claude-hooks"`."

Its statuses are `working ◐`, `waiting ◆`, `finished ●`, `errored ✕`, `idle ○`, `dead ✕`, `starting ◌`, and `finished` is an *alert* state that clears to `idle` only once you enter the session. Its config (`~/.config/agent-manager/config.toml`, `poll_interval = "2s"`) is worth copying wholesale:

```toml
[tools.mytool]
command = "mytool"
default_status = "idle"
rules = [
  { state = "working", pattern = "esc to interrupt" },
  { state = "errored", pattern = "(?im)^\\s*error:" },
]
```

with refinement fields `activity_cutoff` (regex locating the input box; everything above it is turn content), `turn_end`, `busy_line` (work outliving its turn, so a turn-end summary still reads as working while background agents run), `limit_line` (rate-limit banner ⇒ errored), `dialog_footer` (a line only an open dialog draws under the input marker, so a dialog reusing the marker is not read as a typed draft), `chrome_line`, `blocked_line`, `trailing_note`, `input_prefix`, `composer_placeholder`. Detection also "treats streaming output (content changing between polls) as `working`", and "when a `working` pane goes quiet, the turn counts as `finished`, or `waiting` when it ends on a question".

Notifications fire **once per transition**, never per poll. Inside Ghostty or cmux it emits **OSC 777** to the drawing terminal (so it works over SSH); elsewhere it uses the OS desktop path or the terminal bell.

**NTM** (https://github.com/Dicklesworthstone/ntm, Go, 435 stars) uses the same shape: agent plugins at `~/.config/ntm/agents/*.toml` with `[agent.readiness]` regexes that "drive idle/working/error classification for `status`, `--robot-tail`, and `--verify-boot`".

---

## 3. WezTerm specifically (this is your section)

### 3.1 Your fleet state is already sitting in `wezterm cli list --format json`

I ran this on your machine. 63 panes. Fields: `window_id, tab_id, pane_id, workspace, size, title, cwd, cursor_x, cursor_y, cursor_shape, cursor_visibility, left_col, top_row, tab_title, window_title, is_active, is_zoomed, tty_name`. And the titles:

```
33 panes titled '✳ …'   (U+2733)
 2 panes titled '◑ …'   (U+25D1)
 1 pane  titled '◐ …'   (U+25D0)
```

Examples: `✳ Agent work continuation`, `✳ Vapi sign-in issue`, `◐ Claude Code`, `◑ Wezterm setup for agent control`.

Cross-reference herdr's `claude.toml`: `osc_title_idle` is `^\x{2733} ` and `osc_title_working` is `^[\x{2800}-\x{28FF}\x{25D0}-\x{25D3}] `. **Your WezTerm pane titles are already carrying Claude Code's busy/idle state plus an LLM-written topic summary, and `wezterm cli list --format json` hands you all 63 of them in one call with no polling of pane content, no hooks, and no PTY scraping.** A cc-board rewrite is roughly:

```bash
wezterm cli list --format json | jq -r '
  .[] | select(.title | test("^[✳⠀-⣿◐-◓]")) |
  [(if (.title|test("^✳")) then "idle" else "busy" end), .pane_id, .workspace,
   (.cwd|sub("^file://";"")), .title] | @tsv'
```

Caveat to verify: `terminalTitleFromRename` (https://code.claude.com/docs/en/settings-reference#terminaltitlefromrename) says that once you name a session with `/rename` or `--name`, the tab shows the name instead of the generated title. Set it to `false` if you want to keep the generated topic. Also note the *progress bar* signal is a different thing: `terminalProgressBarEnabled` only emits "in ConEmu, Ghostty 1.2.0 or later, and iTerm2 3.6.6 or later" (https://code.claude.com/docs/en/settings-reference#terminalprogressbarenabled), so WezTerm will not get `osc_progress`. The title signal is terminal-agnostic and does work, as proven above.

### 3.2 The rest of the WezTerm control surface

- `wezterm cli list --format json`, `wezterm cli list-clients`
- `wezterm cli spawn [--new-window] [--window-id N] [--workspace NAME] [--cwd DIR] [--domain-name D] -- prog…` — **prints the new pane-id on stdout**
- `wezterm cli split-pane [--pane-id N] [--left|--right|--top|--bottom] [--top-level] [--cells N|--percent N] [--cwd DIR] [--move-pane-id N] -- prog…` — also prints the new pane-id
- `wezterm cli send-text [--pane-id N] [--no-paste] [TEXT]` — sends as a bracketed paste by default; `--no-paste` sends raw (https://wezterm.org/cli/cli/send-text.html)
- `wezterm cli get-text [--pane-id N] [--start-line N] [--end-line N] [--escapes]` — negative line numbers go back into scrollback (https://wezterm.org/cli/cli/get-text.html)
- `wezterm cli activate-pane`, `activate-pane-direction`, `activate-tab`, `kill-pane`, `zoom-pane`, `adjust-pane-size`, `move-pane-to-new-tab`, `set-tab-title`, `set-window-title`, `rename-workspace`
- Targeting env: `$WEZTERM_PANE`, `$WEZTERM_UNIX_SOCKET`; flags `--prefer-mux`, `--class`

And the piece that closes the loop for wezterm.lua: **user vars**. `printf "\033]1337;SetUserVar=%s=%s\007" foo $(echo -n bar | base64)` fires `wezterm.on('user-var-changed', function(window, pane, name, value) … end)`, and `pane:get_user_vars()` reads them all back (https://wezterm.org/config/lua/window-events/user-var-changed.html; needs wezterm 20220903-194523-3bb1ed61+, and `base64 -w 0` on Linux). That means a Claude Code hook can push structured state straight into WezTerm's Lua with no polling.

### 3.3 `wezcld`: makes Claude Code agent teams work in WezTerm

https://github.com/afewyards/wezcld (21 stars, pushed 2026-02-24). This is the exact plaster for the gap in §1.5.

> "Claude Code uses iTerm2 split panes to manage agent teams. wezcld intercepts `it2` CLI commands and translates them to WezTerm CLI calls."

Mechanism: the `wezcld` launcher sets `TERM_PROGRAM=iTerm.app`, prepends its own `bin/` to `PATH`, and launches `claude --teammate-mode tmux`. The `bin/it2` shim translates:

| `it2` command | WezTerm action |
|---|---|
| `session split [-v]` | `wezterm cli split-pane` (3-column grid, leader kept at the bottom) |
| `session run -s <id> <cmd>` | `wezterm cli send-text --pane-id <id>` |
| `session close -s <id>` | `wezterm cli kill-pane --pane-id <id>` |
| `--version` / `app version` | returns `it2 0.2.3` |
| everything else | silent success, exit 0 |

Falls back to plain `claude` outside WezTerm. Shell script, POSIX. Note it is a small, young project, so read the shim before trusting it, but the technique is trivially reproducible in your own `bin/`.

### 3.4 `wezterm-attention`: file-marker attention surface for the tab bar

https://github.com/pro-vi/wezterm-attention (20 stars, pushed 2026-09-03). A WezTerm Lua plugin. This is essentially a productised version of what your wezterm.lua probably wants to do.

Protocol: write JSON to `~/.local/state/wezterm-attention/<WEZTERM_PANE>`, contents `{"type":"thinking"|"stop"|"notify"|"review"}`, optional `frame` (0-3) for spinner position, recommended `publication_id` (a fresh string per publication so an identical `stop` payload becomes visible again after acknowledgement), optional `ttl_ms` (default stale `thinking` cleanup at 30 minutes). Write atomically via `.tmp` + rename. Priority when several panes in a tab differ: **notify > stop > review > thinking**. Sidecars: `.ack` (written on focus, so writer-owned state is never destroyed), `.review` (your own `Alt+B` flag, independent of any marker), `.agents` (subagent roster, `{"agent-4f2a":{"type":"general-purpose","last_ms":…}}`, rendered as `✓+2`). The poller removes markers for panes that vanished between ticks, because WezTerm emits no pane-close event.

Its documented Claude Code wiring:

| Hook | Marker | Required? |
|---|---|---|
| `Stop` | `stop` | **Yes**, core value |
| `PreToolUse` | `thinking` | Recommended |
| `Notification` | `notify` | Optional |
| `PermissionRequest` | `notify` | Optional |
| `SessionEnd` | cleanup | Recommended |

with a pane-id safety contract: every fragment gates on `/^\d+$/` against `WEZTERM_PANE` first, "an unvalidated `../…` value would let a write clobber, or a delete remove, a file outside the marker dir".

Renderer caveat straight from the README: **WezTerm only runs the first registered `format-tab-title` handler**, so `apply_to_config` must run before tabline.wez or you get polling and acknowledgement but no indicators. Use `renderer = "manual"` plus `attention.wrap_title_formatter(...)` to keep your own formatter.

Related, less mechanically interesting: https://github.com/Eric162/wezterm-agent-deck (73 stars) is a pure-Lua plugin with `update_interval = 500`ms status checks and per-state colours/icons; https://github.com/Michal1993r/ai-helper.wezterm (38 stars).

### 3.5 FrankenTerm: the maximalist WezTerm agent hypervisor

https://github.com/Dicklesworthstone/frankenterm. "A swarm-native terminal platform designed to observe, control, and audit large fleets of concurrent AI coding agents", built on a **WezTerm fork's mux protocol** (with the external `wezterm` CLI as a compatibility fallback). Whether or not you install it, its API design is the right target shape for cc-fleet:

```bash
ft robot state                      # AI-readable snapshot of every pane, no daemon needed
ft robot get-text 0 --tail 50 [--escapes] | --panes 0,1,2 | --all
ft robot send=payments --msg="…" --type=claude   # policy-gated
ft robot wait-for …                 # condition-based, never sleep-based
ft robot events --limit 5           # pattern-triggered detections
ft watch                            # daemonised capture + pattern + workflow loop
ft serve --port 7337                # REST + SSE + WebSocket + OpenAPI
```

Every response is a `RobotResponse` envelope: `{ok, data, elapsed_ms, version, now, schema_version}`. Detection is Aho-Corasick multi-pattern + Bloom prefilter + BOCPD (Bayesian online change-point detection) "to catch novel failure modes regex patterns miss", with rule packs named `agent-claude`, `agent-codex`, `agent-gemini` (`[patterns] packs = ["builtin:core"]`, format at `docs/patterns-pack-format.md`, JSON schema at `docs/json-schema/ft-pattern-pack.json`). Ruleset profiles inherit and can disable rules or override severities per profile. Reads are policy-evaluated and **secret-redacted** before returning text (T1/T2/T3 tiers, with JWT/GitLab/Twilio/SendGrid/Datadog patterns added in 2026-05) so a JWT cannot leak into a notification payload. Workflows declare `trigger_policy()` allowlists so a low-trust pane cannot fire a workflow that acts on a high-trust pane.

Honest caveat: 83 crates, 1.26M lines, Rust nightly, a bespoke async runtime (`asupersync`, with `tokio` banned at dependency and type level), a custom installer with minisign verification and a "process family" transaction model. It is not a dependency you adopt casually. Read it for the API shape and the pattern-engine design.

---

## 4. tmux-native orchestrators, ranked by what is worth taking

### 4.1 claude-squad (https://github.com/smtg-ai/claude-squad, AGPL-3.0, Go, 8.4k stars, pushed 2026-08-20)

Binary is `cs`. Prereqs tmux + gh. Config `~/.claude-squad/config.json` (`cs debug` prints the path):

```json
{"default_program":"claude","auto_yes":false,"daemon_poll_interval":1000,
 "branch_prefix":"jacobmaschler/",
 "profiles":[{"name":"claude","program":"claude"},{"name":"codex","program":"codex"},
             {"name":"aider","program":"aider --model ollama_chat/gemma3:1b"}]}
```

**tmux mechanics** (`session/tmux/tmux.go`): session names are `claudesquad_<sanitised title>` (whitespace stripped, `.` → `_`); created with `tmux new-session -d -s <name> -c <workDir> <program>` started **inside a PTY** (`creack/pty`) rather than plain exec, then polled for existence with exponential backoff 5ms→50ms up to 2s; then `set-option -t <name> history-limit 10000` and `mouse on`. Existence check uses `tmux has-session -t=<name>` with the `=` because "`-t name` does a prefix match, which is wrong". Attach is `tmux attach-session -t <name>` over a PTY, with `Ctrl+Q` (ASCII 17) intercepted from stdin as the detach key, and a neat hack: any bytes arriving in the first 50ms of attach are discarded as terminal control-sequence noise (`?[?62c0;95;0c`, `]10;rgb:f8f8f8`) that varies per terminal.

**Capture**: `tmux capture-pane -p -e -J -t <name>` (`-e` keeps ANSI, `-J` joins wrapped lines), with a `-S start -E end` variant for scrollback.

**State detection** is deliberately minimal, and this is claude-squad's weakness (ccmanager's README calls it out): `HasUpdated()` returns `(updated, hasPrompt)` where `updated` is just "sha256 of the captured pane changed since last tick" and `hasPrompt` is a single literal per program:

```go
if t.program == ProgramClaude {
    hasPrompt = strings.Contains(content, "No, and tell Claude what to do differently")
} else if strings.HasPrefix(t.program, ProgramAider) {
    hasPrompt = strings.Contains(content, "(Y)es/(N)o/(D)on't ask again")
} else if strings.HasPrefix(t.program, ProgramGemini) {
    hasPrompt = strings.Contains(content, "Yes, allow once")
}
```

Statuses are `Running | Ready | Loading | Paused` (`session/instance.go`). There is also `CheckAndHandleTrustPrompt()` which auto-dismisses `"Do you trust the files in this folder?"` and `"new MCP server"` by writing `0x0D` to the PTY.

**AutoYes daemon** (`daemon/daemon.go`): a detached child process (`<self> --daemon`, PID written to `~/.claude-squad/daemon.pid`) that loops every `daemon_poll_interval` ms over stored instances and, for any with `hasPrompt`, calls `TapEnter()` (writes `0x0D` to the PTY) and refreshes diff stats. Blunt, and it does bypass Claude Code's confirmations.

**Worktrees** (`session/git/worktree*.go`) — the most complete implementation I read:
- Branch name `<branch_prefix><sessionName>`, prefix defaulting to `<lowercased username>/`, then sanitised
- Worktree path `~/.claude-squad/worktrees/<sanitised-branch>_<hex nanotime>`, so names never collide
- `Setup()` checks `git show-ref --verify refs/heads/<branch>`; if present, `setupFromExistingBranch()`, else `setupNewWorktree()`
- Existing branch: `git worktree remove -f <path>` then `os.RemoveAll(path)` to clear orphans git no longer tracks, then `git worktree add <path> <branch>`, or if only a remote branch exists, `git worktree add -b <branch> <path> origin/<branch>`
- New branch: same cleanup, then `git branch -D <branch>`, `git rev-parse HEAD`, `git worktree add -b <branch> <path> <headCommit>` — branching from the **commit**, not the branch, "otherwise we'll inherit uncommitted changes from the previous worktree"
- `recordBaseCommit()` stores `rev-parse HEAD` because "leaving it unset makes every git diff invocation fail with an ambiguous argument error"
- `Cleanup()`: `worktree remove -f`, `branch -D` (skipped when `isExistingBranch`), `worktree prune`. `Remove()` drops the worktree but keeps the branch. Pause = remove worktree, keep branch.
- Brand-new repo is detected by the `fatal: ambiguous argument 'HEAD'` string and reported as "please create an initial commit"

Also worth stealing: `GetClaudeCommand()` resolves `claude` by running `$SHELL -c "source ~/.zshrc &>/dev/null || true; which claude"` and then unwrapping alias output with `(?:aliased to|->|=)\s*([^\s]+)`.

Keys: `n` new, `N` new with prompt, `D` kill, `↵/o` attach, `ctrl-q` detach, `s` commit and push, `c` checkout (commit + pause), `r` resume, `tab` preview/diff, `shift-↓/↑` scroll diff.

### 4.2 herdr (https://github.com/herdrdev/herdr)

Beyond the detection manifests in §2.2, the reason to study herdr is that **it is a working implementation of the thing you built with bash**, and its API is the design to copy.

Socket API (https://herdr.dev/docs/socket-api/): newline-delimited JSON over a Unix domain socket (named pipe on Windows). Request `{"id":"req_1","method":"ping","params":{}}`, response `{"id":"req_1","result":{"type":"pong"}}`. Socket resolution order: `--session <name>` → `HERDR_SOCKET_PATH` → `HERDR_SESSION=<name>` → `~/.config/herdr/herdr.sock`; named sessions live at `~/.config/herdr/sessions/<name>/herdr.sock`. Schema is self-describing: `herdr api schema --json`.

Event subscription, which is the thing polling loops want:

```json
{"id":"sub_1","method":"events.subscribe","params":{"subscriptions":[
  {"type":"pane.agent_status_changed","pane_id":"w1:p1","agent_status":"blocked"}]}}
```

Events include `pane.created`, `pane.updated`, `pane.agent_status_changed`, `workspace.created`, `tab.created`.

CLI surface (from the shipped agent skill, https://github.com/herdrdev/herdr/blob/master/skills/herdr/SKILL.md):

```bash
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr pane current --current
herdr pane split --current --direction right --cwd "$PWD" --no-focus   # → .result.pane.pane_id
herdr pane run <pane> "just test"
herdr pane wait-output <pane> --match "test result" --timeout 120000
herdr pane read <pane> --source recent-unwrapped --lines 120   # sources: visible|recent|recent-unwrapped|detection
herdr agent start reviewer --kind codex --pane <pane> -- <agent-args…>
herdr agent prompt reviewer "Review the current diff…" --wait --timeout 120000
herdr agent wait reviewer --until blocked --timeout 120000
herdr agent send-keys reviewer esc|ctrl+c
herdr agent get reviewer
```

Panes inherit `HERDR_ENV=1`, `HERDR_PANE_ID`, `HERDR_TAB_ID`, `HERDR_WORKSPACE_ID`, `HERDR_SOCKET_PATH`, `HERDR_BIN_PATH`. Public IDs are opaque and stable: `w1`, `w1:t1`, `w1:p1`; closed IDs are never reused; a pane moved between workspaces gets a new ID.

Semantics worth copying verbatim:
- `agent prompt` "honors the pane's live bracketed-paste mode and sends text followed by encoded Enter after a short delay. It rejects an agent already waiting at an approval or question dialog with `agent_blocked` before sending any input."
- "A prompt sent from a non-working state must produce an observed lifecycle change within five seconds. Otherwise Herdr returns `agent_prompt_stalled` instead of waiting indefinitely."
- `agent start` returns only once herdr sees the expected agent ready for interactive input (30s default), or `agent_not_ready` immediately if blocked at startup.
- `idle` vs `done`: "`done` is the same underlying idle state after unseen background work finishes. Focusing the tab or targeting the pane or agent with a focus command marks it seen. CLI reads do not mark it seen." That seen/unseen distinction is exactly what turns a board into a triage queue.
- `unknown` "does not prove completion" — a good guard rail.

Custom integration contract (https://herdr.dev/docs/integrations/), which is the shape your cc-* scripts should expose:

```bash
"$HERDR_BIN_PATH" pane report-agent "$HERDR_PANE_ID" \
  --source custom:my-agent --agent my-agent --state working [--message …] [--seq N]
"$HERDR_BIN_PATH" pane release-agent "$HERDR_PANE_ID" --source custom:my-agent --agent my-agent
```

with "Report only when `HERDR_ENV=1`", stable unique `--source`, and monotonic `--seq` (stale sequence numbers from the same source are ignored). Two integration classes: **lifecycle authority** (Pi, OMP, Kimi, OpenCode, Kilo, MastraCode — hooks author state and screen fallback is disabled for that source) and **session identity** (Claude Code, Codex, Copilot, Devin, Droid, Qoder, Qwen, Cursor, Hermes, Antigravity, Grok — the hook only reports the native session reference for restore; state still comes from screen manifests). `herdr integration install claude` writes `~/.claude/hooks/herdr-agent-state.sh` (or under `CLAUDE_CONFIG_DIR`) and adds entries to `settings.json`.

### 4.3 agent-manager (https://github.com/YoanWai/agent-manager)

Covered under detection in §2.5. The rest that matters:

- Sessions live on a **private tmux server**: `tmux -L agentmgr`, session names `am_<id>`, "so they never mix with the tmux you run yourself and a `kill-server` on your own socket leaves them alone". Reach one manually with `tmux -L agentmgr ls` then `tmux -L agentmgr attach -t am_<id>`.
- `space` is the quick prompt: **answer the selected session without attaching**, or spawn an agent in the selected group.
- `ctrl+r` opens full-file syntax-highlighted diffs; `c` comments a line, `C` sends a numbered review round back into the agent's pane as one prompt, and sent comments stay visible as open or handled.
- `f` forks a session into a named fork; `v` revives a dead session on its own conversation; `R` restarts on an empty context keeping name/group/dir/tool.
- Worktrees: `<repo>-worktrees/<name>`, branch `am/<name>`, toggled on the `n` form or with `alt+w` in the quick prompt.
- Revive/fork config is generalised: `resume_by_id_command` with `{id}`, `session_id_flag` (e.g. `--session-id`) to mint an id at launch, or `session_store = "codex"|"opencode"|"gemini"|"hermes"|"command-code"` to read back an id the tool minted; `resume_picker_command` for tools with their own picker (`claude --resume`, `codex resume`, `pi --resume`, `gemini -i /resume`); `fork_command` with `{id}`, `{session_file}`, `{new_id}`, `{name}` placeholders (all shell-quoted, so write `codex resume {id}` bare).
- `prompt_flag` / `prompt_mode = "send"` handles CLIs that take no startup prompt: wait until `activity_cutoff` finds the input box, then submit.
- Debug recipe from the docs, which is exactly how you should tune your own rules: "read the pane the way the poller does — `tmux -L agentmgr capture-pane -p -t am_<id>` — and compare it with the patterns in your block."

### 4.4 dmux (https://github.com/standardagents/dmux, MIT, 1.8k stars) and workmux

dmux: `npm i -g dmux`, tmux 3.0+. One tmux pane per task, each with its own worktree and branch. `n` creates pane + worktree + branch + agent from a prompt; `m` opens a pane menu with **Merge** (auto-commit, merge, clean up in one step) or **Create GitHub PR**. Multi-select launches run several agents on the same prompt with agent-specific branch suffixes. AI-generated branch names, commit messages and pane titles. **Lifecycle hooks on worktree create, pre-merge, post-merge**. Durable terminals: regular terminals restore in their last observed directory, and if Codex/Claude was running it tracks and resumes that conversation when the pane is recreated. Native macOS notifications when a background pane "settles and needs you". Multi-project in one session, per-pane hide/isolate. Docs at https://dmux.ai.

workmux (https://github.com/raine/workmux, Rust, 2.4k stars, pushed 2026-09-03) is the pure "git worktrees + tmux windows" primitive; my worktree-manager research stream is covering it in depth.

### 4.5 claude_code_agent_farm

Covered heavily in §2.4. The other genuinely novel idea is the **coordination protocol implemented purely in the prompt**, no orchestrator code:

```
/coordination/
├── active_work_registry.json
├── completed_work_log.json
├── agent_locks/{agent_id}_{timestamp}.lock
└── planned_work_queue.json
```

Agents mint `agent_{timestamp}_{random4}`, check the registry, write a lock claiming specific files and features, register a scope, and treat locks older than 2 hours as stale. The README's claim is that "this powerful feature is implemented entirely by means of the prompt file! No actual code is needed". Worth knowing as the cheap alternative to a real lock server when your agents share a checkout rather than worktrees.

tmux layout: `new-session -d -s <s> -n controller`, `new-window -t <s> -n agents -e 'POWERLEVEL9K_INSTANT_PROMPT=off'`, then N-1 × (`split-window` + `select-layout tiled`), then `set-option -g pane-border-status top` / `pane-border-format ' #{pane_title} '`. Text is sent via `tmux load-buffer -b <buf> <tmpfile>` + `tmux paste-buffer -d -b <buf> -t <target>` for large payloads (binary-safe) rather than `send-keys`, then `send-keys -t <target> C-m`. Config keys: `agents`, `max_agents` (50), `context_threshold` (20), `idle_timeout`, `max_errors`, `auto_restart`, `tmux_kill_on_exit`, `tmux_mouse`, `git_branch`, `git_remote`, `chunk_size`. Double Ctrl+C within 3s force-kills the session.

### 4.6 Tmux-Orchestrator (https://github.com/Jedward23/Tmux-Orchestrator, 1.8k stars, 334 forks) — historically influential, now stale (last push 2025-07-14)

Included because half the blog posts still cite it, and because it is mostly *prompt engineering*, not code. Three files matter:

`send-claude-message.sh` — the whole "type into another agent" mechanism:
```bash
tmux send-keys -t "$WINDOW" "$MESSAGE"
sleep 0.5            # wait for the UI to register
tmux send-keys -t "$WINDOW" Enter
```
That 0.5s split between text and Enter is the naive version of what herdr does properly with bracketed-paste awareness.

`schedule_with_note.sh` — self-scheduling check-ins, using `nohup bash -c "sleep $SECONDS && tmux send-keys -t $TARGET '…' && sleep 1 && tmux send-keys -t $TARGET Enter" &` with a note file read at wake time. Note the hardcoded `/Users/jasonedward/...` paths, which is why the forks (appressman, absmartly, marwood-inc, mdwoicke) exist.

`tmux_utils.py` — `list-sessions -F "#{session_name}:#{session_attached}"`, `list-windows -F "#{window_index}:#{window_name}:#{window_active}"`, `capture-pane -t <s>:<w> -p -S -<N>` capped at 1000 lines, and a `safety_mode` that prompts for confirmation before any `send-keys`.

Doctrine from `CLAUDE.md`/`LEARNINGS.md` that is still right: hub-and-spoke via a PM because "communication complexity grows exponentially (n²)"; commit every 30 minutes; `git tag stable-[feature]-[date]` before merging; structured status queries ("STOP. Give me status: 1) X fixed? YES/NO 2) Current error?") beat open-ended ones. Also a nice trick: activating plan mode remotely with `tmux send-keys -t s:w S-Tab S-Tab` then verifying with `tmux capture-pane | grep "plan mode on"`.

### 4.7 NTM (https://github.com/Dicklesworthstone/ntm, 435 stars)

"tmux as a local control plane." One Go binary. `ntm spawn api --cc=2 --cod=1 --agy=1` launches a mixed swarm; `ntm send api --cc "…"`; `ntm dashboard api`; `ntm palette api`. Beyond that: **Agent Mail** for coordination, file reservations (`ntm locks`), `ntm worktrees`, checkpoints (`ntm checkpoint save api -m "before auth refactor"`), timelines, audit logs, approval workflows (`ntm safety`, `ntm policy`, `ntm approve`, `ntm guards`), and a full robot surface: `ntm --robot-snapshot`, `--robot-status`, `--robot-send=payments --msg="…" --type=claude`, `--robot-ack=payments --ack-timeout=30s`, `--robot-tail=payments --lines=50`, plus `ntm serve --port 7337` for REST/SSE/WebSocket/OpenAPI. Agent plugins are TOML with `[agent.readiness]` regexes. Resilience config: `[resilience] auto_restart, max_restarts, restart_delay_seconds, health_check_seconds, crash_threshold`.

### 4.8 repomon (https://github.com/AliHamzaAzam/repomon, Apache-2.0, Rust)

The one built for your actual shape of problem: **many repos × many worktrees × many agents**, explicitly contrasting itself with "one repo, many worktrees" tools. Architecture: a `repomond` daemon owning SQLite, file watchers, a gix git layer, and an agent runtime behind a `SessionBackend` trait (tmux on macOS/Linux, per-agent host processes on Windows), exposing JSON-RPC over a Unix socket; the desktop app, the TUI and an iOS companion are all thin clients over that one API, so several can drive the same fleet at once. Lanes = repo + worktree, grouped by project, sorted by recent activity, with the ones waiting on you floated to the top. **Fleet mail** addresses one agent, a lane (`lane-12/*`), or everything (`*`), with per-recipient delivery results. Bundles its own portable tmux so sessions survive closing the window.

### 4.9 The rest of the terminal category (from https://github.com/andyrewlee/awesome-agent-orchestrators)

That curated list is the best discovery surface I found. Worth a look, with the one-line mechanism that makes each distinctive:

- **agent-console** (https://github.com/buhuipao/agent-console, Rust) — finds Codex/Claude/pi sessions **from the providers' own transcript files**, including sessions started elsewhere, and resumes the native agent UI instead of replacing it. No tmux, no worktrees. This is detection mechanism F: read `~/.claude/projects/*/*.jsonl`.
- **Cyclops** (https://github.com/cyclops-team/cyclops) — durable mailbox over tmux with FIFO delivery per recipient and fail-closed human-composer protection.
- **amux** (https://github.com/andyrewlee/amux, Go) — minimal TUI, parallel agents in worktrees.
- **agterm** (https://github.com/umputun/agterm, Swift, 563 stars) — native macOS terminal with named workspaces, attention states and a scriptable control API.
- **tmux-ide** (https://github.com/wavyrai/tmux-ide) — checked-in `ide.yml` describing preset agent-team layouts.
- **hcom** (https://github.com/aannoo/hcom, Rust, 476 stars) — see §5.
- **ClawTeam** (https://github.com/HKUDS/ClawTeam, 5.5k stars) — swarms over tmux worktrees with file-based or ZeroMQ P2P inboxes.
- **codecast** (https://github.com/codecast-sh/codecast) — daemon watching agent history files, giving a live triage inbox plus `cast search`, `cast ask`, `cast blame` (git blame where the author is the agent conversation), and `cast handoff` (context transfer document so a fresh session picks up). Direct comparator for cc-handover.

---

## 5. The messaging layer

Four designs, in increasing order of how much you should copy:

1. **`tmux send-keys` / `wezterm cli send-text`** (Tmux-Orchestrator, agent-farm). Races with the user's typing, breaks on bracketed paste, no delivery confirmation. What you presumably do now.
2. **File-based mailboxes.** Claude Code agent teams: `~/.claude/teams/{team}/inboxes/{agent}.json`, validated on read, "reports a message as sent only when the write to the recipient's mailbox file succeeds". agent-farm: `/coordination/agent_locks/`. ClawTeam: file or ZeroMQ. Simple, durable, no daemon.
3. **A daemon with a socket.** herdr (`events.subscribe` on `pane.agent_status_changed`), NTM Agent Mail with `--robot-ack`, repomon fleet mail with wildcard addressing and per-recipient results, FrankenTerm's SSE/WebSocket.
4. **Claude Code's own per-session sockets** (§1.3). Free, already running, 36 of them on your machine right now, delivered between tool calls without interrupting a running tool, with `notify_when_idle` subscriptions and documented safety semantics (a peer message is never your consent; it cannot approve a permission prompt or change configuration; auto mode re-classifies every inter-agent message).

**hcom** (https://github.com/aannoo/hcom) is the interesting third-party take: single Rust binary, **no background service**. "Hooks record activity to a local SQLite database and deliver messages from it": `agent → hooks → db → hooks → other agent`. Messages arrive mid-turn (injected between tool calls) or wake idle agents immediately. Each agent gets a queryable identity: name, status, inbox, **live terminal screen**, transcript in structured chunks, and an event log of every file edit and tool call. Agents subscribe to events and react. **Collision detection is on by default: if two agents edit the same file within 30 seconds, both get notified.** Usage is `hcom claude` / `hcom codex` in front of the normal command, `hcom` for the TUI dashboard, `hcom send` from any process to wake an agent, `hcom start` to join a hookless tool. Crucially for you: "Any emulator works for spawning. **kitty, wezterm, tmux, zellij, waveterm, cmux, herdr** also support closing panes from `hcom kill`", configurable via `hcom config terminal --info`.

---

## 6. Worktree strategy, compared

| Tool | Worktree path | Branch name | Base | Merge back | gitignored files |
|---|---|---|---|---|---|
| Claude Code native | `.claude/worktrees/<name>` | `worktree-<name>` | `worktree.baseRef`: `fresh` (remote default branch) or `head` | Claude commits and pushes unasked before finishing; opens a draft PR when warranted; never pushes to main/master, never force-pushes, never merges | `.worktreeinclude` (gitignore syntax, gitignored files only) |
| claude-squad | `~/.claude-squad/worktrees/<branch>_<hex nanotime>` | `<user>/<session>` via `branch_prefix` | `git rev-parse HEAD` **commit**, not branch | `s` = commit and push; `c` = commit and pause | none |
| agent-manager | `<repo>-worktrees/<name>` | `am/<name>` | repo default | manual | none documented |
| dmux | per pane | AI-generated | configurable base branch per pane | menu: Merge (auto-commit + merge + cleanup) or Create GitHub PR | lifecycle hooks on worktree create |
| ccmanager | per worktree, in-app create/merge/delete | user-chosen | — | in-app merge | **`.worktreeinclude` support** (same file name as Claude Code) |
| Tmux-Orchestrator | none (shared checkout) | `feature/[task-name]` | current | `git tag stable-[feature]-[date]`, checkout main, merge | n/a |
| agent-farm | none (shared checkout + lock files) | `git_branch` config | current | git commits with diff summaries | n/a |

The interesting convergence: `.worktreeinclude` is now a de facto standard across Claude Code and ccmanager. And claude-squad's "branch from the resolved HEAD commit, not the branch name" is a subtle correctness win you should copy if you create worktrees yourself, because it stops uncommitted changes leaking in.

Claude Code's locking is the most careful design: it holds a `git worktree lock` for the life of an agent, its sweep releases locks left by killed sessions but never one you set yourself, and it writes a marker into git metadata so the sweep can distinguish worktrees it made from yours (v2.1.246+).

---

## 7. What to actually steal, in priority order

**1. Replace cc-board's state detection with `wezterm cli list --format json` (30 minutes, zero dependencies).** Your pane titles already carry `✳` for idle and `◐◑` for working, plus a Haiku-written topic. Verified on your machine right now: 33 idle, 3 working, across 63 panes. Match `^\x{2733} ` for idle and `^[\x{2800}-\x{28FF}\x{25D0}-\x{25D3}] ` for working, per herdr's `claude.toml`. Check `terminalTitleFromRename: false` if you use `--name`.

**2. Join it to `claude agents --json` for the states the title cannot express.** The title cannot distinguish "waiting on a permission dialog" from "idle". `claude agents --json` gives you `status: idle|busy|waiting` plus `waitingFor: "dialog open"|"input needed"|"permission prompt"|…`, keyed by `pid`, `cwd`, `name`, `sessionId`. Join on `cwd` and pane ordering, or better: emit `$WEZTERM_PANE` from a `SessionStart` hook into a per-session file so you have an exact pane↔session map.

**3. Adopt the hybrid authority model from agent-manager.** Hooks write authoritative state to a per-session file; the poller reads it first; pane rules refine (they see plain-text questions, Esc interrupts, and error lines that hooks cannot) and take over when the file is missing or stale. Wire `PermissionRequest` (immediate) rather than `Notification/permission_prompt` (six-second delay) for the "needs you" signal, and use `Stop` with its `background_tasks[]` array to distinguish "finished" from "paused waiting on background work". Add `StopFailure` matching `rate_limit` → errored.

**4. Steal ccmanager's three anti-flapping refinements verbatim.** 1.5s idle debounce on unchanged content; busy detection only on the most recent contiguous block *above* the prompt box (found by scanning up for two `─` border lines); and `/\d+\.\s*deny\s*\(esc\)/` for permission menus with no question phrasing. Without these you will get false idles on redraw and false busies from your own typed text. Source: https://github.com/kbwo/ccmanager/blob/main/src/services/stateDetector/claude.ts

**5. Add a "seen" dimension, not just a state.** herdr's `idle` vs `done` distinction ("`done` is the same underlying idle state after unseen background work finishes … CLI reads do not mark it seen") and agent-manager's `finished ●` alert that clears to `idle ○` only when you enter the session are what turn a status list into a triage queue. Combined with wezterm-attention's `.ack` sidecar pattern (acknowledge by writing a sidecar, never by deleting writer-owned state) and its priority ordering `notify > stop > review > thinking`.

**6. Replace `wezterm cli send-text` for agent-to-agent notes with the Claude Code inbox socket.** `/tmp/cc-socks/<pid>.sock`, pid from `claude agents --json`, optional auth line `{"type":"auth","token":"$CLAUDE_CODE_MESSAGING_TOKEN"}`, connect only when the message is ready (30s line timeout). Delivered between tool calls, never interrupting a running tool, with documented safety semantics. This is a strict upgrade for cc-note.

**7. Install `wezcld`, or copy its 40 lines,** to get Claude Code agent teams' split-pane mode in WezTerm. `TERM_PROGRAM=iTerm.app`, an `it2` shim on `PATH` translating `session split` → `wezterm cli split-pane` and `session run -s <id>` → `wezterm cli send-text --pane-id <id>`, then `claude --teammate-mode tmux`. https://github.com/afewyards/wezcld

**8. Move worktree creation to a `WorktreeCreate` hook** if you want them somewhere other than `.claude/worktrees/`. You keep `--worktree`, `--worktree "#1234"`, subagent `isolation: worktree`, and background-session isolation, while controlling layout. Pair with `WorktreeRemove`. Remember the hook replaces `.worktreeinclude` processing, so copy `.env` yourself. Otherwise just adopt `.worktreeinclude` and `worktree.baseRef` and delete that code.

**9. Give cc-fleet a machine surface, not just a TUI.** herdr's `herdr api schema --json`, NTM's `--robot-*` family, and FrankenTerm's `{ok, data, elapsed_ms, version, now, schema_version}` envelope all exist because the primary consumer is another agent. The two operations that matter most: `wait --until blocked|done|idle --timeout` (condition-based, never `sleep`) and an event subscription on state change. herdr's `agent_prompt_stalled` guard (a prompt sent from a non-working state must produce a lifecycle change within 5 seconds, or fail loudly) is the single best error-handling idea in the whole category.

**10. Adaptive timeouts and heartbeats for anything unattended.** agent-farm's `3 × median cycle time` clamped to 30-600s, updated only on >20% change, plus heartbeat files whose age >120s means "restart" and a context threshold that triggers `/clear` rather than a full restart. And its `echo AGENT_FARM_READY_<rand>` probe for proving a shell is live regardless of prompt shape.

---

### Things to be aware of

- Claude Code's `agent_needs_input` and `agent_completed` Notification types **only fire while agent view is open in a terminal** (https://code.claude.com/docs/en/hooks#notification). If you want them as a fleet signal, something must keep `claude agents` open, or you use `PermissionRequest` + `Stop` instead.
- Agent teams' split-pane mode does not support WezTerm without the `wezcld` shim, and its default became `"in-process"` at v2.1.179, so an upgraded session that used to split panes now stays in one terminal unless `teammateMode` is set explicitly.
- Agent teams do **not** worktree-isolate teammates. You must partition files yourself.
- Two 2026 casualties suggest where this is heading: Crystal deprecated (Feb 2026) and Vibe Kanban sunsetting. Betting your workflow on a third-party GUI orchestrator looks worse than betting on the CLI's own primitives plus your own bash.
- Verify claude-squad's AutoYes and any `--dangerously-skip-permissions` pattern against your own risk tolerance; ccmanager's README pointedly notes AutoYes "bypasses Claude Code's built-in security confirmations".