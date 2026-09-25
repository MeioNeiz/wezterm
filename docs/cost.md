# What it costs, in time and in tokens

Pointed at from CLAUDE.md.

## what it costs

Measured on a machine with 59 panes and 33 live sessions, because every one of these
runs against the whole fleet and none of them is interesting at n=1.

| path | when | cost |
|---|---|---|
| `statusline.sh` | 0.51/s across the machine | 20-100ms |
| `wezterm-pane-state.sh` | 4 per turn | 10ms |
| `cc-tint` | SessionStart | 30ms |
| the tab bar | 1/s over 59 panes | 1.2% CPU, 124MB RSS |
| `cc-roster` | every `wz` call with a name | 90ms |
| `cc-peers` | humans, and cc-fleet | 130ms |
| `cc-fleet --fresh` | the board's third frame | 220ms |
| `wz read <pane-id>` | - | 20ms |
| `wz read <name>` | the agent path | 95ms |

The human-facing surfaces were never the problem: they cache in the right places and
the Lua side repaints only on invalidation. **The agent-facing path was**, and it was
65x more expensive than it needed to be - `wz read <name>` cost 1462ms against 22ms for
the same read by pane id, because resolving a name went through `cc-peers`, which works
out a title for every session on the machine before answering.

That matters more than it looks. An agent that can check the fleet in 90ms checks it
mid-task; one that costs 1.4s a call does not bother, and then reasons from memory.

Where the 1.4s went, and what replaced it:

- **a jq per registry file.** 34 forks, 76ms. One jq over all of them is 6ms.
- **an `ls -t` over the pane map per session.** 66ms. Reverse the map once instead.
- **`$(<file)` per pane-map and state file.** A command substitution forks a subshell on
  bash 3.2, and 200 of them was 114ms. One `awk` over every file is 10ms.
- **a title per session**, which is a 256KB transcript tail, an awk and a jq each, for a
  string that changes about twice in a session's life. Memoised in
  `~/.claude/cache/titles/<sid>` as `mtime\x1fchecked_at\x1ftitle`, and reused unless
  the transcript has actually moved. An untitled memo is never reused: holding
  "untitled" for a minute is the difference between a new pane naming itself and a new
  pane looking broken.

So `cc-roster` is the cheap half - who is alive, what state, which pane, no titles - and
`cc-peers` is that plus the memoised title. `wz` resolves through `cc-roster --pane`,
which skips the hook state files too.

**`waiting` is a registry status** that Claude started writing after these readers were
built, and it means the session has stopped and wants an answer; `waitingFor` says what
("input needed"). `cc-fleet`'s rank table did not know the word, so it scored 0 - the one
session on the machine that actually wanted attention sorted below thirty idle ones and
drew in the dimmest grey. It ranks with `asking` now. Anything else that switches on a
state string has to be told about it too.

## reading another session, in tokens

The time table above is the human budget. This is the agent one, and it is paid per turn
by every session that looks at the fleet. Measured 7 Sep on two real sessions in one tab,
in characters of actual output, because that is the only part anyone can check later.

| route | chars | what it carries |
|---|---|---|
| `wz last` x2 | 472 | the last thing each said |
| `wz read --tail 20` x2 | 3,358 | the bottom of each screen |
| `wz read` x2, whole screens | 8,923 | two screens, whatever was on them |
| `cc-handover a b`, merged | 4,583 | prompt, queued, replies, branch, files, transcript |

Two things fall out of that, and neither is what you would guess.

**The brief is cheaper than the screens and carries more.** Half the tokens of two full
`wz read`s, and the screens have already scrolled past the prompt that started the work,
the branch and the file list. An agent asked to pick up someone else's work reaches for
`wz read` because the ask sounds like "read that pane", and pays double for less.

**Prose tokenises better than a terminal.** The brief had 11 non-ASCII bytes in 4,583; one
pane's screen had 590 in 5,009, all of it box drawing and ANSI. So chars/4 is about right
for a brief and optimistic for a screen, which widens the gap again.

The brief is also purely additive: 1,043 characters for one session and 3,576 for the
other, 4,583 merged. Size tracks how much the session had to hand over, not the tool, so
there is no per-target overhead to weigh when handing over three at once.

Method, if it needs redoing: run the command with its output redirected to a file and
`wc -c` that, rather than letting it into the context you are trying to measure.
