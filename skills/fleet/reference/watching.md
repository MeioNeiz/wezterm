# Watching panes over time

Polling, because wezterm has no outbound event stream and the states worth waking for are
Claude's anyway. The daemon diffs a snapshot every two seconds and is not running by
default, so there is a 2s floor on anything that goes through the log.

```bash
wz wait <name> --state idle --timeout 600   # block until a session stops working
wz pipe <name> --command 'grep -i error'    # stream a pane's new lines
wz events --daemon &                        # start the poller that fills the log
wz events --status | --stop
wz events --follow --name state-changed     # pane-opened|closed, state-changed,
                                            #   title-changed, workspace-moved
wz events --cursor-file ~/.claude/cache/mycursor   # resumable: only what you have not seen
wz wait --event pane-closed --timeout 60    # needs the daemon
```

**`wait --state` needs no daemon.** It polls `cc-roster`, which is what knows `asking`
from `idle` in the first place. Only `wait --event` depends on the log.

**`pipe` line-diffs a screen**, so it reads cleanly only for output that scrolls. A
full-screen TUI repaints in place and its "new" lines are whatever the redraw happened to
touch. Fine for a shell or a log, useless pointed at another Claude pane - use `wz last`
for that.

`wz notify 'title' 'body'` raises a desktop notification. It is fire and forget: no read
state, no dismissal, and no way to jump to the pane it came from.

## Rearranging panes

```bash
wz go <name>                    # focus a session, switching tab and workspace
wz join <src> <target> --right  # move src beside target, across tabs and windows
wz break <name>                 # move a pane out to its own tab

wezterm cli activate-pane --pane-id N
wezterm cli kill-pane --pane-id N
wezterm cli adjust-pane-size --pane-id N --amount 10 Left
wezterm cli set-tab-title --tab-id N "cutover"
wezterm cli zoom-pane --pane-id N [--unzoom]
wezterm cli split-pane --pane-id TARGET --move-pane-id N --right
```

`split-pane --move-pane-id` is the regrouping primitive `wz join` wraps: it relocates a
live pane into a split of the target, across tabs and windows, and it is reversible. This
is how "put the cutover work on one tab" gets done.

**`tab_id` is not the tab number.** The tab bar and `LEADER+1..9` count positions from
one; ascending `tab_id` within a window is that order. Convert before saying "tab 9" to
Jacob, or he will be looking at his fourth tab.
