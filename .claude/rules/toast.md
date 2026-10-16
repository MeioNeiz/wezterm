---
paths:
  - "toast/**"
---

# Editing cc-toast

Behaviour and flags: `docs/tools.md` § notify, and cc-toast.

- Build: `swiftc -O toast/cc-toast.swift -o bin/cc-toast` (setup.sh does it when the source
  is newer). `bin/cc-toast` is gitignored; both links point at it
- **Never steal focus.** A non-activating panel, accessory app; check the frontmost app
  before and after a test
- It sits inside WezTerm on purpose: Notification Centre draws every banner into one
  full-screen window, so there is no measuring where native banners are to stack below them
- **Jacob sees every test toast.** One, with obviously fake text, then stop. Verify by
  `screencapture` to the scratchpad and reading the crop
- Slots are `~/.claude/cache/cc-toast/<n>`, `<pid> <height> <sticky> <started_ms> <rank>
  <pane>`; a dead pid frees one. Order is LEADER+t's (kev-pick score, else rank) then
  newest, not slot number; past five the last in that order goes, non-sticky first. Never
  rank here: change wezterm.lua's `kev_ranking`, the one scorer
- A compact toast is laid out at full height and shrunk: the banner views stretch
  (`.height`), everything else is pinned to the top (`.minYMargin`)
- A sticky toast never times out, so anything that can make one must also be able to close
  it: being on its pane, a click, x, or its pane closing
- Panel motion is `Spring`, stepped by a display link; never `animator().setFrame` on the
  panel: a retarget restarts a fixed curve and drops the speed it had, which is the jank.
  Anything that changes a slot calls `announce()`, so every toast restacks on one frame
