#!/bin/bash
# PostToolUse: tells a session to hand over as its context fills, by tokens, not %: recall
# drops with token count whatever the window. A fresh session starts at 31-40k (system
# prompt, tools, CLAUDE.md), so SOFT leaves about 110k of work: finish the task, start no
# other. Research (agent-handover-threshold): 150-250k on 1M windows; the old 70-100k
# figures assumed 200k windows.
# FIRM, hand over now, then every 25k: Codex compacts its 1M models at about 200k. Past
# HARD every 10k: current Claude models score measurably worse past 256k.
# Tokens = used_pct x window from the statusLine's cache/context/<sid>; silent without it
# and in subagents, which can't hand over. Builtins only below SOFT: runs on every tool call.
# Attended (Jacob typed into it within ATTENDED s; arg `prompt`, UserPromptSubmit, records
# when): same levels, but hand over with --keep so the source stays open while he uses it.
# Test: hooks/cc-context-nag.sh --test
if [[ ${1:-} == --test ]]; then
	self=$0 fails=0
	HOME=$(mktemp -d)
	export HOME
	mkdir -p "$HOME/.claude/cache/context"
	typed() {
		printf '{"session_id":"s1","prompt":"%s"}' "$1" | "$self" prompt
	}
	at() {
		printf '%s\t%s\t1\n' "$1" "$2" >"$HOME/.claude/cache/context/s1"
		echo "{\"session_id\": \"s1\",\"tool_input\":{\"c\":\"\\\"session_id\\\":\\\"x\\\"\"}$3}" |
			"$self" | jq -r '.hookSpecificOutput.additionalContext // empty'
	}
	check() {
		local got
		got=$(at "$2" "$3" "${4:-}")
		[[ -z $1 && -z $got ]] || [[ -n $1 && $got == "$1"* ]] ||
			{ echo "at $2% of $3: want '$1' got '$got'"; fails=1; }
	}
	check "" 14 1000000
	check "Context at 150k (15%)." 15 1000000
	check "" 19 1000000
	check "" 21 1000000 ',"agent_id":"a1"'
	check "Context at 210k (21%):" 21 1000000
	check "" 22 1000000
	check "Context at 230k (23%):" 23 1000000
	check "Context at 250k (25%)," 25 1000000
	check "" 25 1000000
	check "Context at 260k (26%)," 26 1000000
	rm -f "$HOME/.claude/cache/context-nag/s1"
	check "" 40 200000
	check "Context at 150k (75%)." 75 200000
	rm -f "$HOME/.claude/cache/context-nag/s1"
	typed '<cross-session-message from=x>hi'
	check "Context at 150k (15%)." 15 1000000
	rm -f "$HOME/.claude/cache/context-nag/s1"
	CC_SPAWN_PROMPT=1 typed '# Handover'
	check "Context at 150k (15%). Answers get worse as context grows. Finish the task in hand but start no other in this session: at the next natural break (step committed, state in notes) hand over with the fleet skill, cc-handover --new (" 15 1000000
	rm -f "$HOME/.claude/cache/context-nag/s1"
	mkdir -p "$HOME/.claude/fleet/gathered"
	printf '9\ts1\tn\t1\n' >"$HOME/.claude/fleet/gathered/10"
	check "" 30 1000000
	rm "$HOME/.claude/fleet/gathered/10"
	CC_SPAWN_PROMPT=1 typed 'carry on'
	[[ $(at 15 1000000) == "Context at 150k"*"--new --keep"* ]] || { echo "attended: no --keep"; fails=1; }
	echo 1 >"$HOME/.claude/cache/context-nag/s1.typed"
	got=$(at 21 1000000)
	[[ $got == "Context at 210k"* && $got != *"--keep"* ]] || { echo "unattended: '$got'"; fails=1; }
	rm -rf "$HOME"
	((fails)) || echo "all pass"
	exit $fails
fi

SOFT=150 FIRM=200 HARD=250 ATTENDED=600
state=$HOME/.claude/cache/context-nag
read -r -d '' in

# A cross-session message, a task notice or a teammate also arrives as a prompt (as in
# cc-hold.sh); only what Jacob types counts
if [[ ${1:-} == prompt ]]; then
	sid=$(jq -r '.session_id // empty' <<<"$in" 2>/dev/null)
	p=$(jq -r '.prompt // empty' <<<"$in" 2>/dev/null)
	p=${p#"${p%%[![:space:]]*}"}
	case $p in
	"<cross-session-message"* | "<task-notification"* | "<teammate-message"* | \
		"[Cross-session"* | "Another Claude session sent"* | "") exit 0 ;;
	esac
	[[ -n $sid ]] || exit 0
	mkdir -p "$state" 2>/dev/null
	# cc-spawn's prompt (a handover brief, a task) comes in as the first one
	if [[ -n ${CC_SPAWN_PROMPT:-} && ! -e $state/$sid.typed ]]; then
		echo 0 >"$state/$sid.typed"
		exit 0
	fi
	date +%s >"$state/$sid.typed"
	exit 0
fi

[[ $in =~ \"session_id\":\ ?\"([^\"]+)\" ]] || exit 0
sid=${BASH_REMATCH[1]}
ctx=$HOME/.claude/cache/context/$sid
[[ -r $ctx ]] || exit 0
IFS=$'\t' read -r pct win _ <"$ctx"
[[ $pct =~ ^[0-9]+$ && $win =~ ^[0-9]+$ ]] || exit 0
k=$((pct * win / 100000))
((k >= SOFT)) || exit 0

if ((k < FIRM)); then level=$SOFT
elif ((k < HARD)); then level=$((FIRM + (k - FIRM) / 25 * 25))
else level=$((HARD + (k - HARD) / 10 * 10)); fi
last=0
[[ -r $state/$sid ]] && read -r last <"$state/$sid"
[[ $last =~ ^[0-9]+$ ]] || last=0
((last < level)) || exit 0
[[ -z $(jq -r '.agent_id // empty' <<<"$in" 2>/dev/null) ]] || exit 0
# Handed over already (a source cc-handover listed, kept open for Jacob): nagged, it hands
# over again and again
for g in "$HOME"/.claude/fleet/gathered/*; do
	[[ $g == *.name || ! -f $g ]] && continue
	cut -f2 "$g" | grep -Fxq -- "$sid" && exit 0
done
typed=0
[[ -r $state/$sid.typed ]] && read -r typed <"$state/$sid.typed"
[[ $typed =~ ^[0-9]+$ ]] || typed=0
now=$(date +%s)
attended=false
((now - typed < ATTENDED)) && attended=true
mkdir -p "$state" 2>/dev/null

at="Context at ${k}k ($pct%)"
how="cc-handover --new"
$attended && how="cc-handover --new --keep (Jacob is using this session, so it stays open \
while he uses it)"
echo "$level" >"$state/$sid"

if ((level == SOFT)); then
	msg="$at. Answers get worse as context grows. Finish the task in hand but start no other \
in this session: at the next natural break (step committed, state in notes) hand over with the fleet skill, \
$how (the successor keeps your name). Carry on past it only when a restart \
costs more than it saves, such as mid-debug with what you know not yet written down."
elif ((level < HARD)); then
	msg="$at: hand over now. Write the state to your notes, then $how \
(fleet skill). Carry on only for a concrete reason, and say it in your next reply."
else
	msg="$at, past where recall measurably degrades: stop work and hand over now. Write the \
state to your notes, then $how \
(fleet skill). Tell Jacob why if you cannot."
fi
jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
