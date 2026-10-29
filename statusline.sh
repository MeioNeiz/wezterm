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
readonly BLUE=$'\033[38;2;137;180;250m'
readonly MAUVE=$'\033[38;2;203;166;247m'
readonly YELLOW=$'\033[38;2;249;226;175m'
readonly RED=$'\033[38;2;243;139;168m'
readonly DIM=$'\033[38;2;108;112;134m'
readonly RESET=$'\033[0m'
readonly BADGE_ODD=$'\033[48;2;250;179;135m\033[38;2;30;30;46m'
readonly BADGE_STOP=$'\033[48;2;243;139;168m\033[38;2;30;30;46m'
readonly MAX_TITLE=64
readonly MAX_NOTE=52
readonly NOTES="$HOME/.claude/fleet/notes.tsv"
readonly CTX_DIR="$HOME/.claude/cache/context"
readonly RATE_EVERY=5
# cc-peers' title memo, `mtime\x1fchecked_at\x1ftitle`; "sl" in the mtime slot says the
# title came from here, which cc-peers trusts without looking at the transcript
readonly TITLE_MEMO="$HOME/.claude/cache/titles"
readonly SEP="  ·  "
readonly LINE_TTL=30

# ${#title} below must count characters, not bytes
export LC_CTYPE=${LC_CTYPE:-en_GB.UTF-8}

left_width() {
	lw=0
	local i n=0
	for i in "${!seg[@]}"; do
		[[ -n ${seg[i]} ]] || continue
		((lw += seg_w[i] + (n ? ${#SEP} : 0), n++))
	done
}
fits() {
	left_width
	((lw + gap + right_w <= width))
}
# $1 the fewest characters it keeps, cut from the whole title; reads lw from the fits before
cut_title() {
	local room=$((width - right_w - gap - (lw - seg_w[0])))
	((room < $1)) && room=$1
	seg[0]="${title_colour}${title}${RESET}"
	seg_w[0]=${#title}
	((${#title} > room)) || return 0
	seg[0]="${title_colour}${title:0:$((room - 1))}…${RESET}"
	seg_w[0]=$room
}

draw() {
	# The right side outranks everything on the left, which gives way first in full: the
	# metadata, the title down to 8, the notes and badge, then the title itself. Room the
	# notes leave goes back to the title.
	# COLUMNS is the pane's width; Claude indents the line 2 and cuts it 2 short of the edge
	gap=2
	fitted=false
	if [[ $COLUMNS =~ ^[0-9]+$ ]] && ((COLUMNS > 20)) && [[ -n $right ]]; then
		fitted=true
		width=$((COLUMNS - 4))
		for i in $drops; do
			fits && break
			seg[i]=""
		done
		fits || cut_title 8
		for ((i = ${#seg[@]} - 1; i > 0; i--)); do
			fits && break
			seg[i]=""
		done
		fits
		cut_title 4
		fits || seg[0]=""
		left_width
		((lw)) || gap=0
		((lw + gap + right_w < width)) && gap=$((width - lw - right_w))
	fi

	out=""
	for i in "${!seg[@]}"; do
		[[ -n ${seg[i]} ]] || continue
		[[ -n $out ]] && out+="${meta}${SEP}${RESET}"
		out+=${seg[i]}
	done
	if [[ -n $right ]]; then
		if $fitted; then
			printf -v pad '%*s' "$gap" ''
			out+="${pad}${right}"
		else
			out+="${meta}${SEP}${RESET}${right}"
		fi
	fi
	printf '%s' "$out"
}

payload=$(cat)

# Split on a unit separator, not a tab: tab is IFS whitespace, so bash would fold
# the empty fields an older build leaves behind and shift every value left one.
IFS=$'\x1f' read -r transcript session dir title ctx_used ctx_size model effort fast now \
	pc_expires pc_ttl pc_recache pc_hit rl_5h rl_5h_at rl_7d rl_7d_at rl_spend < <(
	printf '%s' "$payload" | jq -r '
		def pct(f): if type == "number" then f | round else . end;
		[ .transcript_path // "",
		  .session_id // "",
		  (.workspace.current_dir // .cwd // ""),
		  (.session_name // ""),
		  (.context_window.used_percentage // ""),
		  (.context_window.context_window_size // ""),
		  (.model.display_name // ""),
		  (.effort.level // ""),
		  (if .fast_mode then "fast" else "" end),
		  (now | floor),
		  (.prompt_cache.expires_at // "-"),
		  ((.prompt_cache.ttl // "" | capture("^(?<n>[0-9]+)(?<u>[smhd])$")
		   | (.n | tonumber) * {s: 1, m: 60, h: 3600, d: 86400}[.u]) // "-"),
		  (.prompt_cache.recache_tokens_if_cold // "-"),
		  (.prompt_cache.hit_ratio // "-" | pct(. * 100)),
		  (.rate_limits.five_hour.used_percentage // "-" | pct(.)),
		  (.rate_limits.five_hour.resets_at // "-"),
		  (.rate_limits.seven_day.used_percentage // "-" | pct(.)),
		  (.rate_limits.seven_day.resets_at // "-"),
		  (.rate_limits.spend_limit // "-" | if type == "string" then . else tojson end) ]
		| map(tostring | gsub("\\s+"; " ")) | join("\u001f")
	' 2>/dev/null
)

# refreshInterval re-renders an idle pane every 2s with the same payload, only to refit the
# line to a pane that may have been resized. So the pieces come from the last full render,
# which runs again when the payload or the notes change, or once LINE_TTL old
line_cache="$CACHE_DIR/$session.line"
key="$transcript $dir $title $ctx_used $ctx_size $model $effort $fast $pc_expires $pc_ttl"
key+=" $pc_recache $pc_hit $rl_5h $rl_5h_at $rl_7d $rl_7d_at $rl_spend"
# Strictly newer than the notes: -nt counts whole seconds, and a note can land in the second
# a full render wrote the cache
if [[ -n $session && -r $line_cache && $line_cache -nt $NOTES ]]; then
	seg=() seg_w=()
	{
		IFS= read -r c_key
		IFS= read -r c_at
		IFS= read -r c_right_w
		IFS= read -r c_drops
		IFS= read -r c_meta
		IFS= read -r c_right
		IFS= read -r c_title
		IFS= read -r c_title_colour
		while IFS=$'\x1f' read -r w text; do
			seg+=("$text")
			seg_w+=("$w")
		done
	} <"$line_cache"
	if [[ $c_key == "$key" && $c_at =~ ^[0-9]+$ ]] && ((${now:-0} - c_at < LINE_TTL)); then
		right_w=$c_right_w drops=$c_drops meta=$c_meta right=$c_right title=$c_title
		title_colour=$c_title_colour
		draw
		exit 0
	fi
fi

# The pane's identity colour, and the one place it can appear inside the pane itself:
# wezterm has no per-pane colour of any kind, so this line is it. Sourced rather than
# run, since the statusLine is on the critical path of every turn.
# shellcheck source=/dev/null
source "$HOME/.claude/bin/cc-colour" --lib
# shellcheck source=/dev/null
source "$HOME/.claude/bin/cc-account" --lib
# Rate limits are per account: this session's from CLAUDE_CONFIG_DIR, which Claude passes on
acct_load
acct_current
account=$ACCT
acct_suffix "$account"
readonly RATE_FILE="$HOME/.claude/cache/rate-limits$ACCT_SUFFIX"

# Claude's own session_name: /rename, else its title. Kept before the fallbacks below
sname=$title

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

# Which login this pane runs on, once there is more than one. Loud when it is not the
# account this folder defaults to, which is a session moved on purpose or by mistake
# A solid badge, since a yellow word mid-line went unseen. An override lending the folder
# still wears it, with its end, and the cap the folder has on this account beside it.
acct_tag=""
acct_odd=false
acct_bg=$BADGE_ODD
if [[ $ACCT_NAMES == *" "* ]]; then
	acct_tag=$account
	acct_for "$dir"
	if [[ $ACCT_BASE != "$account" ]]; then
		acct_odd=true
		if [[ $ACCT == "$account" && -n $ACCT_UNTIL ]]; then
			if [[ $OSTYPE == darwin* ]]; then
				acct_tag+=" till $(date -r "$ACCT_UNTIL" +%H:%M)"
			else
				acct_tag+=" till $(date -d "@$ACCT_UNTIL" +%H:%M)"
			fi
		else
			acct_tag+=", not $ACCT_BASE"
		fi
	fi
	ACCT_NOW=${now:-0}
	acct_limits "$account" "$dir"
	[[ -n $LIM_TAG ]] && acct_tag+=" · $LIM_TAG"
	if [[ -n $LIM_STOP ]]; then
		acct_tag+=" STOPPED"
		acct_odd=true
		acct_bg=$BADGE_STOP
	fi
fi

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

# How full this session is and when its prompt cache goes cold, for everything that
# cannot ask: Claude hands both to the statusLine and nowhere else (see CLAUDE.md). Silent
# on failure, since a pane's own line must never break over a cache it writes for others.
# The last four fields are the rate limits this session reported last time, for the block
# below to tell a new response from a re-render.
# Written only when a field besides the epoch moved: refreshInterval re-renders an idle pane
# every few seconds, and the epoch is cache_cold_at's last resort for when it went quiet.
rl_fresh=0
ctx_changed=0
if [[ -n $session && $ctx_used =~ ^[0-9]+$ ]]; then
	[[ -d $CTX_DIR ]] || mkdir -p "$CTX_DIR" 2>/dev/null
	o_rec="" s5=- s5_at=- s7=- s7_at=-
	if [[ -r $CTX_DIR/$session ]]; then
		IFS=$'\t' read -r o1 o2 _ o4 o5 o6 o7 s5 s5_at s7 s7_at <"$CTX_DIR/$session"
		o_rec="$o1 $o2 $o4 $o5 $o6 $o7 $s5 $s5_at $s7 $s7_at"
	fi
	[[ $rl_5h\ $rl_5h_at\ $rl_7d\ $rl_7d_at != "$s5 $s5_at $s7 $s7_at" ]] && rl_fresh=1
	n_rec="$ctx_used ${ctx_size:-0} ${pc_expires:--} ${pc_ttl:--} ${pc_recache:--} ${pc_hit:--}"
	n_rec+=" ${rl_5h:--} ${rl_5h_at:--} ${rl_7d:--} ${rl_7d_at:--}"
	if [[ $n_rec != "$o_rec" ]]; then
		ctx_changed=1
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ctx_used" "${ctx_size:-0}" \
			"${now:-0}" "${pc_expires:--}" "${pc_ttl:--}" "${pc_recache:--}" "${pc_hit:--}" \
			"${rl_5h:--}" "${rl_5h_at:--}" "${rl_7d:--}" "${rl_7d_at:--}" \
			>"$CTX_DIR/$session" 2>/dev/null
	fi
fi

# The title the transcript scan in cc-peers would find, handed over once per change: a
# title only moves during a turn, and every turn renders this line. read is a builtin
if [[ -n $session && -n $sname ]]; then
	memo_src="" memo_title=""
	[[ -r $TITLE_MEMO/$session ]] &&
		IFS=$'\x1f' read -r memo_src _ memo_title <"$TITLE_MEMO/$session"
	if [[ $memo_src != sl || $memo_title != "$sname" ]]; then
		[[ -d $TITLE_MEMO ]] || mkdir -p "$TITLE_MEMO" 2>/dev/null
		printf 'sl\x1f%s\x1f%s\n' "${now:-0}" "$sname" >"$TITLE_MEMO/$session" 2>/dev/null
	fi
fi

# Rate limits are per account, a file each (RATE_FILE), but the payload does not say which
# login: after a /login an idle pane still carries the old one's figures, and every
# re-render repeats the last response's. So a session writes only figures that changed since
# its own last render, a new response, and otherwise at most every RATE_EVERY seconds keeps
# the file alive while it agrees with it. Never "later reset wins": another account's window
# can reset later and would stick until it did. A timer render that changed nothing keeps
# nothing alive, so the right status still ages out an idle machine's figures.
if [[ $rl_5h != "-" || $rl_7d != "-" ]] && [[ -n $rl_5h ]]; then
	rl_last=0 f5=- f5_at=- f7=- f7_at=-
	[[ -r $RATE_FILE ]] && IFS=$'\t' read -r rl_last f5 f5_at f7 f7_at _ <"$RATE_FILE"
	if ((rl_fresh)) || { ((ctx_changed && ${now:-0} - ${rl_last:-0} >= RATE_EVERY)) &&
		[[ $rl_5h\ $rl_5h_at\ $rl_7d\ $rl_7d_at == "$f5 $f5_at $f7 $f7_at" ]]; }; then
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${now:-0}" "$rl_5h" "${rl_5h_at:--}" "$rl_7d" \
			"${rl_7d_at:--}" "${rl_spend:--}" >"$RATE_FILE.$$" 2>/dev/null &&
			mv -f "$RATE_FILE.$$" "$RATE_FILE" 2>/dev/null
	fi
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
# on the line and much the longest, so the fit below shortens it last.
id_colour "$session"
# The whole line, not only the title: the metadata was grey, and grey carries nothing
# that the identity colour would be displacing. Muted rather than full strength, at the
# brightness the grey had, so this reads as one pane-coloured line rather than as six
# competing fields. The context percentage is the exception - its yellow and red are a
# warning and outrank identity.
meta=${IDC_MUTED:-$DIM}
# Each segment as drawn and as wide as it draws. Notes straight after the title: a note
# the session left for itself outranks the branch it is on
seg=() seg_w=()
add_seg() {
	seg+=("$1")
	seg_w+=("$2")
}
add_seg "${IDC_ANSI:-$BLUE}${title}${RESET}" "${#title}"
[[ -n $note_progress ]] && add_seg "${YELLOW}${note_progress}${RESET}" "${#note_progress}"
[[ -n $note_status ]] && add_seg "${YELLOW}▸ ${note_status}${RESET}" $((${#note_status} + 2))
i_label="" i_acct="" i_branch="" i_engine=""
if [[ -n $label ]]; then
	i_label=${#seg[@]}
	add_seg "${meta}${label}${RESET}" "${#label}"
fi
if $acct_odd; then
	add_seg "${acct_bg} ${acct_tag} ${RESET}" $((${#acct_tag} + 2))
elif [[ -n $acct_tag ]]; then
	i_acct=${#seg[@]}
	add_seg "${meta}${acct_tag}${RESET}" "${#acct_tag}"
fi
if [[ -n $branch ]]; then
	i_branch=${#seg[@]}
	add_seg "${meta}${branch}${RESET}" "${#branch}"
fi
if [[ -n $engine ]]; then
	i_engine=${#seg[@]}
	add_seg "${meta}${engine}${RESET}" "${#engine}"
fi

# Context and @name sit flush right, the pane's bottom-right corner: the nearest Claude
# lets anything else draw to its own mode line, the row below
right="" right_w=0
if [[ -n $context ]]; then
	right="${context_colour:-$meta}${context}${RESET}"
	right_w=${#context}
fi
if [[ -n $peer ]]; then
	[[ -n $right ]] && right+="${meta}${SEP}${RESET}" && ((right_w += ${#SEP}))
	right+="${IDC_ANSI:-$MAUVE}@${peer}${RESET}"
	((right_w += ${#peer} + 1))
fi
title_colour=${IDC_ANSI:-$BLUE}
drops="$i_engine $i_branch $i_label $i_acct"

if [[ -n $session ]]; then
	[[ -d $CACHE_DIR ]] || mkdir -p "$CACHE_DIR" 2>/dev/null
	{
		printf '%s\n' "$key" "${now:-0}" "$right_w" "$drops" "$meta" "$right" "$title" \
			"$title_colour"
		for i in "${!seg[@]}"; do
			printf '%s\x1f%s\n' "${seg_w[i]}" "${seg[i]}"
		done
	} >"$line_cache" 2>/dev/null
fi
draw
