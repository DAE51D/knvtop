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
4. `backend/knvtop_poll.py`: 1 Hz loop, one JSON line/line to stdout:
   `{gpu:{util,mem_used,mem_total,temp,power_w,power_cap_w},
     sys:{ram_used,ram_total,swap,loadavg},
     llm:{llama:[...],ollama:[...],vllm:[...]}}`.
   - GPU via `amd-smi metric --json` (subprocess, parse); on failure fall back
     to sysfs (resolve hwmon by `name == "amdgpu"`).
   - RAM/load from `/proc/meminfo`, `/proc/loadavg`.
   - LLM: scan `/proc/*/cmdline` for `llama-server|llama-cli|ollama|vllm`;
     `curl` ollama `/api/ps` (timeout 3 s).
5. `main.qml`: `QProcess` spawns `knvtop_poll.py`,
   `readyReadStandardOutput` → `readLine` → `JSON.parse` → latest sample;
   21-pt ring buffer for the graph; bind detail-panel text.

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

## TODO

- [ ] Phase 1: plasmoid scaffold (`metadata.json` + `main.qml`), verify loads
- [ ] Phase 2: `backend/knvtop_poll.py` + QML `QProcess` JSON-lines bridge
- [ ] Phase 3: `Canvas` 4-line graph + `fullRepresentation` hover/click panel
- [ ] Phase 3: graceful N/A handling (power cap / ollama / no LLM procs)
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