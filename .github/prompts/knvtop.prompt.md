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
  must either logout/login or `kquitapp6 plasmashell && kstart6 plasmashell`.
  Removing and re-adding the widget from the panel also works.

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

### Cosmetic issues (known, not yet fixed)

- Full view: ring gauges overlap the stats text to their right.
- Full view: graph area is too tall relative to the LLM cards below.
- Full view: LLM card text (cmdline) is truncated — needs word-wrap or
  horizontal scroll.
- Compact view: legend text is very small (6pt) — could be 7-8pt.
- Tooltip: "Click for details" hint is useful but the click target (graph area
  only) is not obvious.

## TODO

- [x] Phase 1: plasmoid scaffold (`metadata.json` + `main.qml`), verify loads
- [x] Phase 2: D-Bus service (`service/knvtop_service.py`) + QML `PlasmaDBus` bridge
- [x] Phase 3: `Canvas` 5-line graph (GPU util/mem/temp/power + CPU) + `fullRepresentation` hover/click panel
- [x] Phase 3: graceful N/A handling (power cap / ollama / no LLM procs)
- [x] systemd user unit (`knvtop.service`) for the D-Bus service
- [x] Phase 3: custom `ToolTipView.qml` with colored bars (GPU/MEM/PWR/CPU/RAM)
- [x] Phase 3: click-to-expand via `root.expanded` + topmost `MouseArea`
- [ ] Phase 3: cosmetic cleanup (ring gauge overlap, graph height, card text wrap)
- [ ] Phase 4: README + prompt-file sync; optional `config/main.xml`
- [ ] Milestone commits 1–4 pushed to `main` (Gitea `DAE51D/knvtop`)

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