---
paths:
  - "wezterm.lua"
  - "statusline.sh"
  - "bin/cc-board"
  - "bin/cc-fleet"
  - "bin/cc-peers"
  - "bin/cc-colour"
  - "bin/cc-tint"
  - "toast/**"
---

# Anything that draws on screen

Colour channels, the tint and the palette, with the reasoning: `docs/colour.md`.

- Greys: RULE #585b70 for what is not text (dividers, empty bar cells), FAINT #7f849c and
  DIM #9399b2 for text. Anything below overlay1 is unreadable on Mocha: surface1 on base is
  1.8:1, and 1.0:1 on a marked row
- Width counts characters, never bytes: `${#var}` in bash under en_GB.UTF-8, `utf8.len` in
  Lua. Every glyph here is multibyte
- `wezterm cli list` reports `tab_id`, not the tab number. The tab bar and LEADER+1..9 count
  positions from one; ascending tab_id within a window is that order
- No em-dashes or en-dashes in anything on screen
