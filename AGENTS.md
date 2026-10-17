# knvtop — agent notes

Working-style rules (anti-loop rule, rtk caveats, progress updates) live in
`~/.claude/CLAUDE.md` — read and follow them.

Project-specific:

- Design decisions + research findings: `knvtop.prompt.md` (keep it in sync).
- Plasmoid source: `com.daevid.knvtop/`; runtime copy is
  `~/.local/share/plasma/plasmoids/com.daevid.knvtop/` — deploy with
  `scripts/deploy-dev.sh` (not a bare `cp -r`). It rsyncs the tree and stamps
  **only the installed copy's** `Version` as `<Version>+YYYYMMDD.HHMM.<sha>[-dirty]`,
  which Settings → About shows, so you can tell which build is live. The
  source `metadata.json` Version stays clean (release builds untouched).
  plasmashell only re-reads it on restart; `--restart` does that (confirm
  with the user first — it reloads every widget).
- **Do NOT add the plasmoid to the desktop/panel config via
  `plasma-org.kde.plasma.desktop-appletsrc`** — plasmashell rewrites that file
  and re-instantiates widgets, which caused a flood of broken-widget popups on
  2026-08-25. Install the plasmoid, verify the QML loads (no error dialog),
  then let the user add it via right-click → Add Widgets.
- `plasma-org.kde.plasma.desktop-appletsrc` is under etckeeper-style git
  backup via `~` — if you must edit it, commit the change deliberately.
- **`com.daevid.knvtop/metadata.json`'s `KPlugin.Version` tracks what is
  published on opendesktop/KDE Store** (https://www.opendesktop.org/p/2370069/),
  NOT the number of commits or work sessions. It is the version Plasma shows
  in "Add Widgets" and Settings → About. The rule:
  - Published releases so far: 1.0.0, 1.1.0, 1.1.1. The next release is
    **1.2.0** (the version in the tree until it is uploaded).
  - **Do not bump the version per commit or per feature.** Everything that
    lands between two uploads ships under the one next version. Bump only
    *after* a release is uploaded, to the next number (minor for new
    features, patch for a fix-only release), and record the uploaded one in
    the list above.
  - If unsure what the next number should be, ask the user — an inflated
    version is hard to walk back once it's published (it was inflated to
    1.4.0 once by bumping per-feature; reset to 1.2.0 on 2026-10-16).
  - The dev build stamp from `scripts/deploy-dev.sh` is what distinguishes
    work-in-progress builds, so the release number doesn't have to.
  - Package for upload: commit, then `scripts/build-plasmoid.sh` (it
    packages `HEAD`, so uncommitted changes are NOT in it).

## Gotcha: the QML D-Bus type never delivers method arguments

`PlasmaDBus.dbusMessage` (`org.kde.plasma.workspace.dbus`) as shipped here
(plasma-workspace 6, Qt 6.10) **drops `arguments` on the floor** — the callee
sees zero args whether they're plain JS values, `new PlasmaDBus.string(...)`,
with or without `signature`, and whether set in the constructor map or
assigned afterwards (six variants tested 2026-10-16). `Sample.Get` and
`Status.Restart` only work because they take none. So **any widget→service
call that needs a value must carry it in the object path or member**, not
`arguments`. Kill does this: `Kill()` on `/com/daevid/knvtop/kill/<pid>`,
served by a dbus-python `FallbackObject` (`KnvtopKillObject`). Don't re-try
arguments, `Qt.createQmlObject` workers, a `/tmp` PID-file watcher, or a
`__getattr__` fake `Kill_<pid>` method — all were tried and fail (dbus-python
only dispatches decorated methods; the `/tmp` file is also a local
privilege hole since the service kills via sudo).

Restart uses the identical scheme: `Restart()` on
`/com/daevid/knvtop/restart/<pid>` (`KnvtopRestartObject`). The service
re-resolves the owning unit from the pid via `owning_unit()` in
`knvtop_poll.py` (cgroup → `system:x.service` / `user:x.service`, with a
denylist for kwin/sddm/logind/dbus/user@/knvtop) — **never accept a unit name
from the client**. `KnvtopDBusObject` already has a `Restart` (Status iface,
restarts the poller), and dbus-python keys members on the Python function
name, so a second `Restart` can't live on that class. Test restart/kill only
against throwaway `systemd-run --user --unit=restart-probe sleep 600` units
(the name must not start with `knvtop` or the denylist blocks it).

Also: `Kill` must stay async (`async_callbacks` + worker thread). It waits up
to ~5s for the process to die; blocking the GLib loop stalls the 1s `Get`
polls and trips `failedPollCount >= 3` (the "not installed" panel).

**Testing the widget→service hop without plasmashell:** write a
`TestCase` that makes the same `dbusMessage` call and run it with
`QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen
/usr/lib/qt6/bin/qmltestrunner -input tst_x.qml`. It exercises the exact
Plasma D-Bus marshalling the widget uses. Aim it at a throwaway
`sleep`, never a real service. Note value-type constructors need `new`.

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
