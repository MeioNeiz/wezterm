#!/usr/bin/env python3
"""Print a header describing a Claude session, for a restored but unstarted pane.

Claude Code already records an `ai-title` and a `last-prompt` in the transcript,
so nothing has to be regenerated. Output is written with CRLF because wezterm
injects it straight into a pty.

Usage: claude-session-brief.py <session-id>
"""

import calendar
import glob
import json
import os
import sys
import time

WIDTH = 84
DIM = "\x1b[38;5;245m"
ACCENT = "\x1b[38;5;117m"
TITLE = "\x1b[1;38;5;223m"
OFF = "\x1b[0m"


def transcript_for(session_id):
    pattern = os.path.expanduser("~/.claude/projects/*/%s.jsonl" % session_id)
    hits = glob.glob(pattern)
    return hits[0] if hits else None


def read_session(path):
    title = last_prompt = last_ts = None
    turns = 0
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            kind = rec.get("type")
            if kind == "ai-title":
                title = rec.get("aiTitle") or title
            elif kind == "last-prompt":
                last_prompt = rec.get("lastPrompt") or last_prompt
            elif kind in ("user", "assistant"):
                turns += 1
                last_ts = rec.get("timestamp") or last_ts
    return title, last_prompt, turns, last_ts


def age(iso_ts):
    if not iso_ts:
        return None
    try:
        stamp = time.strptime(iso_ts[:19], "%Y-%m-%dT%H:%M:%S")  # transcripts are UTC
    except ValueError:
        return None
    secs = int(time.time() - calendar.timegm(stamp))
    if secs < 0:
        return None
    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    mins = rem // 60
    if days:
        return "%dd %dh" % (days, hours)
    if hours:
        return "%dh %dm" % (hours, mins)
    return "%dm" % mins


def wrap(text, width, indent):
    words, lines, current = text.split(), [], ""
    for word in words:
        candidate = (current + " " + word).strip()
        if len(candidate) > width and current:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return [(indent if i else "") + line for i, line in enumerate(lines)]


def main():
    if len(sys.argv) < 2:
        return 1
    session_id = sys.argv[1]
    path = transcript_for(session_id)

    out = []
    if not path:
        out.append("%s╭─%s no transcript found for %s%s" % (DIM, OFF, session_id[:8], OFF))
        out.append("%s╰─ Enter starts a fresh session%s" % (DIM, OFF))
    else:
        title, last_prompt, turns, last_ts = read_session(path)
        out.append("%s╭─ %s%s%s" % (DIM, TITLE, title or "Claude session", OFF))
        if last_prompt:
            body = " ".join(last_prompt.split())
            if len(body) > 240:
                body = body[:240].rstrip() + "…"
            for i, line in enumerate(wrap(body, WIDTH - 10, "      ")):
                label = "%slast:%s " % (ACCENT, OFF) if i == 0 else ""
                out.append("%s│%s  %s%s" % (DIM, OFF, label, line))
        meta = ["%d turns" % turns] if turns else []
        idle = age(last_ts)
        if idle:
            meta.append("idle %s" % idle)
        if meta:
            out.append("%s│  %s%s" % (DIM, " · ".join(meta), OFF))
        out.append("%s╰─ Enter to resume%s" % (DIM, OFF))

    sys.stdout.write("\r\n".join(out) + "\r\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
