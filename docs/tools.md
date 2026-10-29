# The tools: wz, cc-note, cc-handover, cc-spawn, cc-account, and Kev's three

Pointed at from CLAUDE.md and docs/INDEX.md.

## addresses, and why a name is not one

Two strings look like a session's identity and only one of them is.

**The name** (`d5-lca-77`) is the registry's `name` and the address SendMessage takes.
Claude derives it at launch as `<cwd basename>-<two hex of sha256(session id)>` and
records where it came from in `nameSource`. **The title** ("AI Live Call Answering
billing setup") is the `ai-title` Claude writes into the transcript and rewrites as the
conversation moves; it is what the tab bar, `cc-peers` and `cc-board` show. A session
that suddenly reads as something sensible has gained a title, not a new address.

The name does move, though, in four ways, and `nameSource` says which:

| `nameSource` | when |
|---|---|
| `derived` | at launch, and again whenever the process adopts a conversation |
| `collision` | two live sessions want one name; the loser takes a new suffix |
| `auto` | background and forked sessions, named after the task they were given |
| `user` / `hook` | `/rename`, or `--name` at launch |

The collision check does not always run (it sits behind `tengu_session_name_uniqueness`):
on 2026-10-01 `7c8722c7` and `e90da9f8`, both `derived`, were live as `d5-lca-90` at once
(two hex is 256 names a directory, and d5-lca holds twenty sessions), and on 2026-10-29 a
fresh meiolol session came up as W4's `meiolol-57`. So cc-spawn names a fresh session
itself, `<folder>-<2 hex>` that no live session holds (3 hex if it finds none free), which
also makes it `user` and sticky; a resume, fork or worktree keeps Claude's. cc-roster refuses a name two live sessions share, saying which
panes, and `cc-fleet --brief` prints `same name, <name> is panes <a> <b>: /rename one`.

Adoption means a resume, a remote attach or a spare claim, and the binary is explicit
that `/clear`, a fork and a `cd` are not on that list: those keep the name. `auto` is how
`743537e5` came to be called `bash command execution`. A `user` name is the only one that
is sticky - nothing re-derives it.

So the addresses that move under you are the ones nobody chose. Claude covers this with
`formerNames` in the registry - up to three per session, each held for ten seconds or
more - and its own resolver falls back to them. Everything here resolves through
`cc-roster`, which now does the same, on the same terms:

- **Claude's key, not ours**: trimmed, lowercased, runs of whitespace folded to hyphens.
  That is why `bash-command-execution` reaches a session called "bash command execution",
  which matters because half of these tools are driven from a shell where the spaces
  would need quoting anyway.
- **and it is the key that gets shown**, not the name as the registry spells it.
  `cc-roster` folds it once, in the jq, so cc-peers, cc-fleet, cc-board, the wezterm
  pickers and the tab bar all inherit an address with no spaces in it; `statusline.sh`
  and `cc-colour` read the registry themselves and fold the same way. Only the *title*
  column still reads like a sentence, which is what a title is for. There is nowhere
  left that shows you a name you cannot type.
- **only former names from the conversation the session is still in**, which is the cut
  Claude's resolver makes too. A rename inside one conversation keeps its old address. A
  resume does not, and should not: that name belonged to the empty session the pane
  started with, not to the work that arrived afterwards.
- **a current name always beats a former one**, and a former name two live sessions both
  used to have resolves to neither. There is no right answer there and picking one
  silently is how you brief the wrong pane.
- **it says so**: `cc-roster: "743537e5" is now "bash command execution"` on stderr, once,
  when a lookup lands through an alias. Callers no longer swallow cc-roster's stderr.

What never moves is the session id, which is why `cc-note` is keyed by it and why
`cc-handover` carries it. If you want an address you can write down for a week,
`/rename` the session: that makes it `user` and nothing re-derives it.

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
  SendMessage does - including one the session has since been renamed away from. `resolve`
  asserts the answer is digits before returning: a pane id reaches `kill-pane` and once
  reached an `rm`, and nothing downstream should have to wonder. It used to go through
  cc-peers and cost 1.4s a call; see "what it costs".
- **`go` across workspaces pokes the GUI.** The action file is the channel; after writing
  it `wz` sets a `wz_poke` user var on the focused pane's tty, and wezterm.lua drains the
  queue at once instead of on its next 0.1s tick. Only a pane on screen fires that event
  (`dead-ends.md`), which the focused one always is; lost or not, the file still runs once.
  The client is the one with the least `idle_time`, if a second is ever attached.
- **The event log is polled, not pushed.** wezterm has no outbound event stream, and the
  states worth waking up for (busy, asking, idle) are Claude's rather than wezterm's, so
  they would not appear in one if it existed. `wz events --daemon` diffs a five-field
  snapshot every two seconds. `--cursor-file` makes a reader resumable.
- **`wait --state` deliberately does not use that log.** It polls cc-peers, so it works with
  no daemon running, and cc-peers is what knows "asking" from "idle" in the first place.
- **`pipe` line-diffs a screen**, so it only reads cleanly for output that scrolls. A
  full-screen TUI repaints in place and its "new" lines are whatever the redraw touched.
  Fine for a shell or a log, useless pointed at another Claude pane.

### notify, and cc-toast

`wz notify` is the one way anything here reaches you off screen: the stop-asks and drift
hooks, cc-watch and wezterm.lua all go through it. On macOS it raises **cc-toast**, a
panel of its own at the top right of the WezTerm window, for `--for` seconds (20 by
default) or until you are on its pane: a Notification Centre banner leaves
after about five whatever it is told, and there is no API that changes that. Its own
corner because native banners draw into one full-screen window, so there is no stacking
below them. Toasts stack in LEADER+t's order (below), so the top toast is where LEADER+t
goes and pressing it again walks down the stack; one that matters more pushes in above and
the rest glide down. Hovering holds the countdown, the countdown holds while another app is
in front, and one closes itself once you are on its pane. The countdown also holds once nothing has been touched for 60s (walked away, locked, display asleep;
`CC_TOAST_AWAY` overrides the 60), and on your return the toast gets at least 8s more.
A click with `--pane` runs `wz go <pane>` and brings WezTerm forward. It plays the sound
unless `--quiet`.

A toast with `--pane` wears that session's identity hue (cc-colour, resolved by wz): a
gradient over the glass, a 3pt bar down the left and the title in the hue, so it reads as
the pane it came from. **`--sticky`** has no countdown and is marked by a small dot in the
hue; it closes only when you are on its pane, click it, or press x. **`--compact`** is a
one-line pill, title then body, that opens into the full toast on hover. stop-asks makes
every toast sticky, except a reply Kev ranks below 0.4 that is not blocked: that one is a
pill for 8 + 40 x rank seconds. Kev down, it stays. Arrivals spring in, a toast ranked 0.5
or more shimmers once, and a sticky one at 0.6 or more breathes (dot and edge). The stack
holds five: past that the last in the order goes, non-sticky first (still in `wz toasts`),
and a toast whose pane has closed dismisses itself within about 10s.

Every notify is logged to `~/.claude/cache/notify-log` with its pane, session, `--rank`
and body, so the toasts can be followed after they have gone: `wz toasts [<target>] [-n
N]` lists them with the time and whether you have been on the pane since. A stop on the
pane you are looking at raises no toast, so it is not there either. stop-asks' body is the
reply's labelled caveat ("One thing to know:", "Not tested yet:") if it has one, else its
first sentence of six words or more; the toast shows about 90 characters of it.
**LEADER+t** is Kev's pick, and the one ranking for the toast stack too: each pane scores
from what is on disk, with no Kev call: `cc-note needs` 1.1 whatever the state, never
aged or discounted, registry or not (the status bar's "needs you"), asking 1.0, errored 0.8, Kev's blocked verdict
0.55 + 0.4p, otherwise finished at 0.3 if unread or 0.05 if read, plus 0.4 times Kev's
rank of the reply. An unseen toast (three hours back) lifts its pane to the toast's rank if
that is higher, so a push or a usage limit counts, and a working pane with one is in. A
day halves a score and a cold cache takes 15% off; ties go to the newer. Pressed again
within 8s it walks down the same list, and the right status says `t 2/9 <name>: <why>` for
4s. wezterm.lua writes the list to `~/.claude/cache/kev-pick` every 2s while toasts are up
and on a `pick` action, which each new toast queues and waits 0.25s on so it lands in its
place; cc-toast falls back to `--rank` for a pane not listed or a file 10s stale. **LEADER+T** goes to the newest toast, and pressed again
within 8s to the one before it, pane by pane. cc-toast is Swift, built by setup.sh from
`toast/cc-toast.swift` into the gitignored `bin/cc-toast`; without it notify falls back to
osascript (Script Editor's banner), and on Linux to notify-send.

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
- **a bare word in a cc-spawn argument list ends the options.** Its parser breaks on the
  first non-flag so that a prompt needs no `--`, which means anything after that word is
  prompt. cc-handover held `--tab` and `--window` as the bare words `tab` and `window` and
  passed them straight through, so with either of those `--dry-run` became part of the
  prompt and a run that promised to spawn nothing spawned a session and set it working.
  The default `--right` is a flag and was always fine, which is how it survived. Fixed by
  translating at the call site; worth knowing before adding the next positional.
- **`--worktree` is a pass-through, not plumbing.** Claude Code grew native worktrees, so
  this is one flag rather than the branch-and-checkout dance every third-party
  orchestrator hand-rolls: it makes `<repo>/.claude/worktrees/<name>`, holds a
  `git worktree lock` for the life of the session, sweeps locks left by sessions that were
  killed but never one you set yourself, and marks its own worktrees in git metadata so
  the sweep can tell them from yours. `.worktreeinclude` carries the gitignored files a
  build needs. The only thing added here is the repo check, which happens before the pane
  opens: claude refuses `--worktree` outside a repo and says so in a pane that has just
  scrolled and is not being read.
- **a split never leaves a Claude pane under a third of the tab's width.** Left to
  sessions, they kept splitting a half-width pane into quarters. A `--right`/`--left` split
  of a pane narrower than two thirds of its tab (`wezterm cli list`: the pane's `cols`
  against the tab's widest `left_col + cols`) becomes a new tab, with a line on stderr;
  on one screen's window that is two across. `--squeeze` overrides; `--shell` and
  `--replace` (closed again at once) are exempt.
- **every spawned session starts with `--dangerously-skip-permissions`**, which is how
  every agent here is run. A pane that stopped to ask does show as `asking` on the board,
  so it is not invisible, it is just wall clock nobody is spending. `--ask` opts one out.
- **cc-spawn picks the session id** (`uuidgen`, passed as `--session-id`), so it is known
  before the session starts; `--print-sid` prints it after the pane id. cc-handover
  `--new` uses it to watch the receiver by session rather than by a pane id that can be
  reused. The restore strips `--session-id`, `--fork-session` and everything from `--`
  (the prompt) before adding `--resume`: kept, a resume replayed the original brief as
  its next turn, and a cold restore's fresh brief lost to the stale first positional.
- **`--fork` copies a warm session**: `cc-handover <T> --fork` runs `claude --resume <sid>
  --fork-session` in a new pane, the whole conversation at cache-read price, source
  untouched, no brief, nothing closed. Refused when cold, where it would re-read the whole
  context and `--new` is cheaper. Bypass is passed again, since a resume never restores it.
- **a message typed while a turn is running is a `queue-operation` record**, not a user
  turn, so every "last prompt" reader is blind to it. It is usually the steer that
  changed what the work was. The brief carries everything queued since the last real
  prompt, in order.

- **a cold session is never woken or resumed.** A resume, a paste or a message re-reads
  its whole context; a fresh session reading the transcript costs a brief. So the brief
  carries a `claude --resume` line only while the source's prompt cache is warm, and says
  instead what a resume would re-read when it is cold; `--to` refuses an idle target whose
  cache is cold, before writing anything, and points at `--new`. Cache state is the
  statusLine's `prompt_cache` expiry and recache price, from `cache/context/<sid>`;
  without them the last reply plus an hour and `used_pct x window`. It also goes to stderr
  per source. Sessions do not talk to each other to hand over: the successor gets the
  transcript, the output files its background tasks wrote (`<tmp>/tasks/<id>.output`,
  from its tool results) and its pane's last 200 lines, saved beside the brief at the
  handover, since `--new` and a gather close the pane and its id gets reused. Only when
  this run leaves the pane open does the brief add `wz read <name> -n 200`, by name.

Also: the `last-prompt` record beside the transcript is Claude's own UI copy and arrives
already truncated with an ellipsis, so the brief greps the whole file for the last real
user turn instead. One grep over a 1.4MB transcript is 13ms; the tail is no good here
because a long turn pushes the prompt that started it well past 400KB back.

`wezterm cli spawn -- <argv>` passes arguments straight to exec with no shell in between,
so a multi-KB markdown brief with newlines, backticks and quotes in it arrives
byte-identical. Checked, because the obvious assumption is that it would not.

### gathering a tab: LEADER+G and ccx

LEADER+G hands every session on the tab, this one included, into a fresh session beside
this pane, with no picker: `cc-handover <here> .tab --new --right`. Gathering into a
session already open is still there by hand, `cc-handover .tab --to <pane>` (warm only). Any `.tab` or multi-source handover is a gather: cc-handover sends the brief (a
plain `--to` only pastes it), records the sources in `fleet/gathered/<receiver>`, and once
the receiver is busy on the brief types `!ccx` into its prompt, unsent, with
`send-text --no-paste` so the `!` switches it to bash mode as a typed key does. A fresh
session is polled every 0.5s for up to a minute first: keys typed before its prompt is up
are lost.

A plain `--new` of one session records its source the same way but types nothing: once
the new session is busy on the brief, a detached loop runs `ccx` as the new pane every 2s
until the source is closed, for up to 30 min. A self-handover is mid-turn until it has
reported, so it goes a few seconds after. Past 30 min it stays, and `!ccx` typed in the
new session still closes it. A plain `--to` closes nothing (it pastes, unsent).

The new session starts as `<name>-next` and takes the name only once its source has gone:
ccx types `/rename <name>` into it as the list empties. Handing the name over at once left
two live sessions sharing it for as long as a background task kept the source open, and
when that task finished it woke the source, so messages reached either (meiolol-b2,
2026-10-29). Typed while busy, `/rename` is queued and applied when the turn ends, without
a turn of its own.

Enter on it runs **ccx**, which closes each source whose pane still holds the same session
and is not busy, asking or waiting, and keeps the rest listed for a later `ccx`. One whose
turn is over but a background task still runs (`shell`) never stops by itself when the
task is a dev server or a watcher (meiolol-c1, 2026-10-29), so ccx closes it at once when
every task has a listening TCP port somewhere under it, and otherwise 15 min after the
handover, so a push in flight gets to land. It stops those tasks too: a pane's death does
not reach them, and they outlive claude as orphans holding memory (7 GB of them on
2026-10-29). `ccx --tasks <claude pid>` lists them, and the brief carries that list so
the successor knows what to restart. A source closed by hand still hands over its name,
but its tasks are left running. It never closes the receiver. Claude answers a bash-mode
command with a turn of its own, so ccx's one line says what it did and that nothing else
is needed: without that the session guessed at why a source was kept, wrongly.

## Kev's three: cc-sort, cc-watch, cc-handovers

Local Kev (kev-mcp) answers yes/no and choice questions in under a second for no Claude
tokens. Three scripts here lean on it, and all three degrade to doing less, never to
guessing, when it is down.

**cc-sort** groups Claude panes by topic: one Kev "same project and topic?" per pair of
sessions in a workspace (name, title, folder), a pane moving beside its best partner when
p >= 0.7 and beats staying put by 0.15. Dry run by default, `--apply` joins. `--rank <pane>`
is LEADER+H's tab ordering, cache plus whatever Kev answers inside a second. Pairs are
cached a day in `~/.cache/kev/cc-sort-pairs.json`, merged under a lock so a `--warm` and a
`--rank` running together keep both. A description carries no last request: that changes
every prompt and no cached pair would survive one. Good at "wrong project" (AUROC 0.99),
weak at splitting one project into topics (0.57), so it never breaks a tab up.

**cc-watch** polls background shell panes every 10s and asks Kev whether new output
matters (a run ended, failed, a server came up, it wants input); p >= 0.45 toasts. **It is
off**, and stays off until the repaint fix has been watched for a while: its first version
read any in-place redraw as forty new lines, and 1953 of its 1968 asks were nvim's clock.
Now new lines are only what follows the last look's tail, read 200 lines into scrollback so
a fast scroll still overlaps; an in-place change to the last two lines is not news; a
screen with no anchor at all is a repaint or a clear and is rebased silently; and panes
running a full-screen program are skipped. While Kev is down the baseline moves, so its
return is not a flood. `cc-watch start | stop | status`, `test` for the examples.

**cc-handovers** is the daily digest: every brief in `~/.claude/fleet/handover` for a day,
who took it up (pasted, `--new`/`--to`, SendMessage, or fetched), how many prompts you sent
it after, and Kev's verdict on the successor's last stop. Written at 08:30 by launchd
(`cc-handovers --install`, setup.sh runs it) to `~/.claude/fleet/handover-days/`, which
/weekly-review in the vault reads; `HANDOVER_DAYS` overrides. Without a kev-mcp checkout it
still runs, with no verdicts. Linux has no launchd: `--install` prints the cron line.

## accounts: cc-account

Two claude.ai logins at once, one per config folder. Claude Code keeps its login per
`CLAUDE_CONFIG_DIR`: `~/.claude.json` and keychain item `Claude Code-credentials` for the
default, `<dir>/.claude.json` and `Claude Code-credentials-<hash of dir>` otherwise. So a
`/login` moves every session **in its folder** and none in another. `~/.claude` is the
default account; every other account's folder (`~/.claude-personal`) holds links back into
it for everything but the login (`cc-account link`, which setup.sh runs; the `own()` list
says what stays apart), so all sessions share settings, hooks, skills, `projects/`, the
registry and every state file, and nothing in the fleet has to know there are two.

The map is `~/.claude/accounts`, out of the repo: `<name> <folder> <email> <dirs>...`, `*`
for the default. The account is fixed when a session starts:

- the zsh `claude` function asks `cc-account env --cwd $PWD`; `claude --<name>` overrides
- `cc-spawn` always sets it, from `--account` or `--cwd`, since a spawned session would
  otherwise inherit its parent's folder. cc-handover passes `--account` through
- `~/.claude` is reached by **unsetting** `CLAUDE_CONFIG_DIR`, never by setting it to
  `~/.claude`: that is a third login (`~/.claude/.claude.json`, a hashed keychain item)
- `cc-account login <name>` signs a folder in from a plain shell (`! cc-account login
  personal`); `cc-account status` says who is signed in where

**Moving a running session**: `cc-account switch [T] [--to <name>]` queues it in
`fleet/switch/<sid>`, and once its turn has ended with nothing but servers left in its
background, `cc-spawn --replace <pane> --resume <sid>`: a pane split from the old one whose
command waits for the old claude to exit, the old pane killed, the conversation resumed in
place under the other login with the same session id (and its `--effort`; the name is
re-derived). Another account means no prompt cache, so the first reply re-reads the whole
context; refused when cold, as every resume is, unless `--force`. For a big session
`cc-handover --new --account <name>` is cheaper, and a handover of a session with a switch
queued starts the successor on that account.

It waits as long as that takes. It used to give up silently after 10 min, and on
2026-10-29 every one of ten meiolol switches did: team sessions stay busy, or sit in
`shell` on a build, for longer. A resume kills the session's background tasks, so a test
or push in flight is waited out; servers are not, and the resumed session is told which
it lost (`--then` prompts arrive the same way). One detached watcher (`switch --watch`,
a mkdir lock) polls cc-roster every 5s for all of them, since a waiter each cost 0.4s
apiece every 2s. A switch is dropped, with a sticky toast, only at its `--until`, by
default the end of the override lending the session's folder to that account; a failed
resume toasts too; a session that has gone takes its switch with it. `switch --pending`
lists them (and restarts the watcher after a reboot), `switch <T> --cancel` drops one.

**Lending a folder for a while**: `cc-account use work ~/personal/meiolol --until 18:00`
(or `+2h`) writes `~/.claude/account-overrides`; `acct_for` prefers a live override to the
map, so the zsh `claude` and cc-spawn pick it up, and it lapses on its own when read after
its time, with no job left running. Running sessions keep their account. `use` lists them,
`use --end [dir]` ends one.

**Caps**: `~/.claude/account-limits`, `<name|*> <folder|*> <5h|7d> <stop> [warn]`, every
matching line applying. A stop of `11,23,47,65,90` is a cap per calendar day of the window,
counted from the day it started (the weekly one resets Monday 10:00, so Monday morning is
still the last week's last day). `hooks/cc-limits.sh` runs on UserPromptSubmit and every
PreToolUse: under the cap it prints nothing (no tokens, ~11ms); at warn it toasts once a
window; at stop it blocks the prompt or denies the tool call, toasts sticky, and ends an
override lending the folder to that account. Usage is the statusLine's cache, so it lags by
at most one response. `cc-account limits [dir]` shows where each account stands, and `use`
refuses to lend a folder already over its cap.

**Fallback**: `<name|*> <folder|*> fallback <account>`. At a cap there the hook moves the
session rather than stopping it: `cc-account switch --force --then`, resumed in place once
its turn ends. A refused prompt is resent on the new account as the `--then`, and a turn cut
off at a tool call gets "carry on". Only to an account below its own caps, so a session
never bounces between two; one move per session (`cache/limits/moving-<sid>`, 15 min); a
switch that fails stops it as before. Jacob's rule (2026-10-29) is `work * fallback
personal`: work can always move to personal, personal stops at its caps and never takes
work.

The statusLine names the account once there are two, as a peach badge when it is not the
folder's own (`personal, not work`, or `work till 18:00` under an override, with the
folder's nearest cap `week 19/23%`), red with `STOPPED` at a cap. Rate limits are per account: `cache/rate-limits` for `~/.claude`'s,
`rate-limits-<name>` for the others; the right status shows each, prefixed by name.

## cc-privacy: the privacy dot, without the noise

macOS cannot be told to skip an app for the dot by Control Centre, and AltTab and DockDoor
light it about once a second for their window previews. cc-privacy streams Control
Centre's `sensor-indicators` log and raises a toast when any app outside `IGNORE` (AltTab,
DockDoor, WezTerm, by bundle id) starts screen recording, the mic or the camera (60s), or
location (a quiet pill). Each change in what else is on goes to
`~/.claude/cache/privacy-dots`, `time<TAB>kind app, ...`, empty when nothing: macOS keeps
these log entries for under a day. `cc-privacy` shows the last 30, `-n N` more. launchd
keeps `cc-privacy watch` running from login (`--install`, setup.sh runs it); errors to
`~/.claude/cache/cc-privacy.err`.

## cc-doctor: drift between copies, and new values in Claude Code

Most bugs the October survey found were one fact kept in several places that had drifted
apart. `cc-doctor` checks those places and prints a line per check, `ok`, `warn` or `FAIL`
with file:line, and exits 1 on any FAIL (`--quiet`: only what is not ok; about 0.2s):
both links for every bin/ script, plus hooks, wezterm.lua, statusline.sh and the skill;
cc-toast built from its current source; settings.json running every command setup.sh
registers, with its Notification matcher (read from setup.sh's `$want` at run time, so
the list lives in one place); `PARKED_MAX`, `PARKED_MONITOR_MAX` and `CACHE_TTL` equal in
every reader (cc-fleet's own `CACHE_TTL` is its row cache; its `PROMPT_CACHE_TTL` is
compared); every `wezterm cli` call passing `--no-auto-start`; wezterm.lua loading; the
survey in `research/sources.md` behind the running Claude Code (warn only, never a fail);
and the running version's new values acknowledged.

**The version watch** is the survey's most useful trick made routine: `strings` of a new
binary, diffed against the last, finds values the changelog never mentions. `cc-doctor
--enums` reads seven sets: hook events, `notification_type`, StopFailure error kinds,
statusLine top-level keys (literal ones only; the common `session_id`, `cwd` and the like
come through a helper and are not seen), registry `status`, `waitingFor`, and Stop's
`background_tasks[].type` labels. Each set is found by values it holds, since minified
variable names change every build. A set that comes back empty prints as "the extraction
needs a look", not as every value removed. The hourly reap in `cc-roster --digest` runs
`--enums --notify` detached: a readlink and a stat until the version changes, then about
a second of extraction and one toast naming what moved. When the readers that switch on
those values have been told (CLAUDE.md), `cc-doctor --enums --ack` clears the FAIL.
`--diff <a> <b>` compares two binaries and writes nothing: the next survey's first step.
