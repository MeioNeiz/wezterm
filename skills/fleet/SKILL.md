---
name: fleet
description: See and drive the live Claude Code sessions and wezterm panes on this machine, and move work between them. Use for what is running, what needs attention, what a session is doing, which chats are stale, jumping to / closing / regrouping panes; for handing work from a full session to a fresh one ("hand this over", "running out of context", "fresh agent", "pick up where X left off"); for starting a session on a task; for recording what a session is waiting on; and for waiting on or watching a pane.
---

# The fleet

20-40 live Claude sessions across a dozen wezterm workspaces. **workspace** ≈ project
(one GUI window), **tab** = a screen of panes, **pane** = one session. Session names
(`d5-lca-49`) are SendMessage addresses, and every tool here takes one wherever it takes
a pane id. `.` means the calling session.

## What to reach for

Costs are output tokens, which is the budget that matters: you pay them every call.

| asked | run | tokens |
|---|---|---|
| what wants me / what's running | `cc-fleet --brief` | **~20-45** |
| the whole dashboard | `cc-fleet` | ~770 |
| every field, parseable | `cc-fleet --tsv` | ~920 |
| ...as JSON | `cc-fleet --json` | ~1960 |
| what a session last **said** | `wz last <name>` | **~60** |
| the last few lines on screen | `wz read <name> --tail 5` | ~430 |
| a whole pane's screen | `wz read <name>` | ~3600 |
| what a session is *about* | `cc-peers` | ~660 |
| name → pane, for scripts | `cc-roster` | ~1060 |

`cc-fleet --brief` also names any session past 60% of its context window, fullest first,
because that is the fact that leads somewhere: `cc-handover --new` is what to do about
it, and nothing else says when to reach for it.

**Start with `cc-fleet --brief`.** It answers the usual question in 20 tokens; the other
five cost 30-100x that for information nobody asked for. Reach past it only when you need
a field it does not carry, and prefer `--tsv` to `--json` when you do.

`--tsv` columns: `workspace, window, tab_id, pane, name, state, blocked_on, idle_seconds,
your_turns, dir, title, id`.

Three things about that data:

- **`idle_seconds` is time since *Jacob* last prompted it**, not since it did anything.
  `-1` means never - usually a handover nobody read. An agent talking to itself for an
  hour does not make the work live.
- **`state` is `busy`, `idle`, `shell`, `asking` or `waiting`.** The last two both mean
  stopped and wanting an answer; `blocked_on` says what.
- **`idle` does not mean finished.** The Stop hook fires whether a session finished or
  stopped to ask. `wz last <name>` is the check: it reads the transcript rather than the
  screen, so it still works after the pane has scrolled, and it costs ~60 tokens against
  `wz read`'s ~3600. Don't report a session as done without it, and don't reach for
  `wz read` to find out - that is the single most expensive habit here.

## Handing work over

The thing Jacob does by hand and shouldn't: a session fills up, he scrolls back and
copies the last message into a fresh pane. That loses what he actually asked, what he
said mid-turn, the branch, the open files, and anything the session recorded for itself.

```bash
cc-handover --new                  # fresh session in a pane to the right, seeded
cc-handover --new --tab            # also --window, --down
cc-handover d5-lca-48 --new        # a different session
cc-handover d5-lca-08 d5-lca-65 --new   # two sessions' work continuing as one
cc-handover --why 'context full' --new
cc-handover                        # print the brief, spawn nothing
cc-handover --to 7                 # paste into an open pane, unsent
cc-handover --new --dry-run        # show the command, run nothing
```

Several targets merge into one brief, a section each. The brief carries the last real
prompt, what was queued mid-turn, the last substantive replies, branch and dirty count,
files edited, `cc-note` state, and **the path to each source transcript** - so the
successor reads the original conversation instead of working from a summary. Say that
when you hand over.

Queued messages are told apart rather than lumped together: Jacob's stay his, another
agent's are attributed to it, and task-notifications are dropped. Anything over ~1100
characters keeps both ends and says how much was cut, so a pasted document does not get
re-ingested whole.

Nothing is lost: `claude --resume <id>` reopens the old session. Ask before closing it.
**A session can hand itself over** - if you are near full, run it and say where the work
went.

## Starting work

```bash
cc-spawn 'read src/auth.ts and list every path that skips the guard'
cc-spawn --tab --cwd ~/work/api 'run the failing test and say why'
cc-spawn --shell                   # a plain pane to watch something in
cc-spawn --dry-run '...'
```

**Always `cc-spawn`, never `wezterm cli spawn -- claude`.** A session spawned from inside
another inherits `CLAUDE_CODE_CHILD_SESSION` and saves no transcript: no title, no name,
nothing on its statusLine, and it can never be handed over. `cc-spawn` clears the
environment. Nothing else warns you.

A directory Claude has not seen stops on a trust prompt before the task lands.

## What a session says about itself

`cc-note` is the only writable layer; everything else is derived from Claude's files.
Keyed by session id, so it survives a pane move and `--resume` and stops at `/clear`.
Inside a session it needs no target and no lookup.

```bash
cc-note needs 'log in to the DigitalFive dashboard'      # quiet: see below
cc-note needs --now 'approve the deploy'                 # quiet, and a sound now
cc-note status 'waiting on the staging deploy'   # shows on its statusLine and cc-fleet
cc-note progress 3 7
cc-note log '...'           # log --tail 20
cc-note mute                # stop it counting towards "wants you elsewhere"
cc-note show --for d5-lca-48
cc-note list --json
```

**`needs` is for something Jacob has to do away from the keyboard** - a login, an
approval, a card to tap. Two levels, because a notification for every pane that wants
something trains him to ignore all of them:

- **quiet** (default): the pane's statusLine, the first line of `cc-fleet --brief`, and
  `●N needs you` in red on the wezterm status bar of whatever window he is looking at.
  No sound, nothing to dismiss, and it stays until cleared.
- **`--now`**: the same plus a chime. Use it only when there is a clock on the thing.

Clear it with `cc-note needs --clear` once he has done it.

Otherwise use `status` when you park work or are blocked on something off-machine, and
`progress` when a long job has steps worth counting.

## Rules

- **Never kill a pane whose state is `busy`, `asking` or `waiting`.** One is mid-turn,
  the others hold a prompt open.
- **Confirm before anything mutating** - killing, moving, retitling, handing into a pane
  that already has something in it. Name the sessions and say what will happen, then
  wait. Reading is free; rearranging someone's desk is not.
- Closing a pane loses no conversation (`claude --resume <id>`). Say so when proposing a
  clear-out; it changes the decision.
- Don't kill a `never`-prompted session without saying what it was: usually a handover
  nobody has read, and the ask may still matter.
- Prefer `cc-fleet --stale` over inventing a staleness rule.

## Gotchas

- The `SessionStart` hook writes `~/.claude/wezterm-sessions/$WEZTERM_PANE`
  unconditionally, so a nested `claude` run hijacks that pane's mapping until the real
  session writes again.
- Duplicate session names happen. SendMessage reaches whichever is listed first - flag it
  rather than guessing.
- Every script needs links in **both** `~/.claude/bin` and `~/.local/bin`; only the
  second is on PATH, and the failure is silent because hooks call by full path.
- Nine identity hues over forty sessions, so colours repeat. `cc-board` flags a tab where
  two panes share one; don't call a colour unique without checking.

More: `reference/watching.md` (wait, events, pipe, and rearranging panes),
`reference/colour.md` (the two colour channels). Machinery notes and the rules for
changing any of this: `~/personal/wezterm/CLAUDE.md`.
