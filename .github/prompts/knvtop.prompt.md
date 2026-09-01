# knvtop — KWin/Plasma GPU + LLM Monitor Widget

## Goal

Build a self-contained KWin/Plasma widget (KDE Plasma 6, Kubuntu) that renders
nvtop's graph panel — the four upper time-series lines — and, on hover,
pops up a detail view of the local LLM inference stack (llama.cpp, Ollama,
vllm, etc.) plus system RAM/CPU stats.

Reference: https://github.com/syllo/nvtop (TUI, C++/ncurses; we are NOT
forking it — we are building a widget that reads the same underlying data
sources directly, so nvtop itself is optional at runtime).

## The four graph lines (nvtop's upper graph panel)

| Line        | Color  | Meaning                          | Data source (this box)                          |
|-------------|--------|----------------------------------|--------------------------------------------------|
| GPU %       | blue   | GPU utilization %                | `/sys/class/drm/card*/device/gpu_busy_percent`   |
| GPU mem %   | yellow | VRAM/GTT used %                  | `rocm-smi` / `amdgpu_top` (GTT on APU, ~80 GB)   |
| GPU temp °C | purple | GPU temperature                  | `/sys/class/hwmon/hwmon*/temp1_input`            |
| GPU power % | green  | Power draw % of TDP              | `rocm-smi` power / `amdgpu_top` power            |
| CPU %       | orange | CPU utilization % (all cores)    | `/proc/stat` delta between samples               |

The CPU % line is useful to see what part of the model workload is in RAM
vs VRAM, i.e. CPU vs GPU — when the LLM is mostly offloaded to GPU the CPU
line stays low; when layers spill to RAM the CPU line climbs.

Target hardware: AMD Radeon 8060S iGPU (Strix Halo, gfx1151) — an APU with
unified memory. `rocm-smi` only reports the 2 GB dedicated domain, so for
mem% and power% we should prefer `amdgpu_top` (or `amd-smi` if available)
and fall back to hwmon sysfs for temp. The widget must degrade gracefully
(N/A) when a source is missing.

Multi-GPU / other vendors: nice-to-have (nvtop supports NVIDIA/AMD/Intel).
Immediate need is this one APU only.

## Hover / rollover detail view

On mouse-over of the widget, show a popup/tooltip (or expanded panel) with:

1. **llama.cpp** — every running instance:
   - full command line (flags: `-m`, `-ngl`, `-c`, `-np`, `--parallel`,
     `--ctx-size`, etc.)
   - model file in use
   - process PID, GPU offload, context size, slot count
   - source: parse `/proc/<pid>/cmdline` + `/proc/<pid>/status`
2. **Ollama** — running server: model(s) loaded, memory used, PID
   (ollama exposes `/api/ps` on `127.0.0.1:11434` — use it)
3. **vllm / other LLM servers** — same treatment, best-effort
4. **System stats** — RAM used/total, swap, CPU load avg, and the same
   four GPU values as text

Only LLM-related processes matter. Ignore everything else in the process
list (nvtop's command table is NOT wanted — this is LLM-focused).

## Environment / target

- Kubuntu 26.04, KDE Plasma 6 (Qt 6 / QML). Working on other Ubuntu is a
  bonus, not a requirement.
- Hardware: EVO-X2 (AMD Ryzen AI Max+ 395, Radeon 8060S iGPU, 96 GB
  LPDDR5X unified memory). `amdgpu_top` is the preferred GPU telemetry
  tool here; `rocm-smi` is installed but under-reports on this APU.
- Self-contained is best: read sysfs + `/proc` + (optionally) poll
  `amdgpu_top`/`rocm-smi`/ollama API. Do NOT require nvtop to be running.
  If a shell-out tool is needed, prefer one already installed on Kubuntu.

## Architecture notes (to validate via research)

- Plasma applet (plasmoid) vs. KWin widget (kwin script) vs. standalone
  Qt6/QML applet: research which is the right vehicle for a graphing
  widget with hover popups on Plasma 6. The `strix-halo-power` repo in
  this workspace already has a Plasma applet (`org.kde.pmode`) — reuse its
  structure as a starting template.
- Graph rendering: QML `Canvas` or `Path`-based polyline over a ring
  buffer of samples; sample interval ~1 s, 21 s window to match nvtop.
- Data collection: a small worker process (Python or C++) that polls the
  telemetry sources and exposes them to QML (e.g. via a Qt Quick
  `QAbstractListModel` or a simple JSON-over-stdio/pipe bridge, like the
  `pmode-bridge` pattern in `strix-halo-power`).
- LLM process discovery: scan `/proc/*/cmdline` for `llama-server`,
  `llama-cli`, `ollama`, `vllm` etc.; parse flags; query ollama `/api/ps`.

## Repo & workflow

- Gitea: `gitea@gitea.home.lan:DAE51D/knvtop.git` (branch `main`, no PRs).
- Commit/push at key milestones and before any big refactoring. Don't
  spam the log — a handful of meaningful commits is fine. Local `tar.gz`
  backups are also acceptable between milestones.
- Keep the prompt file (this file) updated in tandem with the design as
  decisions are made, same convention as the other repos in this workspace.

## Research findings (resolved 2026-08-25)

All five open questions below are answered with evidence from this box and
the nvtop source. Full detail: session memory `knvtop-research.md`.

1. **Vehicle → Plasma 6 declarative QML applet (plasmoid).** Same vehicle as
   the local `org.kde.pmode` applet (reuse its structure). KWin scripts are
   window-manager JS with no drawing surface; a standalone Qt6 app isn't
   panel-integrated. Root QML must be `PlasmoidItem`.
2. **Telemetry → primary `amd-smi metric --json`** (one-shot, amd-smi 26.5.0 /
   ROCm 7.14). `gpu_data[0]`: util = `usage.gfx_activity.value` (%); mem used =
   `mem_usage.used_gtt.value` (MB, the ~80 GB GTT); mem total =
   `mem_usage.total_gtt.value` (79872 MB); temp =
   `temperature.apu_temperature_gfx.value` (°C); power =
   `power.apu_average_gfx_power.value` (W GFX-only) / `power.socket_power.value`
   (W PPT). **Fallback (zero-dep, 1 Hz):** sysfs — util
   `/sys/class/drm/card1/device/gpu_busy_percent`; hwmon resolved **by
   `name == "amdgpu"`** (NOT the `hwmon4` index — it shifts at boot):
   `temp1_input` (milli-°C), `power1_input` (µW PPT). **Avoid as primary:**
   `amdgpu_top -J` (continuous stream, needs timeout+head) and `rocm-smi`
   (no JSON, only the 2 GB VRAM domain — wrong memory picture).
3. **How nvtop computes the 4 AMD metrics** (so we match): nvtop's AMD backend
   uses **libdrm** (`dlopen` libdrm_amdgpu), NOT ROCm/RSMI — see
   `src/extract_gpuinfo_amdgpu.c`. util = `AMDGPU_INFO_SENSOR_GPU_LOAD` (SMU
   `METRICS_AVERAGE_GFXACTIVITY`, == `amd-smi gfx_activity`); temp =
   `AMDGPU_INFO_SENSOR_GPU_TEMP`/1000 (edge); power draw =
   `AMDGPU_INFO_SENSOR_GPU_AVG_POWER` (µW package); **power cap = sysfs hwmon
   `power1_cap`** (current limit, default TDP) → POW% = draw*100/cap. **APU
   quirk:** nvtop's MEM bar = VRAM heap + GTT heap (a few GB), *not* the 96 GB
   pool. `power1_cap` may be unpopulated on Strix Halo → POW then shows draw-only.
   nvtop `-s/--snapshot` prints a JSON array & exits (no power cap in it).
4. **QML graph → `Canvas`.** 21 pts × 4 lines @ 1 Hz is trivial; `Canvas` has
   the least boilerplate and no C++. `Timer` pushes a sample, shifts the ring
   buffer, `requestPaint()` redraws 4 polylines.
5. **Ollama `/api/ps`** (v0.32.6, :11434): empty = `{"models":[]}`; a loaded
   entry carries `name`, `model`, `size_vram`, `size`,
   `details{parent_model,format,family,parameter_size,quantization_level}`,
   `expires_at`.

## Decisions (confirmed 2026-08-25)

- **MEM line = true GTT** (`used_gtt`/`total_gtt`, ~80 GB) — the real
  unified-memory LLM picture. Diverges from nvtop's MEM bar on purpose
  (nvtop shows VRAM+GTT heap = a few GB).
- **Popup = hover-expand + click** via `Plasmoid.fullRepresentation`, plus a
  one-line `toolTipMainText` rollover summary.
- **Data bridge = Python helper** (`backend/knvtop_poll.py`) emitting one JSON
  object per line to stdout, read by `QProcess` in QML. No C++ build.
- **Self-contained:** no nvtop at runtime; `amd-smi` + sysfs + `/proc` +
  ollama API only.

## Implementation plan

### Phase 1 — Scaffold (milestone commit 1)
1. Create `com.daevid.knvtop/` with `metadata.json` (KPackageStructure
   `Plasma/Applet`, KPlugin Id `com.daevid.knvtop`, FormFactors
   desktop+panel, `X-Plasma-API-Minimum-Version` 6.0) — copy/adjust from
   `strix-halo-power/applet/org.kde.pmode/metadata.json`.
2. `contents/ui/main.qml`: `PlasmoidItem` root, `inPanel` check,
   `compactRepresentation` (the Canvas graph), `fullRepresentation` (detail
   panel placeholder).
3. Install to `~/.local/share/plasma/plasmoids/`, verify it loads in panel +
   desktop.

### Phase 2 — Data bridge (milestone commit 2)
4. `backend/knvtop_poll.py`: reusable sampling functions
   (`gpu_sample()`, `sys_sample()`, `llm_sample()`, `ollama_ps()`).
   - GPU via `amd-smi metric --json` (subprocess, parse); on failure fall back
     to sysfs (resolve hwmon by `name == "amdgpu"`).
   - RAM/load from `/proc/meminfo`, `/proc/loadavg`.
   - LLM: scan `/proc/*/cmdline` for `llama-server|llama-cli|ollama|vllm`;
     `curl` ollama `/api/ps` (timeout 3 s).
5. `service/knvtop_service.py`: D-Bus service on the session bus
   (`com.daevid.knvtop` / `/com/daevid/knvtop`). Runs the poller in a
   background thread at 1 Hz. Exposes:
   - `com.daevid.knvtop.Sample.Get()` → `a{sv}` with keys `gpu`, `sys`, `llm`
   - `com.daevid.knvtop.Status.IsAlive()` → `bool`
   - `com.daevid.knvtop.Status.Restart()` → restarts the poller thread
6. `main.qml`: `PlasmaDBus.SessionBus.asyncCall` polls `Sample.Get()` every
   1 s; 21-pt ring buffer for the graph; bind detail-panel text.

### Phase 3 — Graph + popup (milestone commit 3)
6. `Canvas`: on new sample push to ring buffer, `requestPaint`; draw 4
   polylines (blue/yellow/purple/green) over a 21 s window with nvtop-style
   axis labels.
7. `fullRepresentation`: detail panel (llama.cpp section, Ollama section,
   system stats). `MouseArea` on root toggles `plasmoid.expanded` on hover;
   click also opens. `toolTipMainText` = one-line GPU summary.
8. Graceful N/A when a source is missing (power cap absent, ollama down, no
   LLM procs).

### Phase 4 — Polish + docs (milestone commit 4)
9. `README.md` (install, data sources, the nvtop-MEM-divergence note); update
   this prompt file in tandem.
10. Optional: `config/main.xml` for sample interval + which lines to show.

## Implementation learnings (2026-08-25)

- **`QProcess` does NOT work in declarative QML plasmoids.** No plasmoid in
  `/usr/share/plasma/plasmoids/` uses it. `QProcess` is a C++ class, not a
  QML type. The proven pattern (see `org.kde.pmode`) is a **D-Bus service**
  that the QML talks to via `PlasmaDBus.SessionBus.asyncCall`.
- **`Plasmoid.background` is not a valid property.** Use
  `Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground` instead.
  Assigning to `Plasmoid.background` causes a load error:
  "Cannot assign to non-existent property 'background'".
- **Do NOT add the plasmoid to the desktop/panel config via
  `plasma-org.kde.plasma.desktop-appletsrc`** — plasmashell rewrites that
  file and re-instantiates widgets, causing a flood of broken-widget popups.
  Install the plasmoid, verify the QML loads (no error dialog), then let the
  user add it via right-click → Add Widgets.
- **`plasma-org.kde.plasma.desktop-appletsrc` is under etckeeper-style git
  backup via `~`** — if you must edit it, commit the change deliberately.
- **`widgetById` in `evaluateScript` returns `undefined`** for newly added
  widgets. The `addWidget` return value is a `WorkspaceScripting::Widget`
  object whose string form contains a hex address, but `widgetById` does not
  accept that address. This makes programmatic verification of widget load
  state unreliable via D-Bus scripting.
- **`rtk` can mask real output.** When `rtk grep` returns empty, the actual
  `grep` may also return empty (no matches) — but `rtk` can also swallow
  output in ways that hide what is happening. If an `rtk`-wrapped command
  is failing or returning useless output, retry the SAME command WITHOUT
  `rtk` before trying anything else.
- **Anti-loop rule.** If the same command (or a near-identical variant) has
  been run 2-3 times without producing new information or changing state,
  STOP. Question the premise, switch approach, or say so explicitly.

## Implementation learnings (2026-08-26)

- **D-Bus service: use `dbus-python` + `dbus.mainloop.glib`, NOT Gio.**
  Mixing `Gio.DBusConnection.register_object` with `dbus.SessionBus().request_name`
  fails silently — the name is claimed but method replies are never sent.
  The working pattern: `dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)`
  first, then `dbus.service.BusName(BUS_NAME, bus=dbus.SessionBus())`, then
  `dbus.service.Object` subclass with `@dbus.service.method` decorators.
  Use `dbus.Dictionary`/`dbus.Array`/`dbus.Int64`/`dbus.Double`/`dbus.String`
  for return values (NOT `GLib.Variant` — incompatible with dbus-python's
  type system).
- **`dbus.NAME_FLAG_DO_NOT_QUEUE` does not exist** in the Python `dbus`
  module. `request_name(name)` with no flags is the default (queue).
- **CPU% via `/proc/stat` delta:** read the `cpu` line, compute
  `(1 - d_idle/d_total) * 100` between consecutive samples. First sample
  returns None (no baseline). Global `_prev_cpu` state in the poller module.
- **systemd user unit for the D-Bus service:** `knvtop.service` in
  `~/.config/systemd/user/`, `ExecStart=%h/Code/knvtop/service/knvtop_service.py`,
  `WantedBy=default.target`. The script needs `chmod +x` or systemd
  returns `203/EXEC`.

## Implementation learnings (2026-08-28)

### QML Canvas in plasmoids

- **Separate `Sparkline.qml` component works; inline Canvas in `main.qml` does not.**
  The key pattern (from `corestrip`): a standalone `Canvas`-rooted QML file with a
  `revision: int` property. The parent sets `revision: root.revision` (an int that
  increments each poll tick). The Sparkline has `onRevisionChanged: requestPaint()`.
  This forces a repaint every tick without the parent needing to call `requestPaint()`
  on a cross-scope id.
- **Cross-scope id references fail in nested Repeater delegates.** E.g.
  `barArea.spark.val()` inside a Repeater delegate that is inside a different
  `Item` scope will not resolve. Use root-level helper functions (`root.fmt(v)`,
  `root.mb(v)`) instead of reaching into sibling ids.
- **`font.strikeOut` is NOT a valid QML property.** Use `opacity` to dim disabled
  legend items. Assigning `font.strikeOut` causes a QML load error.
- **`Repeater` inside `ShapePath` fails:** "Cannot assign object of type
  QQuickRepeater to list property pathElements". `QtQuick.Shapes` is available in
  plasmoids but Repeater-generated `PathLine` elements don't work. Use `Canvas`
  for any multi-point polyline.
- **`Label` is NOT available in all QML contexts in plasmoids.** In
  `ToolTipView.qml` (a standalone Item, not a direct child of PlasmoidItem),
  `Label` fails with "Label is not a type" even with
  `import org.kde.plasma.plasmoid`. Use QtQuick's `Text` instead. In
  `main.qml` (the PlasmoidItem root), `Label` works fine because the
  `org.kde.plasma.plasmoid` import is in scope at the top level.

### Plasmoid expand/click behavior

- **`root.expanded` is the correct property to toggle, NOT `Plasmoid.expanded`.**
  `expanded` is a property on `PlasmoidItem` itself. Corestrip uses
  `root.expanded = !root.expanded` where `root` is the PlasmoidItem.
  `Plasmoid.expanded` does not exist as an accessible property.
- **`MouseArea` Z-order matters critically.** In QML, later-declared children
  are on top. If you declare a `MouseArea` *before* 5 `Sparkline` Canvas items,
  the Canvases are on top and eat all mouse events — the MouseArea never
  receives clicks. The `MouseArea` must be declared *after* (below in the file)
  all the visual children it needs to cover.
- **`toolTipItem` replaces `toolTipMainText`/`toolTipSubText`.** For a rich
  hover UI (bars, colors, multi-line), use `toolTipItem: ToolTipView { ... }`.
  The plain text properties only render monochrome text.
- **Plasmoids do NOT hot-reload QML.** After `cp -r` to the install dir, you
  must either logout/login or restart plasmashell. Removing and re-adding
  the widget from the panel also works. **No logout needed — and `kstart6`
  does not exist on this Kubuntu 26.04 install** (only `kstart`/`kstart5`,
  neither of which is `kstart6`); the reliable command here is just:
  `kquitapp6 plasmashell; nohup plasmashell >/tmp/plasmashell.log 2>&1 & disown`
  (a bare `&` without `disown`/`setsid` can get killed when the invoking
  shell/subshell exits). Check the log for `knvtop`/QML `error`/`Cannot`
  lines after restart to confirm the new QML loaded cleanly. If the
  D-Bus backend (`knvtop_poll.py`) changed instead, `systemctl --user
  restart knvtop.service` is the equivalent — no plasmashell restart
  needed for backend-only changes.

### Panel sizing

- **Use `Layout.fillWidth`/`Layout.fillHeight` + `Layout.minimumWidth/Height`
  and `Layout.preferredWidth/Height`.** Hardcoded `width`/`height` on the
  compactRepresentation Item conflict with the panel's layout system. The
  `inPanel` check switches between panel (160×50 min, 220×70 pref) and desktop
  (280×120 min, 360×160 pref) sizes.

### D-Bus service (dbus-python)

- **`Get()` returns a JSON string (`out_signature="s"`), not a dict.** QML
  parses with `JSON.parse(reply.values[0])`. Returning a `dbus.Dictionary`
  directly causes type-mismatch errors on the QML side.
- **The systemd user unit must `chmod +x` the script** or systemd returns
  `203/EXEC`. `ExecStart=%h/Code/knvtop/service/knvtop_service.py`.

### Drkonqi crash loop

- **`drkonqi-coredump-launcher` can crash-loop** (generating coredumps that
  trigger more launches). Mask via:
  `sudo ln -sf /dev/null /etc/systemd/user/drkonqi-coredump-{launcher.socket,pickup.service,cleanup.service,cleanup.timer}`
  Then `systemctl --user daemon-reload`.

### Power scaling

- **`power1_cap` is not populated on Strix Halo APU.** The power% line uses
  `gpu.power_cap_w || 100` (100 W default) as the denominator so the line
  renders even when the cap is null.

### Cosmetic issues (fixed 2026-08-28, corestrip-style component cleanup)

- Full view: ring gauges no longer crowd the stats text — the stats line was
  a single word-wrapped `Text` that read as overlapping the ring row above
  it; replaced with a `Flow` of short labeled chips (MEM/TMP/PWR/sys/load)
  that wrap per-chip with clear spacing.
- Full view: graph area height reduced 120→96px, better balanced against the
  LLM cards below.
- Full view: LLM card text wrap was already fixed in `b6ccb76` (ColumnLayout
  + `height: col.implicitHeight+16`); confirmed still correct after the
  extraction to `LlmCard.qml`.
- Compact view: legend font bumped 6pt→7.5pt.
- Tooltip → click target: added `cursorShape: Qt.PointingHandCursor` to the
  compact graph-area `MouseArea` for affordance (the click region itself
  already covered the full graph area, just lacked a visual cue).
- **Extracted two reusable components (matching corestrip's Ring/Card
  pattern)**: `Ring.qml` (parameterized Canvas ring gauge — replaces 5x
  duplicated ~25-line Canvas blocks) and `LlmCard.qml` (replaces 3x
  duplicated Rectangle+ColumnLayout blocks for llama.cpp/ollama/vllm
  entries). The 5 ring gauges and legend toggles are now driven by a single
  `Repeater` over a model array, same pattern already used for the compact
  legend.
- **Bug fix found during extraction**: the original inline ring-gauge
  `Canvas.onPaint` blocks read `root.gpu`/`root.sys` directly with no
  `requestPaint()` trigger — QML `Canvas` does not repaint just because a
  property referenced inside `onPaint` changes. The rings likely only ever
  rendered the value from the instant the popup opened and stayed static
  while it was open. `Ring.qml` fixes this with explicit
  `onRatioChanged/onValueTextChanged/onRingColorChanged: canvas.requestPaint()`,
  matching the working `Sparkline.qml` `onRevisionChanged` pattern.

### Second pass (2026-08-28, after live screenshot review)

- **Backend bug — phantom duplicate "llama.cpp" card.** `_is_llm()`/
  `llm_sample()` classified any process by `exe.startswith("llama")`, which
  also matches ollama's own bundled runner (e.g.
  `/usr/local/lib/ollama/llama-server`) that ollama spawns per loaded
  model. That showed up as a second, confusing "llama.cpp" card with no
  useful ngl/ctx/parallel info (ollama's runner uses short flags `-c`/`-np`,
  not `--ctx-size`/`--parallel`). Fixed with `_is_ollama_owned(argv)` —
  skip any `llama*` process whose binary path has `ollama` as a directory
  component. Verified live against the running D-Bus service.
- **QML bug — the real root cause of "CLI flags not wrapping".** `LlmCard.qml`
  (and the inline blocks before it) sized the card via a plain
  `height: col.implicitHeight + 16` on the Rectangle. **`ColumnLayout` sizes
  a managed child from `Layout.preferredHeight`, falling back to
  `implicitHeight` — it does NOT read a child's raw `height:` binding.**
  So the outer ColumnLayout never learned the card needed to be taller for
  a long wrapped cmdline; the Text wrapped correctly internally, but its
  lines painted past the Rectangle's (too-short) bottom edge and visually
  overlapped whatever card/label came next in the popup. This is why the
  "fix cmdline wrap" commit (`b6ccb76`) never actually resolved the report —
  wrapping itself worked, containment didn't. Fixed by using
  `implicitHeight: col.implicitHeight + 16` instead of `height:`, matching
  corestrip's own `Card.qml` (`implicitHeight: layout.implicitHeight + ...`).
  **Rule of thumb for any future card/container inside a Layout: always size
  it via `implicitHeight`/`Layout.preferredHeight`, never a raw `height:`
  binding — the Layout system silently ignores the latter.**
- **Wrong fix direction: forcing a dark background everywhere.** A light-
  themed screenshot showed the ring row/stats row text washed out. The
  first fix (hardcoding `background: Rectangle { color: "#101418" }` on
  the ScrollView) was backwards — the widget is supposed to have both a
  light and dark mode by following Plasma's own system color scheme for
  the ring/stats area (only the graph/cards/compact widget are meant to be
  permanently dark, nvtop-terminal style, via their own explicit Rectangle
  backgrounds). The real fix: leave that area's background alone (no
  explicit background = inherits Plasma's popup theme) and make ITS TEXT
  theme-aware instead, via `Kirigami.Theme.textColor` (see below), so it
  reads correctly in both light and dark system themes — reverted the
  background hack once this was understood.
- **`PlasmaCore.Theme.textColor` does not exist in Plasma 6 QML** — throws
  `TypeError: Cannot read property 'textColor' of undefined`. Grepped every
  installed system plasmoid under `/usr/share/plasma/plasmoids`: zero use
  `PlasmaCore.Theme.*`, several use `Kirigami.Theme.textColor` (confirmed
  via `org.kde.desktopcontainment`). Use `import org.kde.kirigami as
  Kirigami` + `Kirigami.Theme.textColor` for theme-aware colors; dim a
  "muted/secondary" variant with `Qt.rgba(c.r, c.g, c.b, 0.65)` rather than
  a second theme color role.
- **An illegal `--` inside an XML comment silently breaks the ENTIRE kcfg
  file, not just the entry near it.** Added `config/main.xml` with a
  comment containing `entry -- this just persists...` (double hyphen,
  invalid per the XML spec inside comments). Result: every single
  `Plasmoid.configuration.*` property in `main.qml` came back `undefined`
  ("Unable to assign [undefined] to bool" x5, for unrelated properties
  scattered through the whole file) — not an isolated failure near the
  comment. `xmllint --noout config/main.xml` catches this instantly;
  worth running after any kcfg edit, before deploying.
- **Popup dialog sizing.** `fullRepresentation` set a raw `width`/`height`
  directly on the root `ScrollView`. Plasma's popup `Dialog` sizes itself
  from `Layout.preferredWidth/Height` / `Layout.minimumWidth/Height` hints
  on the fullRepresentation root, not from raw geometry — without those
  hints the dialog chrome can end up wider than the content filling it
  (a persistent right-side gap after every row). Fixed by wrapping the
  `ScrollView` in an outer `Item` carrying those Layout hints, matching
  corestrip's `FullView.qml` root-Item pattern.
- **Verifying popup-only visual changes for this plasmoid is hard to
  automate.** No `xdotool`/`ydotool` were installed initially; installed
  `ydotool` + `ydotoold` (Wayland-native, uses `/dev/uinput`) since `xdotool`
  does not work against native Wayland windows/panels, only XWayland.
  `ydotool mousemove --absolute`/`click 0xC0` do move the real cursor and
  can click, confirmed via a taskbar tooltip appearing at the target
  coordinate — but blindly clicking panel/system-tray coordinates is risky:
  one attempt landed on an unintended target and triggered Plasma's
  Overview effect instead of the plasmoid popup. Prefer asking the user to
  click and screenshot over repeated blind coordinate guesses.
- **Plasma persists the popup's dialog size independent of QML — this can
  make a `Layout.preferredWidth`/`Height` change look like it did nothing.**
  Once a popup has been opened, Plasma writes the size it ended up at into
  `~/.config/plasma-org.kde.plasma.desktop-appletsrc` under
  `[Containments][N][Applets][ID][Configuration]` as `popupWidth=`/
  `popupHeight=` (every applet on the panel has this — checked: digital
  clock, binary clock, clipboard, system-monitor widgets all carry the same
  keys). On every subsequent open, Plasma restores *that* stored size and
  `Layout.preferredWidth/Height` on `fullRepresentation` is only consulted
  when no stored value exists yet. Three separate width tweaks in a row
  (640→660→520) all looked identical on screen because of this — none of
  them were actually being applied. Fix: quit plasmashell first
  (`kquitapp6 plasmashell`) to avoid a write race, back up the config file,
  delete the `popupWidth=`/`popupHeight=` lines for this applet's
  `[...][Configuration]` block (NOT the separate `[...][ConfigDialog]`
  block below it, which is the *config dialog's* remembered size, unrelated
  to the popup), then restart plasmashell. It re-derives from
  `Layout.preferredWidth/Height` and writes a fresh `popupWidth`/
  `popupHeight` back once the popup is opened again. This is editing an
  *existing* applet's already-established config values, not adding a new
  widget via scripting — different (and much lower-risk) from the
  `addWidget`/`evaluateScript` re-instantiation flood warned about above.

## Implementation learnings (2026-08-29, generic scan + unified list)

- **`knvtop_poll.py` and `knvtop_service.py` have two SEPARATE, hand-
  duplicated sample-building loops — a change to one does NOT reach the
  live widget unless mirrored in the other.** `knvtop_poll.py`'s own
  `main()` is only ever exercised by running the script standalone
  (`python3 knvtop_poll.py`); the actual systemd service runs
  `knvtop_service.py`, whose `KnvtopService._poll_loop()` imports specific
  functions by name (`from knvtop_poll import gpu_sample, sys_sample,
  llm_sample, ollama_ps`) and builds its OWN sample dict independently.
  Adding `gpu_proc_sample()` to `knvtop_poll.py` and testing it via
  `timeout 3 python3 knvtop_poll.py` looked completely correct for an
  entire debugging session while the live D-Bus service silently never
  had the feature at all (`_poll_loop()`'s `except Exception: pass` gave
  no error either — it wasn't erroring, `gpu_proc_sample()` just wasn't in
  the import line). **Whenever a new top-level sample field is added to
  `knvtop_poll.py`, it MUST also be wired into `knvtop_service.py`'s
  import line and `_poll_loop()`'s dict** — verify against the LIVE D-Bus
  service (`qdbus6 com.daevid.knvtop /com/daevid/knvtop
  com.daevid.knvtop.Sample.Get`), not just a standalone script run, before
  concluding a backend change actually shipped.
- **`Repeater.visible = false` does not hide its delegates.** A `Repeater`
  is a non-visual instantiator — the Items it creates get inserted as
  *siblings* of the Repeater in the tree, not children of it, so its own
  `visible` property has no bearing on them. The sanctioned way to
  conditionally show/hide repeated content is to gate the `model:`
  property itself (empty array when hidden), not to toggle `visible` on
  the `Repeater` element.
- **UX design correction, worth internalizing for any future filter UI on
  this widget**: a "show only X" checkbox should *narrow* a single list,
  not *switch between two disjoint views*. The first cut of the AI/LLM-
  only toggle built two separate code paths (specialized LLM cards XOR a
  separate generic list) that never overlapped — checked hid the generic
  list entirely, unchecked hid the LLM cards entirely, which is not what
  "processes only" filtering should mean. Fixed with `root.unifiedProcs`
  (merge `gpuProcs` with the recognized-by-name llama/ollama/vllm entries
  by pid, tagging `kind`) and `root.visibleProcs` (checked → keep only
  entries with a `kind`; unchecked → everything, LLM entries included). A
  recognized process keeps its rich fields (ngl/ctx/flags table, etc.)
  even when shown unfiltered alongside plain generic entries — merging
  preserves the LLM-specific data, it doesn't discard it in favor of the
  generic shape.
- **`llm_sample()` entries whose process has no open GPU fd (e.g. a pure
  HTTP router in front of the real GPU-computing workers) legitimately
  have no counterpart in `gpu_proc_sample()`'s scan at all.** They aren't
  a subset of each other — the merge above has to layer LLM entries on
  top of (not filter down from) the generic scan, keyed by pid, so a
  recognized process that doesn't hold a DRM fd still shows up.

## NPU research (2026-08-31/09-01, not implemented -- owner chose "skip for now")

The EVO-X2's NPU (`RyzenAI-npu5`, `amdxdna` driver, fw 1.1.2.65) was
investigated for a ring+line graph pair matching the GPU ones. Findings,
so this doesn't need re-deriving from scratch later:

- `amd-smi list` doesn't see the NPU at all -- GPU (`0000:c6:00.0`) only.
- No hwmon entry exists for it (checked every `/sys/class/hwmon/hwmon*`
  by `name`, same resolution method used for the GPU) -- no temp/power
  sensor exposed that way.
- `xrt-smi` (installed via `libxrt-utils-npu`, not present by default --
  only the runtime libs were) is the only real telemetry source:
  `xrt-smi examine -r aie-partitions -f JSON -o <file>` gives per-process
  hardware-context info -- PID, submissions/completions counts,
  migrations, errors, and `gops`/`egops`/`fps`/`latency` fields that are
  `"N/A"` until a workload is actively running. **No busy-percent field
  exists at all** -- unlike amdgpu's `drm-engine-*` ns counters, this is
  submission/completion *counts*, not cumulative time, so there's no
  clean way to derive a 0-100% figure the way GPU/CPU% work here.
- `xrt-smi` needs **root**, even though `/dev/accel/accel0` is
  `root:render` and `dae51d` IS in the `render` group -- it does an
  internal mmap of a PCI BAR resource that fails with `mmap(...) failed
  (err=-11): Resource temporarily unavailable` unless run via `sudo`,
  regardless of device-node group permissions. This is a genuine
  privilege gate, not a transient fluke (reproduced both with and
  without sudo, consistently).
- Power/electrical query specifically errors:
  `DRM_IOCTL_AMDXDNA_GET_INFO IOCTL failed (err=-22): Invalid argument`
  -- this firmware/driver combination doesn't support that query yet.
- Conclusion given to the owner: a ring gauge showing genuine NPU
  utilization isn't achievable with what this driver/firmware exposes at
  the OS level right now (young stack, actively developed upstream).
  Offered three honest options (submission-rate-as-a-number instead of a
  %, simple busy/idle indicator, or skip) -- owner chose skip. Revisit
  once `amdxdna`/`xrt-smi` exposes real utilization/power telemetry, or
  if `amd-smi` gains NPU support.

## TODO

- [x] Phase 1: plasmoid scaffold (`metadata.json` + `main.qml`), verify loads
- [x] Phase 2: D-Bus service (`service/knvtop_service.py`) + QML `PlasmaDBus` bridge
- [x] Phase 3: `Canvas` 5-line graph (GPU util/mem/temp/power + CPU) + `fullRepresentation` hover/click panel
- [x] Phase 3: graceful N/A handling (power cap / ollama / no LLM procs)
- [x] systemd user unit (`knvtop.service`) for the D-Bus service
- [x] Phase 3: custom `ToolTipView.qml` with colored bars (GPU/MEM/PWR/CPU/RAM)
- [x] Phase 3: click-to-expand via `root.expanded` + topmost `MouseArea`
- [x] Phase 3: cosmetic cleanup (ring gauge overlap, graph height, card text wrap)
- [x] Phase 3 polish pass (2026-08-28 evening): `Ring.qml`/`LlmCard.qml`
  extraction, ollama-owned-child exclusion, popup width/gap fixes (the
  ScrollView width trap + the popupWidth config-cache trap), ring
  centering, per-model ollama cards, pid de-emphasis, Flow→Row for the
  stats chips. See "Second pass" and later learnings above for the
  root-cause writeups.
- [x] `config/main.xml` + `config.qml` + `ui/ConfigGeneral.qml`: persists
  the 5 line-visibility toggles (`showGpu`/`showMem`/`showTemp`/
  `showPower`/`showCpu`) via `Plasmoid.configuration` instead of plain QML
  properties reset every session. Popup header row: pin button (checkable
  `window-pin`, toggles `root.hideOnWindowDeactivate`) + configure button
  (triggers the real `configure` internal action now that a config page
  exists). Only a poll-interval setting remains a nice-to-have — not added
  since the D-Bus service samples at a fixed 1 Hz regardless, so a
  QML-side interval knob wouldn't get new data any faster without also
  plumbing it through `knvtop_poll.py`/`knvtop_service.py`.
- [x] Ring row + stats row text is theme-aware (`Kirigami.Theme.textColor`)
  so it reads correctly in both Plasma light and dark color schemes — the
  graph/cards/compact widget stay permanently dark by design (nvtop-style
  terminal panels), only this area follows the system theme.
- [x] Phase 4: README.md written (install, data sources, the nvtop-MEM-
  divergence note, and the cross-user GPU-stats/CAP_SYS_PTRACE setup step).
- [x] Generic nvtop-style GPU process scan (2026-08-29): `gpu_proc_sample()`
  walks `/proc/*/fdinfo` for DRM client fds (Graphic/Compute classification
  from which `drm-engine-*` keys are present, GPU% as a delta of the
  cumulative ns counters). Config page: real "AI/LLM processes only"
  checkbox (default true) + User/Type filters, all wired to
  `Plasmoid.configuration` and applied via `filteredGpuProcs`.
- [x] Per-process live stats row on every LLM card (GPU%/GPU MEM/CPU%/Host
  MEM), sharing the same `_fdinfo_gpu_stats()` helper as the generic scan
  plus a new `_proc_cpu_pct()` (delta of `/proc/<pid>/stat` utime+stime,
  same pattern as `_cpu_sample()`).
- [x] Cross-user GPU visibility: `/proc/<pid>/fdinfo` is same-uid-or-root
  only, so a process owned by a different account (this box's actual
  llama.cpp, which runs as `aistack`, not this service's `dae51d`) read
  GPU%/VRAM as N/A. Fixed by granting `cap_sys_ptrace` to a **dedicated
  copy** of python3 (`/usr/local/lib/knvtop/python3-ptrace`), not the
  shared system binary — capabilities live on the file's inode, so
  setcap'ing the real `/usr/bin/python3.14` would've handed
  `cap_sys_ptrace` to every Python script anyone runs on the machine.
  `knvtop.service`'s `ExecStart` auto-detects the dedicated copy and falls
  back to plain `python3` if it isn't set up (README documents the setup
  step for other users). Verified: the router process (port 8082, a pure
  HTTP proxy with no GPU context of its own) correctly still shows N/A;
  the actual inference process now reports real VRAM/GPU%.
- [x] Milestone commits pushed to `main` (Gitea `DAE51D/knvtop`)

## Verification

1. `python3 backend/knvtop_poll.py` standalone — one JSON line/s, correct
   keys, GTT ≈80 GB total, sane temp/power.
2. `curl -s http://127.0.0.1:11434/api/ps | jq .` cross-check the ollama
   section.
3. Load plasmoid in panel + desktop — 4 lines render, colors correct, scroll
   at 1 Hz.
4. Hover → tooltip; hover-expand/click → detail panel shows llama-server
   cmdline (model, ctx-size, parallel, n-gpu-layers), ollama models, RAM/load.
5. Kill ollama / an LLM proc → widget degrades to N/A, no crash.
6. Reboot-resilience: hwmon resolved by name (not index) — confirm after a
   reboot if possible.

## Scope

- **In:** single APU (EVO-X2), 4 GPU lines, LLM-only hover detail, RAM/CPU,
  self-contained.
- **Out (later):** multi-GPU, NVIDIA/Intel backends, per-process GPU-mem
  attribution, panel-only sizing tweaks, packaging (.plasmoid/deb).