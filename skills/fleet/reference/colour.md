# Colour on the fleet surfaces

Two channels, told apart by **what carries them** rather than by hue. Getting this wrong
in a report to Jacob is worse than saying nothing: he reads these surfaces at a glance
and a mis-description sends him to the wrong pane.

## Status is a dot

`●` in the state's colour, one per pane, with `?` for blocked on a prompt and `✓` for
just finished. Mauve anywhere a pane needs an answer. The tab bar, `cc-board` and its
strip all use the one alphabet; the board adds `›` for a shell pane, which the bar never
shows.

| state | colour | means |
|---|---|---|
| asking / waiting | `#cba6f7` mauve | stopped, wants an answer |
| fresh | `#f9e2af` yellow | finished in the last 90s |
| waiting | `#ffd7af` peach | stopped, no longer fresh |
| working | `#a6e3a1` green | busy, needs nothing |
| stale | `#6c7086` grey | hours old, or the session has exited |

Fresh ages out at 90 seconds (`FRESH_SECONDS`, `FRESH_SECS`), and waiting's `#ffd7af`
sits next to fresh's `#f9e2af`, so copying the glyphs without the hues would leave `✓`
and `●` both reading as yellow.

## Identity is a text colour

One of nine Catppuccin accents per session, saying only *which chat this is*: the pane's
whole statusLine, its label in the tab bar, the name column on `cc-board`, `cc-fleet`
and the `LEADER+;` picker, and the workspace name in the window status bar.

The pane itself is tinted too - background, foreground, cursor and selection, set per
pane by `cc-tint` over OSC, because wezterm has no per-pane colour config and each pane
is its own terminal emulator. Ground and text rotate to the same hue together, which
makes a tinted pane slightly *easier* to read than the untinted default rather than
harder.

```bash
cc-colour --all                 # every session's identity colour
cc-colour --pin d5-lca-48 teal  # settle a duplicate
cc-tint --all                   # repaint panes already running
cc-tint --level off|whisper|faint|subtle|full
cc-tint --reset
```

## Nine hues over forty sessions

Duplicates happen. `cc-board` marks a tab where two panes share one (`tab 1 · 4 · 2
alike`) and names the hue in the block under the cursor. **Do not describe a colour to
Jacob as if it were unique without checking that flag.**

Assignment is the first 8 hex of the session id mod nine, so every reader agrees without
coordinating and a colour survives `/rename`, `--resume` and a reboot. It also tells
apart two sessions that share a name, which happens.

One exception: a new session in a pane that already had one is held at least three hues
away from the colour it is replacing, because adjacent hues are 1.6-2.9 dE apart in
Oklab and that is inside the range where two colours you cannot compare side by side
read as the same. Those rehues are written to `~/.claude/session-colours-auto`; hand
pins in `~/.claude/session-colours` win.

Useful side effect: two sessions sharing a name still get different colours.

The full reasoning, including the four approaches that were tried and abandoned, is in
`~/personal/wezterm/CLAUDE.md`. Read it before changing any of this.
