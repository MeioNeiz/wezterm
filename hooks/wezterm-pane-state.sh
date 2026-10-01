#!/bin/sh
# Hook: record what this Claude pane is doing, for the tab bar, the board and the fleet.
# Record format and the states are in CLAUDE.md.
#
# The state is argv, not the payload, so this stays independent of hook field names.
# Three events need the payload too, each the only source of what it carries:
#   notify   only the message says why Claude stopped
#   done     background_tasks tells finished from parked
#   errored  Stop does not fire when a turn dies on an API error
#
# Must stay silent (some hooks inject stdout into context) and never exit non-zero
# (exit 2 blocks several of these events).

# Drained even when unused, so Claude never writes into a closed pipe.
payload=$(cat)

[ -n "${WEZTERM_PANE:-}" ] || exit 0
state=$1
[ -n "$state" ] || exit 0

# A claude run from inside a session's Bash tool inherits WEZTERM_PANE but not a
# terminal: only the pane's own session has one. Unguarded, a nested run takes the pane,
# wiping its state and marking it ended. Hooks are detached, so the tty checked is the
# nearest claude ancestor's, one shell up at most. Permissive if ps says nothing.
resident() {
	set -- $(ps -o ppid=,tty=,comm= -p "$PPID" 2>/dev/null)
	case ${3##*/} in
	sh | bash | zsh | dash) set -- $(ps -o ppid=,tty=,comm= -p "$1" 2>/dev/null) ;;
	esac
	# no tty: ?? on macOS, ? on Linux
	[ "${2:-}" != "??" ] && [ "${2:-}" != "?" ]
}
resident || exit 0

detail=""

# First occurrence of a string field, empty if absent. First, because a nested object
# (a background task, a teammate) can carry its own session_id later in the payload.
field() {
	printf '%s' "$payload" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[$2]*\"" |
		head -1 | sed 's/^.*:[[:space:]]*"//; s/"$//'
}

# Toast a deliberate notification. Detached, name lookup and all, so the hook stays fast;
# HUP ignored, since the hook can exit first
ping() {
	wz="$HOME/.claude/bin/wz"
	[ -x "$wz" ] || return 0
	(
		trap '' HUP
		ping_sid=$(field session_id '0-9a-fA-F-')
		who=""
		command -v jq >/dev/null 2>&1 && who=$(jq -r --arg s "$ping_sid" \
			'select(.sessionId == $s) | .name // empty' "$HOME"/.claude/sessions/*.json \
			2>/dev/null | head -1)
		who=${who:-pane $WEZTERM_PANE}
		case $1 in
		push_notification) set -- 0.8 "$who" "$2" ;;
		worker_permission_prompt) set -- 0.7 "$who: a worker wants approval" "$2" ;;
		*) set -- 0.4 "$who: refused, fell back" "$2" --quiet ;;
		esac
		sticky=""
		[ "$1" = 0.8 ] && "$wz" help 2>&1 | grep -q -- '--sticky' && sticky=--sticky
		"$wz" notify --pane "$WEZTERM_PANE" --rank "$1" $sticky ${4:-} -- "$2" "$3"
	) </dev/null >/dev/null 2>&1 &
}

case $state in
notify)
	msg=$(field message '^"')
	# A session can say something on purpose: its PushNotification tool, a background
	# worker waiting on approval, a refusal that fell back to another model. A toast each,
	# ranked for LEADER+t; the message test below still decides the pane's state
	kind=$(field notification_type 'a-z_')
	case $kind in
	push_notification | worker_permission_prompt | model_refusal_fallback) ping "$kind" "$msg" ;;
	esac
	case $msg in
	*permission*)
		state=asking
		detail=$(printf '%s' "$msg" |
			sed -n 's/.*to use \([A-Za-z][A-Za-z0-9_-]*\).*/\1/p' | head -1)
		;;
	*)
		# the 60s idle nag: Stop already recorded the truth, so leave it standing
		exit 0
		;;
	esac
	;;
asking)
	# PermissionRequest: fires at once, where Notification waits ~6s and resets on every
	# keystroke. Nothing clears it: readers drop it once the title spins again, or once the
	# registry stops after it, since Esc on the dialog ends the turn without a Stop.
	detail=$(field tool_name 'A-Za-z0-9_-')
	;;
done)
	# A live entry in background_tasks: the turn ended with the session's own children
	# running. Entries carry a status, and a finished one must not park the pane. jq,
	# because a task's command can hold any bracket a grep would stop at.
	if command -v jq >/dev/null 2>&1; then
		live=$(printf '%s' "$payload" | jq -r '
			[ .background_tasks[]? | select((.status // "running")
				| test("^(completed|done|failed|killed|stopped|cancell?ed|errored)$") | not) ]
			| if length > 0 then "live:" + ((.[0].type // "") | gsub("[\t\n]"; " "))
			  else empty end' 2>/dev/null)
		if [ -n "$live" ]; then
			state=parked
			detail=${live#live:}
		fi
	elif printf '%s' "$payload" |
		grep -q '"background_tasks"[[:space:]]*:[[:space:]]*\[[[:space:]]*{'; then
		# [^]] stops the match running past the array
		state=parked
		detail=$(printf '%s' "$payload" |
			sed -n 's/.*"background_tasks"[[:space:]]*:[[:space:]]*\[[^]]*"type"[[:space:]]*:[[:space:]]*"\([A-Za-z_ -]*\)".*/\1/p' |
			head -1)
	fi
	;;
errored)
	# StopFailure. Docs say `error`, one report says `error_type`, so both are tried.
	detail=$(field error 'a-z_')
	[ -n "$detail" ] || detail=$(field error_type 'a-z_')
	[ -n "$detail" ] || detail=unknown
	;;
esac

sid=$(field session_id '0-9a-fA-F-')

# The pane -> session map is rewritten on every event, not just SessionStart: anything
# that took it (a nested claude before the guard above, a crashed restart) is taken back
# on the resident session's next turn. Not on `ended`, the event that says it is leaving.
if [ -n "$sid" ] && [ "$state" != ended ]; then
	map="$HOME/.claude/wezterm-sessions"
	[ -d "$map" ] || mkdir -p "$map" 2>/dev/null
	printf '%s\n' "$sid" >"$map/$WEZTERM_PANE" 2>/dev/null
fi

dir="$HOME/.claude/wezterm-state"
[ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || exit 0
printf '%s\t%s\t%s\t%s\n' "$state" "$(date +%s)" "$detail" "$sid" \
	>"$dir/$WEZTERM_PANE" 2>/dev/null
exit 0
