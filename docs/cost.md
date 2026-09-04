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
