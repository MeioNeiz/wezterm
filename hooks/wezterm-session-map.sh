#!/bin/sh
# SessionStart hook: record which Claude session is in this wezterm pane, so the save
# layer can rebuild it as `claude --resume <id>`. Keyed by pane id; wezterm.lua wipes the
# dir on gui-startup because ids restart from 0 with a new mux.
#
# Must stay silent: SessionStart stdout is injected into the session context.

payload=$(cat)
[ -n "${WEZTERM_PANE:-}" ] || exit 0

# A claude nested in another session's Bash tool inherits WEZTERM_PANE but has no
# terminal, and must not take the pane. Same check as wezterm-pane-state.sh.
set -- $(ps -o ppid=,tty=,comm= -p "$PPID" 2>/dev/null)
case ${3##*/} in
sh | bash | zsh | dash) set -- $(ps -o ppid=,tty=,comm= -p "$1" 2>/dev/null) ;;
esac
[ "${2:-}" != "??" ] || exit 0

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
exit 0
