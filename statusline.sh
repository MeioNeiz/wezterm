#!/bin/bash
# Claude Code statusLine: names the conversation at the bottom of its own pane, so
# a 3-4 way wezterm split is identifiable without scrolling up the chat.
#
# The line ends with @<name>: the address SendMessage needs to reach this pane from
# another session. It sits last and is the only @-token on the line, so wezterm's
# quick-select can lift it without dragging in the rest. Default names are the cwd
# plus a random suffix, which tells four panes in one repo apart but says nothing
# useful; /rename fixes that, and bare /rename derives one from the conversation.
#
# Title priority matches Claude's own: /rename (custom-title) > aiTitle > first
# prompt. Recent builds hand the first two over as .session_name, so the transcript
# scan is now only a fallback for builds that do not.
#
# The scan reads the 256KB tail first (title lines are rewritten throughout a
# session), and the whole-file pass, needed only when every title line is older
# than that, is cached per session. Transcripts reach 13MB.

readonly CACHE_DIR="$HOME/.claude/cache/statusline"
# The pane's identity colour, and the one place it can appear inside the pane itself:
# wezterm has no per-pane colour of any kind, so this line is it. Sourced rather than
# run, since the statusLine is on the critical path of every turn.
# shellcheck source=/dev/null
source "$HOME/.claude/bin/cc-colour" --lib
readonly BLUE=$'\033[38;2;137;180;250m'
readonly MAUVE=$'\033[38;2;203;166;247m'
readonly YELLOW=$'\033[38;2;249;226;175m'
readonly RED=$'\033[38;2;243;139;168m'
readonly DIM=$'\033[38;2;108;112;134m'
readonly RESET=$'\033[0m'
readonly MAX_TITLE=64
readonly MAX_NOTE=52
readonly NOTES="$HOME/.claude/fleet/notes.tsv"
readonly CTX_DIR="$HOME/.claude/cache/context"

# ${#title} below must count characters, not bytes
export LC_CTYPE=${LC_CTYPE:-en_GB.UTF-8}

payload=$(cat)

# Split on a unit separator, not a tab: tab is IFS whitespace, so bash would fold
# the empty fields an older build leaves behind and shift every value left one.
IFS=$'\x1f' read -r transcript session dir title ctx_used ctx_size model effort fast now < <(
	printf '%s' "$payload" | jq -r '
		[ .transcript_path // "",
		  .session_id // "",
		  (.workspace.current_dir // .cwd // ""),
		  (.session_name // ""),
		  (.context_window.used_percentage // ""),
		  (.context_window.context_window_size // ""),
		  (.model.display_name // ""),
		  (.effort.level // ""),
		  (if .fast_mode then "fast" else "" end),
		  (now | floor) ]
		| map(tostring | gsub("\\s+"; " ")) | join("\u001f")
	' 2>/dev/null
)

# Older builds may not pass transcript_path; the layout is derivable from cwd.
if [[ -z $transcript && -n $session && -n $dir ]]; then
	slug=${dir//[^A-Za-z0-9]/-}
	transcript="$HOME/.claude/projects/$slug/$session.jsonl"
fi

# Most authoritative title in a jsonl stream: a manual rename beats Claude's own.
scan_titles() {
	awk '
		/"type":"custom-title"/ { custom = $0 }
		/"type":"ai-title"/     { ai = $0 }
		END { if (custom != "") print custom; else if (ai != "") print ai }
	' | jq -r '.customTitle // .aiTitle // empty' 2>/dev/null
}

# Fallback for a session too young to have been titled yet. Matched by line rather
# than by a byte budget: a mid-line cut leaves jq a half-written record, and it then
# discards the whole batch over the one it could not parse.
first_prompt() {
	grep -m 60 '"type":"user"' "$1" 2>/dev/null | jq -r '
		select((.isMeta // false) | not)
		| .message.content
		| if type == "string" then .
		  elif type == "array" then [ .[] | select(.type == "text") | .text ] | join(" ")
		  else empty end
		| select(type == "string" and (startswith("<") | not))
		| gsub("\\s+"; " ")
	' 2>/dev/null | head -1
}

# A window bootstrapped by a peer handover has no ordinary prompt at all: the
# message lands as isMeta, which Claude's own titler and first_prompt both skip,
# so it reads "untitled" until the first human turn - which for a handover may
# never come. Name it after the sender and the handover's opening line instead.
# Splitting on ">" and rejoining survives a body containing one.
handover_prompt() {
	grep -m 40 'cross-session-message from=' "$1" 2>/dev/null | jq -r '
		.message.content
		| select(type == "string")
		| (capture("from-name=\"(?<who>[^\"]+)\"") // {who: "peer"}).who as $who
		| (split(">") | .[1:] | join(">") | sub("^\\s+"; "") | split("\n")[0]
		   | gsub("\\s+"; " ")) as $body
		| select($body != "")
		| "\($who): \($body)"
	' 2>/dev/null | head -1
}

if [[ -z $title && -r $transcript ]]; then
	title=$(tail -c 262144 "$transcript" | scan_titles)

	if [[ -z $title && -n $session ]]; then
		cache="$CACHE_DIR/$session"
		if [[ -r $cache ]]; then
			title=$(<"$cache")
		else
			title=$(scan_titles <"$transcript")
			if [[ -n $title ]]; then
				mkdir -p "$CACHE_DIR" 2>/dev/null &&
					printf '%s\n' "$title" >"$cache" 2>/dev/null
			fi
		fi
	fi

	[[ -z $title ]] && title=$(first_prompt "$transcript")
	[[ -z $title ]] && title=$(handover_prompt "$transcript")
fi

[[ -z $title ]] && title="untitled"

title=${title%%$'\n'*}
((${#title} > MAX_TITLE)) && title="${title:0:$((MAX_TITLE - 1))}…"

# One git call for both facts; branch is line 1, worktree root line 2.
branch=""
root=""
if [[ -n $dir && -d $dir ]]; then
	gitinfo=$(git -C "$dir" rev-parse --abbrev-ref HEAD --show-toplevel 2>/dev/null)
	branch=${gitinfo%%$'\n'*}
	root=${gitinfo#*$'\n'}
	[[ $root == "$branch" ]] && root=""
	[[ $branch == HEAD ]] && branch="detached"
fi

label=${root:-$dir}
label=${label##*/}

# Auto-compact is off, so nothing else warns before the window fills. Naming the
# window size too, since a 200k session and a 1M one wear the same percentage very
# differently.
context=""
context_colour=""
if [[ $ctx_used =~ ^[0-9]+$ ]]; then
	if ((${ctx_size:-0} >= 1000000)); then
		window="$((ctx_size / 1000000))M"
	elif ((${ctx_size:-0} >= 1000)); then
		window="$((ctx_size / 1000))k"
	else
		window="${ctx_size:-?}"
	fi
	context="${ctx_used}% of ${window}"
	((ctx_used >= 80)) && context_colour=$RED
	((ctx_used >= 60 && ctx_used < 80)) && context_colour=$YELLOW
fi

# Catches a /model or /effort left behind in one pane. The parenthetical is the
# context window, which the context field already says.
engine=${model%% (*}
[[ -n $effort ]] && engine="${engine} ${effort}"
[[ -n $fast ]] && engine="${engine} ⚡"

# What this session told itself, out of cc-note. Every field has a "-" placeholder, so
# tab-as-IFS has nothing to fold.
note_status=""
note_progress=""
if [[ -n $session && -r $NOTES ]]; then
	while IFS=$'\t' read -r n_sid _ n_flags n_prog n_stat; do
		[[ $n_sid == "$session" ]] || continue
		[[ ${n_prog:--} != "-" ]] && note_progress=$n_prog
		[[ ${n_stat:--} != "-" ]] && note_status=$n_stat
		break
	done <"$NOTES"
fi
if ((${#note_status} > MAX_NOTE)); then
	note_status="${note_status:0:$((MAX_NOTE - 1))}…"
fi

# How full this session is, for everything that cannot ask: Claude hands this number to
# the statusLine and nowhere else (see CLAUDE.md). Silent on failure, since a pane's own
# line must never break over a cache it writes for others.
if [[ -n $session && $ctx_used =~ ^[0-9]+$ ]]; then
	[[ -d $CTX_DIR ]] || mkdir -p "$CTX_DIR" 2>/dev/null
	printf '%s\t%s\t%s\n' "$ctx_used" "${ctx_size:-0}" "${now:-0}" \
		>"$CTX_DIR/$session" 2>/dev/null
fi

# The registry holds the name SendMessage addresses, and the payload does not carry it.
# Keyed by pid, so one jq over every file matches on the session id. Folded the way
# cc-roster folds it: a background session is named after its task, spaces and all.
peer=""
if [[ -n $session ]]; then
	peer=$(jq -r --arg s "$session" 'select(.sessionId == $s) | (.name // empty)
		| ascii_downcase | sub("^\\s+"; "") | sub("\\s+$"; "") | gsub("\\s+"; "-")' \
		"$HOME"/.claude/sessions/*.json 2>/dev/null | head -1)
fi

# The title is the pane's identity colour rather than a fixed blue. It is the first thing
# on the line and much the longest, so it is the one part that is always on screen however
# long the rest gets - which the trailing @name is not.
id_colour "$session"
# The whole line, not only the title: the metadata was grey, and grey carries nothing
# that the identity colour would be displacing. Muted rather than full strength, at the
# brightness the grey had, so this reads as one pane-coloured line rather than as six
# competing fields. The context percentage is the exception - its yellow and red are a
# warning and outrank identity.
meta=${IDC_MUTED:-$DIM}
out="${IDC_ANSI:-$BLUE}${title}${RESET}"
# Straight after the title, because the far end of the line is where a narrow pane
# truncates and a note the session left for itself outranks the branch it is on.
[[ -n $note_progress ]] && out+="${meta}  ·  ${RESET}${YELLOW}${note_progress}${RESET}"
[[ -n $note_status ]] && out+="${meta}  ·  ${RESET}${YELLOW}▸ ${note_status}${RESET}"
[[ -n $label ]] && out+="${meta}  ·  ${label}${RESET}"
[[ -n $branch ]] && out+="${meta}  ·  ${branch}${RESET}"
[[ -n $context ]] && out+="${meta}  ·  ${RESET}${context_colour:-$meta}${context}${RESET}"
[[ -n $engine ]] && out+="${meta}  ·  ${engine}${RESET}"
[[ -n $peer ]] && out+="${meta}  ·  ${RESET}${IDC_ANSI:-$MAUVE}@${peer}${RESET}"
printf '%s' "$out"
