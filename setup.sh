#!/bin/bash
# Links this repo into place and registers its hooks with Claude. macOS or Linux, safe to
# rerun: replaces links, never a real file. Windows: setup-windows.ps1, config only.
set -eu
repo=$(cd "$(dirname "$0")" && pwd)
settings="$HOME/.claude/settings.json"

link() {
	local target=$1 path=$2
	if [ -L "$path" ] || [ ! -e "$path" ]; then
		mkdir -p "$(dirname "$path")"
		ln -sfn "$target" "$path"
	else
		echo "skipped $path: a real file is there; move it aside and rerun"
	fi
}

# cc-toast: the on-screen toast wz notify raises on macOS. A build product, so gitignored;
# rebuilt when the source is newer
if [ "$(uname)" = Darwin ] && [ -f "$repo/toast/cc-toast.swift" ]; then
	if ! command -v swiftc >/dev/null; then
		echo "cc-toast not built: needs swiftc (xcode-select --install); wz notify falls back"
	elif [ ! -x "$repo/bin/cc-toast" ] || [ "$repo/toast/cc-toast.swift" -nt "$repo/bin/cc-toast" ]; then
		swiftc -O "$repo/toast/cc-toast.swift" -o "$repo/bin/cc-toast" &&
			echo "built bin/cc-toast" || echo "cc-toast build failed; wz notify falls back"
	fi
fi

link "$repo/wezterm.lua" "$HOME/.wezterm.lua"
link "$repo/statusline.sh" "$HOME/.claude/statusline.sh"
link "$repo/skills/fleet" "$HOME/.claude/skills/fleet"
for f in "$repo"/hooks/*; do
	link "$f" "$HOME/.claude/hooks/${f##*/}"
done
# both: wezterm.lua and the hooks call ~/.claude/bin by full path, only ~/.local/bin is on PATH
for f in "$repo"/bin/*; do
	link "$f" "$HOME/.claude/bin/${f##*/}"
	link "$HOME/.claude/bin/${f##*/}" "$HOME/.local/bin/${f##*/}"
done

for cmd in jq python3 git wezterm claude; do
	command -v "$cmd" >/dev/null || echo "missing: $cmd"
done
case ":$PATH:" in
*":$HOME/.local/bin:"*) ;;
*) echo "~/.local/bin is not on PATH, so bare cc-* calls will not resolve" ;;
esac

command -v jq >/dev/null || {
	echo "hooks not registered: needs jq"
	exit 0
}
[ -f "$settings" ] || echo '{}' >"$settings"

# Per command: one an event already runs (however its path is spelt) is left alone, and
# only the missing ones are added, as a group of their own
tmp=$(mktemp)
jq --arg home "$HOME" '
def hook($arg): { type: "command", command: ("\"$HOME/.claude/hooks/wezterm-pane-state.sh\" " + $arg) };
def norm: gsub("\""; "") | sub("^~"; "$HOME") | split($home) | join("$HOME");
{
	SessionStart: { hooks: [
		{ type: "command", command: "\"$HOME/.claude/hooks/wezterm-session-map.sh\"" },
		{ type: "command", command: "\"$HOME/.claude/bin/cc-tint\"", timeout: 5 }
	] },
	UserPromptSubmit: { hooks: [hook("working")] },
	Notification: { matcher: "permission_prompt|push_notification|worker_permission_prompt|model_refusal_fallback", hooks: [hook("notify")] },
	Stop: { hooks: [hook("done")] },
	SessionEnd: { hooks: [hook("ended")] },
	StopFailure: { hooks: [hook("errored")] },
	PermissionRequest: { hooks: [hook("asking")] }
} as $want
| reduce ($want | to_entries[]) as $e (.;
	([.hooks[$e.key][]?.hooks[]?.command | norm]) as $got
	| [$e.value.hooks[] | select((.command | norm) as $c | $got | any(.[]; . == $c) | not)] as $missing
	| if ($missing | length) == 0 then .
	  else .hooks[$e.key] = ((.hooks[$e.key] // []) + [$e.value + { hooks: $missing }]) end)
| .statusLine //= { type: "command", command: "\"$HOME/.claude/statusline.sh\"" }
' "$settings" >"$tmp"

if cmp -s "$tmp" "$settings"; then
	rm "$tmp"
else
	cp "$settings" "$settings.bak"
	mv "$tmp" "$settings"
	echo "registered hooks in $settings (previous copy: settings.json.bak)"
fi
jq -e '.statusLine.command | test("statusline.sh")' "$settings" >/dev/null ||
	echo "statusLine left as it was: point it at ~/.claude/statusline.sh to get the pane line"

# cc-handovers: yesterday's handover digest at 08:30. Rewrites and reloads its own plist
if [ "$(uname)" = Darwin ] && [ -z "${SETUP_NO_LAUNCHD:-}" ]; then
	"$HOME/.claude/bin/cc-handovers" --install || echo "cc-handovers --install failed"
fi
