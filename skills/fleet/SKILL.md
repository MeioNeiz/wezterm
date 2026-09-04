---
name: fleet
description: Inspect, drive and reorganise the live Claude Code sessions and wezterm panes on this machine, and move work between them. Use when asked what is running, what needs attention, which chats are stale or finished, to jump to / close / regroup sessions, or to work out what another session is doing. Also covers handing work from a session that is full to a fresh one ("hand this over", "I'm running out of context", "start a fresh agent on this", "pick up where X left off"), starting a new session on a task, annotating a session with what it is waiting on, and watching panes over time. Triggers on "what's running", "what needs me", "which chats are stale", "tidy up my panes", "move the X work onto one tab", "close the finished ones", "what is <name> doing", "where is the <topic> chat", "hand this over", "fresh agent", "tell me when X finishes", "wait for <name>", "which pane is using all the CPU", "find the pane with <text>".
---

# The fleet

This machine usually has 20-40 live Claude sessions across a dozen wezterm workspaces.
This skill is how to see them, drive them, and move work between them.

Terminology: **workspace** ≈ project (1:1 with a GUI window here), **tab** = a screen of
panes, **pane** = one Claude session. Session names (`d5-lca-49`) are also SendMessage
addresses, and every tool below takes one wherever it takes a pane id.

## What to reach for

| you are asked | reach for | cost |
|---|---|---|
| what is running / what wants me | `cc-fleet` | 90ms cached |
| the address of a session | `cc-roster` | 90ms |
| what a session is *about* | `cc-peers` | 130ms |
| what a session last **said** | `wz last <name>` | 140ms |
| what is on a pane's screen | `wz read <name>` | 95ms |
| move work to a fresh session | `cc-handover --new` | ~500ms |
| start a session on a task | `cc-spawn '<task>'` | instant |
| record what a session is waiting on | `cc-note status '...'` | free |

**`cc-roster` is the cheap one and the right default.** It answers who is alive, what
state they are in and which pane holds them, with no titles. `cc-peers` is that plus a
title per session, which is the expensive half. Prefer `cc-roster` unless you actually
need to know what a session is about.

## Reading

```bash
cc-fleet                    # dashboard: grouped by workspace, ranked by what wants you
cc-fleet --json             # same rows, parseable - prefer this when reasoning about them
cc-fleet --stale [H]        # only sessions with no prompt from Jacob in H hours (default 8)
cc-roster                   # sid, name, status, detail, pane, cwd, pid, seen, started
cc-peers                    # the addressing roster, with titles
cc-board --once --all       # the grid: every session, with what it last said
wz tree -c -a               # every Claude session as panes: workspace, window, tab, dir
wz last <name>              # what it last said, and whether that ends in a question
wz read <name> [-n 400]     # what is on screen; -n pulls scrollback
wz grep -a 'Traceback' -s   # search every pane's text; -s focuses the first hit
wz top -a                   # cpu and rss per pane, busiest first
```

`cc-fleet --json` fields: `workspace, window, tab_id, pane, name, state, blocked_on,
idle_seconds, your_turns, dir, title, id`.

Three things about that data:

- **`idle_seconds` is time since *Jacob* last prompted it**, not since it did anything.
  `-1` means he has never prompted it at all - usually a peer handover nobody read. An
  agent talking to itself for an hour does not make the work live.
- **`state` is `busy`, `idle`, `shell`, `asking` or `waiting`.** `asking` and `waiting`
  both mean it has stopped and wants an answer; `blocked_on` says what ("input needed",
  or the tool it is blocked on). Both rank top of the dashboard.
- **A stopped session may still be waiting without saying so.** The Stop hook fires
  whether it finished or stopped to ask, so `idle` alone does not mean done. `wz last
  <name>` is the cheap check: it reads the transcript rather than the screen, so it
  works after the pane has scrolled. Do not report an idle session as "done" without it.

## Handing work over

The thing Jacob does by hand and should not: a session fills up, and he scrolls back and
copies the last message into a fresh pane. That loses what he actually asked, what he
said mid-turn, the branch, the files it had open and anything it recorded for itself.

```bash
cc-handover --new                     # fresh session in a pane to the right, seeded
cc-handover --new --tab               # on its own tab; also --window, --down
cc-handover d5-lca-48 --new           # hand over a different session
cc-handover --why 'context full' --new
cc-handover                           # just print the brief
cc-handover --to 7                    # paste it into a pane already open, unsent
cc-handover --new --dry-run           # show the command, run nothing
```

The brief carries the last real prompt (not Claude's truncated `last-prompt` record),
every message queued while the turn was running, the last few substantive replies, the
branch and dirty count, the files it was editing, whatever `cc-note` holds, and the path
to the source transcript. That last part matters: **the successor can read the original
conversation** rather than work from a summary of it. Say so when handing over.

The old session is not closed and loses nothing - `claude --resume <id>` reopens it. Ask
before closing it.

**A session can hand itself over.** If you are near full, run `cc-handover --new` and
tell Jacob where the work went.

## Starting work

```bash
cc-spawn 'read src/auth.ts and list every path that skips the guard'
cc-spawn --tab --cwd ~/work/api 'run the failing test and say why it fails'
cc-spawn --window --dry-run '...'     # check the command first
cc-spawn --shell                      # a plain pane to watch something in
```

Always start sessions through `cc-spawn`, never `wezterm cli spawn -- claude` directly.
A session spawned from inside another inherits `CLAUDE_CODE_CHILD_SESSION` and **saves
no transcript**: no title, no name in `cc-peers`, nothing on its statusLine, and it can
never be handed over. `cc-spawn` clears the environment first. Nothing warns you.

A fresh session in a directory Claude has not seen before stops on a trust prompt before
the task lands. Spawning into a directory that already has sessions avoids it.

## What a session says about itself

`cc-note` is the only writable layer here - everything else is derived from Claude's own
files. Keyed by session id, so a note survives a pane move and a `--resume`, and stops
applying at `/clear`. Inside a session it needs no target and costs no lookup.

```bash
cc-note status 'waiting on the staging deploy'   # shows on its statusLine and cc-fleet
cc-note progress 3 7
cc-note todo add 'backfill the 2019 rows'        # todo done 1 | list | clear
cc-note log 'ruled out the CDN'                  # log --tail 20
cc-note mute                                     # stop it competing for attention
cc-note list --json                              # every annotated session
cc-note show --for d5-lca-48
cc-note clear
```

Use it when you park work, when you are blocked on something outside the machine, or
when a long job has steps worth counting. A status note displaces the topic on
`cc-fleet`, because it is newer and it says what is actually holding the work up.

## Acting

```bash
wz go <name>                    # focus a session, switching tab and workspace
wz join <src> <target> --right  # regroup: move src beside target, across tabs and windows
wz break <name>                 # move a pane out to its own tab
wz send --enter <name> 'yes'    # type into a pane; wz key <name> ctrl-c enter for keys
wz notify 'title' 'body'        # desktop notification

wezterm cli activate-pane --pane-id N
wezterm cli kill-pane --pane-id N
wezterm cli adjust-pane-size --pane-id N --amount 10 Left
wezterm cli set-tab-title --tab-id N "cutover"
wezterm cli zoom-pane --pane-id N [--unzoom]
```

`split-pane --move-pane-id` is the regrouping primitive `wz join` wraps: it relocates a
live pane into a split of the target, across tabs and windows, and it is reversible.
This is how "put the cutover work on one tab" gets done.

**`tab_id` is not the tab number.** The tab bar and `LEADER+1..9` count positions from
one; ascending `tab_id` within a window is that order. Convert before saying "tab 9" to
Jacob, or he will be looking at his fourth tab.

## Watching

Polling, because wezterm has no outbound event stream and the states worth waking for
are Claude's anyway. The daemon diffs a snapshot every two seconds and is not running by
default.

```bash
wz wait <name> --state idle --timeout 600   # block until a session stops working
wz pipe <name> --command 'grep -i error'    # stream a pane's new lines
wz events --daemon &                        # start the poller
wz events --follow --name state-changed     # pane-opened|closed, state-changed,
                                            #   title-changed, workspace-moved
wz events --cursor-file ~/.claude/cache/mycursor   # resumable
wz wait --event pane-closed --timeout 60    # needs the daemon
```

**`wait --state` needs no daemon** - it polls `cc-roster`, which is what knows `asking`
from `idle`. Only `wait --event` depends on the log.

**`pipe` line-diffs a screen**, so it is right for output that scrolls and wrong for a
full-screen TUI, which repaints in place. Do not point it at another Claude pane and
expect a transcript; use `wz last` for that.

## Talking to another session

`cc-roster` lists every live session by name. `SendMessage({to: "<name>", message:
"..."})` routes to it. Match on the title from `cc-peers` rather than asking which
window was meant. Names default to cwd plus a random suffix, so several in one repo look
alike until `/rename`.

## Rules

- **Never kill a pane whose state is `busy`, `asking` or `waiting`.** One is mid-turn,
  the other two are holding a prompt open for an answer.
- **Confirm before anything mutating** - killing, moving, retitling, handing over into a
  pane that already has something in it. Say which sessions by name and what will
  happen, then wait. Reading is free; rearranging someone's desk is not.
- Closing a pane does not lose the conversation: `claude --resume <id>` brings any of
  them back. Say so when proposing a clear-out; it changes the decision.
- Prefer `cc-fleet --json` over parsing the dashboard, and `--stale` over inventing a
  staleness rule.
- Don't kill a `never`-prompted session without saying what it was: it is usually a
  handover from another session that nobody has read, and the ask may still matter.

## Gotchas

- The `SessionStart` hook writes `~/.claude/wezterm-sessions/$WEZTERM_PANE`
  unconditionally, so a nested `claude` run inside a pane hijacks that pane's mapping
  and corrupts the PANE column until the real session writes again.
- Duplicate session names happen (two `d5-lca-b3`). SendMessage then reaches whichever
  the roster lists first. Flag it rather than guessing.
- `~/.claude/bin` is not on PATH. Every script is reachable by name only because
  `~/.local/bin` symlinks to it. A new script needs both links or it fails silently.
- Colour: status is a dot, identity is a text colour, and nine hues over forty sessions
  means duplicates. Details in `reference/colour.md`; don't describe a colour to Jacob
  as unique without checking `cc-board`'s "N alike" flag.
- The machinery notes are in `~/personal/wezterm/CLAUDE.md`, which is the place to look
  before changing any of these scripts. Session addressing lives in
  `~/.claude/context/session-addressing.md`.
