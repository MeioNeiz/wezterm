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

Costs are output tokens, paid every call. **Start with `cc-fleet --brief`**; reach past it
only for a field it does not carry, and prefer `--tsv` to `--json` when you do.

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
| enough to **continue** its work | `cc-handover <name>` | ~260-900 |
| ...two sessions at once | `cc-handover a b` | ~1150 |
| ...the rest of this tab | `cc-handover .tab` | the same |
| only the sessions on this tab | add `--tab` to any cc-fleet | scoped, so less |
| organise panes by topic | `cc-sort` (dry), `--apply` after Jacob agrees | 0: Kev |
| what was handed over yesterday | `cc-handovers` (`-d 0` today) | ~1-2k |
| what a background job ended with | `cc-fleet --job <id>` | the job's last output |

`cc-fleet --brief` also names any session past 60% of its context window, fullest first
(`cc-handover --new` is what to do about it), the idle sessions whose prompt cache has gone
cold with what resuming them would re-read, and background jobs (`claude --bg`, no pane)
that have finished unseen; `cc-fleet --job <id>` shows what one ended with.

**"Catch me up on what they were doing" is `cc-handover`, not a pane read.** The brief is
about half the size of both screens and carries the last prompt, queued messages, branch,
files touched and transcript path, all of which a screen has usually scrolled past. Use
`wz read` only when the question is what is *on* that screen.

**No read here wakes a session**: all go via Claude's files or wezterm's screen buffer.
Only three things touch a pane: `cc-handover --to <pane>` (pastes, unsent), `--new` and
`cc-spawn` (a new pane, source untouched), and SendMessage. Never ask a session what it is
doing when reading it is free and silent.

`--tsv` columns, **no header row**: `workspace, window, tab_id, pane, name, state,
blocked_on, idle_seconds, your_turns, dir, title, id`.

**`--tab` scopes any cc-fleet mode to the sessions sharing this pane's tab**, counts and
footers included: "the other panes here" without the whole machine.

Three things about that data:

- **`idle_seconds` is time since *Jacob* last prompted it**, not since it did anything.
  `-1` means never: usually a handover nobody read.
- **`state` is `busy`, `idle`, `shell`, `errored`, `asking` or `waiting`.** The last two
  both mean stopped and wanting an answer; `blocked_on` says what, and on a `waiting` it
  is the session's own word for it: `permission prompt` and `input needed` want Jacob now,
  `dialog open` and `sandbox request` are a different kind of stuck, `worker request` is
  not about him at all.
- **`idle` does not mean finished.** Stop fires whether a session finished or stopped to
  ask. `wz last <name>` is the check (the transcript, ~60 tokens, works after scrolling);
  don't report a session as done without it, and don't use `wz read` (~3600) to find out.

## Handing work over

What Jacob would otherwise do by hand, copying the last message into a fresh pane, losing
what he asked, what he said mid-turn, the branch, the open files and the session's notes.

```bash
cc-handover --new                  # fresh session in a pane to the right, seeded
cc-handover --new --tab            # also --window, --down
cc-handover d5-lca-48 --new --in 12     # split from pane 12, landing in that pane's tab
cc-handover d5-lca-48 --new        # a different session
cc-handover d5-lca-08 d5-lca-65 --new   # two sessions' work continuing as one
cc-handover .tab                   # every other live session on this tab
cc-handover .tab --new --window    # the whole tab's work continuing in one session
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

Queued messages keep their author (Jacob's, another agent's attributed, task-notifications
dropped); anything over ~1100 characters keeps both ends and says how much was cut.

**The cache rule.** A session whose prompt cache is **cold never gets woken or resumed**:
not pasted into, not sent a message, not `claude --resume`d, because any of those
re-reads its whole context. Hand its work to a fresh session (`cc-handover <name> --new`)
that reads the transcript and output from disk. **Warm, resuming is fine.** The brief
says which applies (also on stderr): warm keeps a `claude --resume` line, cold says what
a resume would cost and that the brief replaces it, and `--to` refuses an idle cold
target. Sessions never talk to each other to hand over: no asking one to summarise its
work for a successor. The brief, the transcript, its background tasks' output files and
`wz read <pane> -n 200` on its scrollback are the handover.

`.tab` is the same target grammar as `.`, and it means every *other* live session on this
pane's tab, in wezterm's own left-to-right order, skipping panes holding no session. It
exists because "hand me the rest of this tab" otherwise takes three calls and a join.

**A bare word in a cc-spawn argument list ends the options** and the rest becomes the
prompt, `--dry-run` included. Flags only, before the prompt.

Nothing is lost: closing a pane keeps the transcript, which is all a successor reads, and
a warm session can still be resumed. Ask before closing it.
**A session can hand itself over** - if you are near full, run it and say where the work
went.

## Starting work

```bash
cc-spawn 'read src/auth.ts and list every path that skips the guard'
cc-spawn --tab --cwd ~/work/api 'run the failing test and say why'
cc-spawn --shell                   # a plain pane to watch something in
cc-spawn --ask '...'               # leave permission prompts on
cc-spawn --worktree=auth-guard '...'    # its own checkout, its own branch
cc-spawn --dry-run '...'
cc-spawn --effort low 'verify the email draft at ... against docs/...'
```

**Choose `--effort` when you write the brief.** Effort is per session, so spawn time is
the only moment it can be set; the default is xhigh. `low` for a lookup, a verifier, a
one-shot answer or a standby session; leave it out for real work. `--model` likewise.

**`--worktree` when two sessions would otherwise edit the same repo at once.** Claude
Code makes it at `<repo>/.claude/worktrees/<name>` on `worktree-<name>`, locked for the
session's life, with gitignored files from `.worktreeinclude`. Opt-in: sessions sharing
a checkout is normal here, and only a problem when they write at the same time. Needs a
git repo; cc-spawn checks before opening the pane.

Spawned sessions run with `--dangerously-skip-permissions`, as every agent here does;
`--ask` opts out, and there is rarely a reason to.

**Always `cc-spawn`, never `wezterm cli spawn -- claude`.** A session spawned from inside
another inherits `CLAUDE_CODE_CHILD_SESSION` and saves no transcript: no title, no name,
nothing on its statusLine, and it can never be handed over. `cc-spawn` clears the
environment. Nothing else warns you.

A directory Claude has not seen stops on a trust prompt before the task lands. Bypass
does not cover that one, so it is the only prompt a spawned session can still sit on.

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

**`needs` is for something Jacob has to do away from the keyboard**: a login, an
approval, a card to tap. Two levels, because a notification per pane trains him to ignore
all of them:

- **quiet** (default): the pane's statusLine, the first line of `cc-fleet --brief`, and
  `●N needs you` in red on the status bar of whatever window he is in, until cleared.
- **`--now`**: the same plus a chime. Only when there is a clock on the thing.

Clear it with `cc-note needs --clear` once he has done it.

Otherwise use `status` when you park work or are blocked on something off-machine, and
`progress` when a long job has steps worth counting.

## Rules

- **Never kill a pane whose state is `busy`, `asking` or `waiting`.** One is mid-turn,
  the others hold a prompt open. `busy` now also covers a session whose turn is over but
  whose own background work is not, so this is stricter than it looks.
- **`errored` means the turn died on an API error**, usually a rate limit, and Claude
  Code does not retry it. The session is fine; it needs a nudge to carry on. `cc-fleet
  --brief` names the error kind in brackets.
- **Confirm before anything mutating**: killing, moving, retitling, handing into a pane
  that already has something in it. Name the sessions, say what will happen, then wait.
- Closing a pane loses no conversation: the transcript stays on disk for a successor to
  read. Say so when proposing a clear-out; it changes the decision.
- Don't kill a `never`-prompted session without saying what it was: usually a handover
  nobody has read, and the ask may still matter.
- Prefer `cc-fleet --stale` over inventing a staleness rule.
- **PushNotification reaches Jacob as a sticky toast** that waits until he looks. Use it
  only for what cannot wait for him to glance at the board: a decision blocking work, a
  failure, something done that he asked to hear about at once. Not for routine finishes;
  the Stop hook already toasts those.

## Gotchas

- A `claude` run from a session's Bash tool inherits `WEZTERM_PANE`. The pane hooks and
  cc-tint see it has no controlling tty and stay out, so it never shows on the board or
  takes the pane's map; it is not a fleet member and no tool here will find it.
- Duplicate session names happen. SendMessage reaches whichever is listed first - flag it
  rather than guessing.
- **A name can move.** Claude renames a session on a collision, on `/rename`, and on a
  resume; background sessions get named after their task. Every tool here takes the old
  name too and says `cc-roster: "x" is now "y"` on stderr when you use one, so pass that
  on rather than swallowing it. A name Claude built from a task has spaces in it, and
  every tool here shows and takes the folded form instead - `bash-command-execution` -
  which SendMessage accepts too. What never moves is the session id, which is what
  `cc-note` is keyed by.
- Every script needs links in **both** `~/.claude/bin` and `~/.local/bin`; only the
  second is on PATH, and the failure is silent because hooks call by full path.
- Nine identity hues over forty sessions, so colours repeat. `cc-board` flags a tab where
  two panes share one; don't call a colour unique without checking.

More: `reference/watching.md` (wait, events, pipe, and rearranging panes),
`reference/colour.md` (the two colour channels). Changing any of this: work in
`~/personal/wezterm`, whose CLAUDE.md routes to the rules and the state-file formats.
