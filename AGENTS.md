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
- **Bump `com.daevid.knvtop/metadata.json`'s `KPlugin.Version`** with any
  commit that ships a real feature or fix (not pure docs/comment-only
  changes). This is the version Plasma shows in the "Add Widgets" browser
  and the widget's own info popup when installing/updating — it's the
  only version indicator, on purpose (no in-UI version string). Pre-1.0:
  bump the minor digit for new features (0.1.0 → 0.2.0), the patch digit
  for a fix-only pass.

## Toolchain (installed 2026-09-02)

- **`ruff`** (0.16.x, via `uv tool install ruff`, on PATH at
  `~/.local/bin/ruff`). Linter + formatter for the Python backend.
  - `ruff check com.daevid.knvtop/backend/knvtop_poll.py` — lint.
  - `ruff format --check <file>` — would-it-reformat check.
  - **The editor auto-save hook already runs `ruff format`** on the Python
    backend, so the committed style IS ruff-format style. Don't fight it —
    if a save reformats an unrelated section, that's the hook, not you.
  - `ruff check` reports pre-existing style nits (BLE001 blind-`except` is
    *intentional* — the poller must never crash a Plasma applet; PLW1510 /
    SIM115 / ISC004 are cosmetic). Don't auto-fix these; they're by design.
- **`qmllint` / `qmlformat`** (Qt 6.10, from `qt6-declarative-dev-tools`;
  real binaries in `/usr/lib/qt6/bin/`, symlinked into `/usr/local/bin/`).
  - `qmllint com.daevid.knvtop/contents/ui/main.qml` — validate QML.
    Ignore the `Plasmoid.contextualActions` "missing-property" warning
    (Plasma injects it at runtime) and the `unqualified` style warnings.
  - `qmlformat --check <file>` — would-it-reformat. Note: the existing QML
    is hand-styled and does NOT match qmlformat's style, so do NOT run a
    bulk `qmlformat` over the tree (huge unrelated diff). Use it only to
    check a file you just wrote, or format a single new file.
- **`uv`** (0.12.x) is available for installing any other Python tool on
  demand: `uv tool install <pkg>`.
