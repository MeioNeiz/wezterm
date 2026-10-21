#!/bin/bash
# Refuses prompts (arg `prompt`, UserPromptSubmit) and tool calls (`tool`, PreToolUse) once
# this session's account has reached a cap in ~/.claude/account-limits (cc-account limits).
# Silent below it: nothing reaches the model, so a prompt under the cap costs no tokens.
# Toasts once a window at the warning and at the stop; at the stop it also ends an override
# lending this folder to the account, so the next session here starts on the folder's own.
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
	if [[ -n $LIM_STOP ]]; then
		notify+=(--sticky "Usage cap: $account stopped" "$LIM_STOP.$back")
	else
		notify+=("Usage warning: $account" "$LIM_WARN")
	fi
	("${notify[@]}" </dev/null >/dev/null 2>&1 &)
fi

[[ -n $LIM_STOP ]] || exit 0
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
