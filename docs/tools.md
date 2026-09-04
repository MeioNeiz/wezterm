# The tools: wz, cc-note, cc-handover, cc-spawn

Pointed at from CLAUDE.md.

## wz

The cc-* scripts answer "which chats want me". `wz` answers "what is in that pane, and make
it do something", which is the half a Claude session needs and could only get before by
composing four `wezterm cli` calls and getting the quoting right.

Nothing in it is a new capability. `wezterm cli` could always do this; what it could not do
was make it cheap enough to reach for mid-task. The parts worth knowing:

- **`grep` and `top` are the two that did not exist in any form.** `wezterm cli list`
  reports no pid, so per-pane CPU comes from joining `tty_name` against one `ps -ax` for the
  whole machine. A `ps -t` per pane would cost more than everything else here put together.
- **Targets resolve through `cc-roster`**, so `wz read d5-lca-48` takes the same address
  SendMessage does. `resolve` asserts the answer is digits before returning: a pane id
  reaches `kill-pane` and once reached an `rm`, and nothing downstream should have to wonder.
  It used to go through cc-peers and cost 1.4s a call; see "what it costs".
- **The event log is polled, not pushed.** wezterm has no outbound event stream, and the
  states worth waking up for (busy, asking, idle) are Claude's rather than wezterm's, so
  they would not appear in one if it existed. `wz events --daemon` diffs a five-field
  snapshot every two seconds. `--cursor-file` makes a reader resumable.
- **`wait --state` deliberately does not use that log.** It polls cc-peers, so it works with
  no daemon running, and cc-peers is what knows "asking" from "idle" in the first place.
- **`pipe` line-diffs a screen**, so it only reads cleanly for output that scrolls. A
  full-screen TUI repaints in place and its "new" lines are whatever the redraw touched.
  Fine for a shell or a log, useless pointed at another Claude pane.

Not built, and why: there is no `swap-pane` or `respawn-pane` because wezterm has no
primitive for either. There is no status/notes store because nothing would render it; that
wants a statusline change in this file, and it should wait until the tab bar work lands.

Truncation happens in bash, never in awk. See the awk rule below: `substr` cuts a multibyte
glyph in half and every tab title starts with one.

## the writable layer

Everything else here is derived: the registry is Claude's, the hook files are Claude's,
the transcript is Claude's. None of them can hold "waiting on the DNS change", "step 3 of
7" or "leave this one alone", which is what `cc-note` is for.

Keyed by session id rather than by pane, so a note follows the conversation through a
pane move, a `--resume` and a reboot - and `/clear` mints a new id, which is exactly when
a note should stop applying. `CLAUDE_CODE_SESSION_ID` is set in every session's shell, so
a session annotating itself costs no lookup at all.

It renders in three places and deliberately not in a fourth:

- **the statusLine**, straight after the title, because the far end of the line is where
  a narrow pane truncates and a note the session left for itself outranks the branch it
  is on. Read with a bash loop rather than a grep - this path stays fork-free.
- **cc-fleet**, where a status note takes the topic column: it is newer than the topic
  Claude derived and it says what is actually holding the work up. Read at render time
  rather than folded into `assemble_rows`, because that result is cached for eight
  seconds and a note is the one field you change and expect to see immediately.
- **the window status bar**, where `mute` means a session stops counting towards the
  "wants you elsewhere" marker. That marker exists to catch a blocked pane in a workspace
  you are not looking at; one you have already decided to leave is noise in the place
  noise is most expensive.
- **not the tab bar.** Four false starts up there are documented above and every one of
  them was adding a channel. Progress and status have somewhere better to live.

## handing work over

`cc-handover` is the one that earns its place daily. The manual version is scrolling back
and copying the last message into a fresh pane, which loses what was actually asked, what
was said mid-turn, the branch, the files it had open, and everything the session recorded
for itself. All of that is already on disk.

Two things that are not obvious and cost a while to find:

- **a session spawned from inside another inherits its whole Claude environment**, and
  `CLAUDE_CODE_CHILD_SESSION` turns transcript saving off. The child then has no
  transcript, so it never gets a title, `cc-peers` cannot name it, its statusLine has
  nothing to show, and it can never be handed over itself - which is the one thing the
  script exists to prevent. It announces itself as one line of warning in a pane nobody
  is watching. `cc-spawn` clears the environment, and is why every launcher goes through
  it rather than calling `wezterm cli spawn -- claude` directly.
- **a message typed while a turn is running is a `queue-operation` record**, not a user
  turn, so every "last prompt" reader is blind to it. It is usually the steer that
  changed what the work was. The brief carries everything queued since the last real
  prompt, in order.

Also: the `last-prompt` record beside the transcript is Claude's own UI copy and arrives
already truncated with an ellipsis, so the brief greps the whole file for the last real
user turn instead. One grep over a 1.4MB transcript is 13ms; the tail is no good here
because a long turn pushes the prompt that started it well past 400KB back.

`wezterm cli spawn -- <argv>` passes arguments straight to exec with no shell in between,
so a multi-KB markdown brief with newlines, backticks and quotes in it arrives
byte-identical. Checked, because the obvious assumption is that it would not.
