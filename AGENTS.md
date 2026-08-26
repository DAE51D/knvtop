# knvtop — agent notes

Working-style rules (anti-loop rule, rtk caveats, progress updates) live in
`~/.claude/CLAUDE.md` — read and follow them.

Project-specific:

- Design decisions + research findings: `knvtop.prompt.md` (keep it in sync).
- Plasmoid source: `com.daevid.knvtop/`; runtime copy is
  `~/.local/share/plasma/plasmoids/com.daevid.knvtop/` — `cp -r` after edits.
- **Do NOT add the plasmoid to the desktop/panel config via
  `plasma-org.kde.plasma.desktop-appletsrc`** — plasmashell rewrites that file
  and re-instantiates widgets, which caused a flood of broken-widget popups on
  2026-08-25. Install the plasmoid, verify the QML loads (no error dialog),
  then let the user add it via right-click → Add Widgets.
- `plasma-org.kde.plasma.desktop-appletsrc` is under etckeeper-style git
  backup via `~` — if you must edit it, commit the change deliberately.
