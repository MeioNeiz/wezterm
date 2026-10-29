#!/bin/bash
# Refuses prompts (arg `prompt`, UserPromptSubmit) and tool calls (`tool`, PreToolUse) once
# this session's account has reached a cap in ~/.claude/account-limits (cc-account limits).
# Silent below it: nothing reaches the model, so a prompt under the cap costs no tokens.
# Toasts once a window at the warning and at the stop; at the stop it also ends an override
# lending this folder to the account, so the next session here starts on the folder's own.
# An account with a fallback (cc-account) moves the session there instead, resumed in place
# once its turn ends, so long as the fallback is below its own caps: the move only ever
# goes to an account with room, so two can never pass a session back and forth.
# Usage comes from the statusLine's per-account cache, so it lags by at most one response.

[[ -s $HOME/.claude/account-limits ]] || exit 0
source "$HOME/.claude/bin/cc-account" --lib
acct_load
[[ -n $ACCT_NAMES ]] || exit 0
acct_current
account=$ACCT
dir=${CLAUDE_PROJECT_DIR:-$PWD}
acct_limits "$account" "$dir"
[[ -n $LIM_KEY ]] || exit 0

moving=""
if [[ -n $LIM_STOP ]]; then
	acct_fallback "$account" "$dir"
	if [[ -n $ACCT_FALLBACK ]]; then
		stop=$LIM_STOP key=$LIM_KEY
		acct_limits "$ACCT_FALLBACK" "$dir"
		[[ -z $LIM_STOP ]] && moving=$ACCT_FALLBACK
		LIM_STOP=$stop LIM_KEY=$key
	fi
fi

# Once per session: every refused tool call of the turn lands here, and the switch is
# already waiting for that turn to end
if [[ -n $moving ]]; then
	input=$(cat)
	sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
	mark="$HOME/.claude/cache/limits/moving-$sid"
	if [[ -z $sid ]]; then
		moving=""
	elif [[ -z $(find "$mark" -mmin -15 2>/dev/null) ]]; then
		if [[ ${1:-} == prompt ]]; then
			then=$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null)
		else
			then="Resumed on $moving: $account reached its usage cap mid-turn. Carry on where"
			then+=" you left off."
		fi
		mkdir -p "${mark%/*}" && : >"$mark"
		"$HOME/.claude/bin/cc-account" switch "$sid" --to "$moving" --force \
			${then:+--then "$then"} </dev/null >/dev/null 2>&1 || { rm -f "$mark"; moving=""; }
	fi
fi

back=""
if [[ -n $LIM_STOP ]]; then
	acct_for "$dir"
	if [[ -n $ACCT_UNTIL && $ACCT == "$account" ]]; then
		"$HOME/.claude/bin/cc-account" use --end "$dir" >/dev/null 2>&1
		back=" ${ACCT_OVR_DIR/#$HOME/~} is back on $ACCT_BASE: new sessions there start on it."
	fi
fi

seen="$HOME/.claude/cache/limits/$LIM_KEY"
if [[ ! -e $seen ]]; then
	mkdir -p "${seen%/*}" && : >"$seen"
	find "${seen%/*}" -type f -mtime +8 -delete 2>/dev/null
	notify=("$HOME/.claude/bin/wz" notify)
	[[ -n ${WEZTERM_PANE:-} ]] && notify+=(--pane "$WEZTERM_PANE")
	if [[ -n $moving ]]; then
		notify+=("Usage cap: $account to $moving" "$LIM_STOP. Moving to $moving.$back")
	elif [[ -n $LIM_STOP ]]; then
		notify+=(--sticky "Usage cap: $account stopped" "$LIM_STOP.$back")
	else
		notify+=("Usage warning: $account" "$LIM_WARN")
	fi
	("${notify[@]}" </dev/null >/dev/null 2>&1 &)
fi

[[ -n $LIM_STOP ]] || exit 0
if [[ -n $moving ]]; then
	case ${1:-} in
	prompt)
		why="Usage cap: $LIM_STOP. Moving this session to $moving: it resumes here and runs"
		why+=" this prompt then."
		printf '{"decision":"block","reason":"%s"}\n' "$why"
		;;
	tool)
		why="Usage cap: $LIM_STOP. This session is moving to $moving and resumes in place"
		why+=" once this turn ends: end it now with a one-line status, then it carries on."
		printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse",%s,%s}}\n' \
			'"permissionDecision":"deny"' "\"permissionDecisionReason\":\"$why\""
		;;
	esac
	exit 0
fi
case ${1:-} in
prompt)
	printf '{"decision":"block","reason":"%s"}\n' \
		"Usage cap: $LIM_STOP.$back cc-account limits shows where it stands."
	;;
tool)
	why="Usage cap: $LIM_STOP. Every tool call is refused until it resets."
	why+=" Do not retry or work round it: stop and tell Jacob."
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse",%s,%s}}\n' \
		'"permissionDecision":"deny"' "\"permissionDecisionReason\":\"$why\""
	;;
esac
exit 0
