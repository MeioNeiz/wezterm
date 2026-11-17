#!/bin/bash
# Hook: a session on hold (cc-note hold), or idle with a cold prompt cache, is woken by
# Jacob and nobody else.
#
#   tool    PreToolUse, SendMessage and Bash: refuses a message to a held or cold session,
#           and Claude clearing a hold. Jacob clears one with !, which runs no hook
#   prompt  UserPromptSubmit: Jacob typing into a held session lifts its hold
#
# Exit 2 refuses the tool, stderr its reason. Anything else lets it through: a hook that
# breaks must never stop a session talking.

payload=$(cat)

readonly NOTES="$HOME/.claude/fleet/notes.tsv"
readonly HOLDDIR="$HOME/.claude/fleet/hold"
readonly CTX_DIR="$HOME/.claude/cache/context"
# Assumed when the context record has no expiry. Must match wz, wezterm.lua, cc-board
readonly CACHE_TTL=3600
readonly UUID='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# Space-separated with a space each end, for a plain *" $sid "* test.
HELD=" "
held_sids() {
	[[ -r $NOTES ]] || return 1
	local sid flags
	# sid, at and flags are never empty ("-" placeholders), so tab IFS folds nothing here
	while IFS=$'\t' read -r sid _ flags _; do
		case ",$flags," in *,hold,*) HELD="$HELD$sid " ;; esac
	done <"$NOTES"
	[[ $HELD != " " ]]
}

refuse_held() {
	local name=$1 sid=$2 why=""
	[[ -r $HOLDDIR/$sid ]] && IFS= read -r why <"$HOLDDIR/$sid"
	echo "$name is on hold (${why:-no reason given}): only Jacob wakes it. Ask him." >&2
	exit 2
}

# wz refuse_cold's rule: idle or errored, past expires_at, else statusUpdatedAt + 1h
cold() {
	local sid=$1 status=$2 seen=$3 exp=""
	case $status in idle | errored) ;; *) return 1 ;; esac
	# No field is ever empty in that file, so tab IFS is safe here
	[[ -r $CTX_DIR/$sid ]] && IFS=$'\t' read -r _ _ _ exp _ <"$CTX_DIR/$sid"
	[[ -n $NOW ]] || NOW=$(date +%s)
	if [[ $exp =~ ^[0-9]+$ ]]; then
		((NOW >= exp))
	elif [[ $seen =~ ^[0-9]+$ ]] && ((seen > 0)); then
		((NOW >= seen / 1000 + CACHE_TTL))
	else
		return 1
	fi
}

# Every send pays one jq over the registry (about 10 ms). cc-roster, the resolver of record
# at 60 to 120 ms, runs only once a session the target could name is held or looks cold
send() {
	local to want rows sid name status seen pid cur suspect="" out rc current=0 held_current=""
	NOW=""
	to=$(printf '%s' "$payload" | jq -r '.tool_input.to // empty' 2>/dev/null)
	# "name [ref]": the ref is Claude's own and maps to nothing here; the name does
	to=${to% \[*\]}
	case $to in "" | main | parent) exit 0 ;; esac

	if [[ $to == uds:* ]]; then
		pid=${to##*/}
		pid=${pid%.sock}
		[[ $pid =~ ^[0-9]+$ ]] || exit 0
		set -- "$HOME/.claude/sessions/$pid.json"
		want=""
	else
		set -- "$HOME"/.claude/sessions/*.json
		want=$(printf '%s' "$to" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' \
			-e 's/[[:space:]]*$//' -e 's/[[:space:]][[:space:]]*/-/g')
	fi
	rows=$(jq -r --arg w "$want" '
		def key: (. // "") | ascii_downcase
			| sub("^\\s+"; "") | sub("\\s+$"; "") | gsub("\\s+"; "-");
		select(.sessionId and .pid)
		| select($w == "" or (.name | key) == $w
			or any((.formerNames // [])[]; (.name | key) == $w))
		| [.sessionId, (.status // "?"), ((.statusUpdatedAt // .updatedAt // 0) | tostring),
		   (.pid | tostring), (if $w == "" or (.name | key) == $w then "1" else "" end),
		   .name] | join("\u001f")' "$@" 2>/dev/null)
	[[ -n $rows ]] || exit 0
	while IFS=$'\x1f' read -r sid status seen pid cur name; do
		kill -0 "$pid" 2>/dev/null || continue
		if [[ -n $cur ]]; then
			current=$((current + 1))
			[[ $HELD == *" $sid "* ]] && held_current="$sid"$'\x1f'"$name"
		fi
		if [[ $HELD == *" $sid "* ]] || cold "$sid" "$status" "$seen"; then
			suspect=$sid
		fi
	done <<<"$rows"
	[[ -n $suspect ]] || exit 0
	# One live session wears the name and it is held: nothing for cc-roster to settle
	if ((current == 1)) && [[ -n $held_current ]]; then
		name=${held_current#*$'\x1f'}
		[[ $to == uds:* ]] || name=$to
		refuse_held "${name:-$to}" "${held_current%%$'\x1f'*}"
	fi

	# The row, with the hook state merged in: parked reads busy, a dead turn errored
	out=$("$HOME/.claude/bin/cc-roster" --row "${want:-$suspect}" 2>&1)
	rc=$?
	if ((rc == 1)) && [[ $out == *"live sessions"* ]]; then
		# A shared name, and SendMessage takes the first listed: refuse only for a hold
		[[ $HELD == *" $suspect "* ]] &&
			refuse_held "$to (a name more than one live session wears)" "$suspect"
		exit 0
	fi
	((rc == 1)) && [[ -z $out ]] && exit 0
	if ((rc != 0)); then
		echo "cc-hold: cc-roster failed (exit $rc) resolving \"$to\"; let it through" >&2
		exit 0
	fi
	# a former name adds an "is now" line on stderr; the row is the last line
	IFS=$'\x1f' read -r sid name status _ _ _ _ seen _ <<<"$(printf '%s' "${out##*$'\n'}" |
		tr '\t' '\037')"
	[[ $sid =~ $UUID ]] || {
		echo "cc-hold: cc-roster gave no row for \"$to\"; let it through" >&2
		exit 0
	}
	[[ $HELD == *" $sid "* ]] && refuse_held "$name" "$sid"
	if cold "$sid" "$status" "$seen"; then
		echo "$name is $status and cold: waking it re-reads its whole context." \
			"Hand it over: cc-handover $name --new. Never ask Jacob to wake it (he never will)." >&2
		exit 2
	fi
	exit 0
}

# Only Jacob lifts a hold. Claude may set one, on itself or another. Matched where a
# command starts (line, ; & | ( or $( before it, a path allowed), so prose about it in a
# heredoc or a comment passes
bash_cmd() {
	local cmd re
	re='(^|[;&|(]|\$\()[[:space:]]*([^[:space:];&|()]*/)?'
	re+='cc-note["'\'']?[[:space:]]+hold[[:space:]][^;&|]*--clear'
	cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
	cmd=${cmd//$'\n'/;}
	[[ $cmd =~ $re ]] || exit 0
	echo "Only Jacob clears a hold: ask him. He runs it himself with the ! prefix," \
		"e.g. ! cc-note hold --clear --for <name>. (Only writing about it? Use Edit.)" >&2
	exit 2
}

# A cross-session message, a task notice or a teammate also arrives as a prompt; only
# what Jacob types counts
prompt() {
	local sid p
	held_sids || exit 0
	sid=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
	[[ -n $sid && $HELD == *" $sid "* ]] || exit 0
	p=$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null)
	p=${p#"${p%%[![:space:]]*}"}
	case $p in
	"<cross-session-message"* | "<task-notification"* | "<teammate-message"* | \
		"[Cross-session"* | "Another Claude session sent"*) exit 0 ;;
	esac
	"$HOME/.claude/bin/cc-note" hold --clear --for "$sid" </dev/null >/dev/null 2>&1
	exit 0
}

case ${1:-} in
tool)
	# Every Bash call comes through here, so no jq until one could matter. tool_name sits
	# before tool_input in the payload, so the first match is the real one
	[[ $payload =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([A-Za-z]+)\" ]] || exit 0
	case ${BASH_REMATCH[1]} in
	SendMessage) held_sids; send ;;
	Bash) [[ $payload == *cc-note*hold*--clear* ]] && bash_cmd ;;
	esac
	;;
prompt) prompt ;;
esac
exit 0
