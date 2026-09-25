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

# An event that already runs any of these commands is left alone
tmp=$(mktemp)
jq '
def hook($arg): { type: "command", command: ("\"$HOME/.claude/hooks/wezterm-pane-state.sh\" " + $arg) };
{
	SessionStart: { hooks: [
		{ type: "command", command: "\"$HOME/.claude/hooks/wezterm-session-map.sh\"" },
		{ type: "command", command: "\"$HOME/.claude/bin/cc-tint\"", timeout: 5 }
	] },
	UserPromptSubmit: { hooks: [hook("working")] },
	Notification: { matcher: "permission_prompt", hooks: [hook("notify")] },
	Stop: { hooks: [hook("done")] },
	SessionEnd: { hooks: [hook("ended")] },
	StopFailure: { hooks: [hook("errored")] },
	PermissionRequest: { hooks: [hook("asking")] }
} as $want
| reduce ($want | to_entries[]) as $e (.;
	[.hooks[$e.key][]?.hooks[]?.command] as $got
	| ($e.value.hooks | map(.command)) as $cmds
	| if ($cmds - $got | length) < ($cmds | length) then .
	  else .hooks[$e.key] = ((.hooks[$e.key] // []) + [$e.value]) end)
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
