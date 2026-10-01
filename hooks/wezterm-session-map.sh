#!/bin/sh
# SessionStart hook: record which Claude session is in this wezterm pane, so the save
# layer can rebuild it as `claude --resume <id>`. Keyed by pane id; wezterm.lua wipes the
# dir on gui-startup because ids restart from 0 with a new mux.
#
# Must stay silent: SessionStart stdout is injected into the session context. The one
# exception is a JSON systemMessage on a cold resume, which is shown and not injected.

payload=$(cat)
[ -n "${WEZTERM_PANE:-}" ] || exit 0

# A claude nested in another session's Bash tool inherits WEZTERM_PANE but has no
# terminal, and must not take the pane. Same check as wezterm-pane-state.sh.
set -- $(ps -o ppid=,tty=,comm= -p "$PPID" 2>/dev/null)
case ${3##*/} in
sh | bash | zsh | dash) set -- $(ps -o ppid=,tty=,comm= -p "$1" 2>/dev/null) ;;
esac
# no tty: ?? on macOS, ? on Linux
{ [ "${2:-}" != "??" ] && [ "${2:-}" != "?" ]; } || exit 0

dir="$HOME/.claude/wezterm-sessions"
[ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || exit 0

sid=$(printf '%s' "$payload" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]*"' |
	head -1 | sed 's/^.*:[[:space:]]*"//; s/"$//')
[ -n "$sid" ] || exit 0

printf '%s\n' "$sid" >"$dir/$WEZTERM_PANE" 2>/dev/null

# The pane's last state record belongs to whoever was here before, and nothing rewrites
# it until the first prompt. Readers drop it on sid anyway; clearing it here makes the
# pane read as a new session rather than as nothing in the second between.
state="$HOME/.claude/wezterm-state/$WEZTERM_PANE"
if [ -r "$state" ]; then
	was=$(awk -F'\t' 'FNR == 1 { print $4 }' "$state" 2>/dev/null)
	[ "$was" = "$sid" ] || rm -f "$state" 2>/dev/null
fi

# A resume or fork carries Claude Code's own price for the first request:
# prompt_cache_likely_expired, context_tokens, estimated_cache_write_usd (2.1.286). Its
# $/token is kept for cc-fleet; a cold resume is the one thing the cold rule says never to
# do, so it is said in the pane (systemMessage: shown, not put in context) and toasted
command -v jq >/dev/null 2>&1 || exit 0
US=$(printf '\037')
resume=$(printf '%s' "$payload" | jq -r '
	select(.source == "resume" or .source == "fork")
	| [(.prompt_cache_likely_expired == true), (.context_tokens // 0 | floor),
	   (.estimated_cache_write_usd // 0), (.session_title // "" | gsub("[\t\n\u001f]"; " "))]
	| map(tostring) | join("\u001f")' 2>/dev/null)
[ -n "$resume" ] || exit 0
IFS=$US read -r cold tokens usd title <<EOF
$resume
EOF

# Cents per million tokens written back, from a resume big enough to price reliably
cents=$(awk -v t="$tokens" -v u="$usd" 'BEGIN { if (t >= 10000 && u > 0) printf "%d", u * 1e8 / t }')
if [ -n "$cents" ] && [ "$cents" -gt 0 ]; then
	price="$HOME/.claude/cache/cache-write-price"
	printf '%s\t%s\n' "$cents" "$(date +%s)" >"$price.$$" 2>/dev/null && mv "$price.$$" "$price"
fi

# Below this a cold resume costs too little to be worth saying (cc-fleet's COLD_WORTH)
[ "$cold" = true ] && [ "$tokens" -ge 100000 ] 2>/dev/null || exit 0
name=$(jq -r --arg s "$sid" 'select(.sessionId == $s) | .name // empty' \
	"$HOME"/.claude/sessions/*.json 2>/dev/null | head -1)
# cc-handover takes a name or a pane, never a title; the pane was mapped above
handle=${name:-$WEZTERM_PANE}
[ -n "$name" ] || name=${title:-pane $WEZTERM_PANE}
cost=$(awk -v t="$tokens" -v u="$usd" 'BEGIN {
	k = t >= 1e6 ? sprintf("%.1fM", t / 1e6) : sprintf("%dk", t / 1000)
	printf "~%s tokens (~$%.2f)", k, u }')
body="first prompt rewrites $cost; cc-handover $handle --new is cheaper"
# nohup: the hook's session can end before wz has handed the toast off
nohup "$HOME/.claude/bin/wz" notify --pane "$WEZTERM_PANE" --rank 0.8 -- \
	"$name resumed cold" "$body" </dev/null >/dev/null 2>&1 &
jq -cn --arg m "Resumed cold: the $body" '{systemMessage: $m}'
exit 0
