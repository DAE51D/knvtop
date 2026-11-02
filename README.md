# knvtop

A KDE Plasma 6 widget that shows nvtop-style GPU telemetry (utilization,
memory, temperature, power, plus CPU%) as a compact multi-line graph in the
panel, expanding into a detail popup with per-process cards for local LLM
inference servers (llama.cpp, Ollama, vLLM, SGLang, and Hugging Face TGI) and — optionally — every
GPU-using process on the system, filterable by user and engine type.

Built for a single AMD APU with unified memory (Strix Halo / Radeon 8060S),
but the process-discovery and GPU-telemetry code is generic AMDGPU/libdrm,
not tied to that specific hardware.

Also available on the [KDE Store](https://store.kde.org/p/2370069/) —
grab the `.plasmoid` there instead of building one yourself if you'd
rather not clone the repo.

## Screenshots

**Hover tooltip** — a quick summary without opening the full popup:

![Hover tooltip](screenshots/tooltip.png)

**Expanded popup** — ring gauges, graph, and per-process cards (model server
flags, Ollama loaded models, or the full generic process list):

![Expanded popup](screenshots/popup-expanded.png)

**Config page** — default line visibility plus the AI/LLM-only/user/type
process filters:

![Config page](screenshots/config-page.png)

## Install

Install the shared D-Bus daemon once by following the instructions in
[nvstats-service](https://github.com/DAE51D/nvstats-service) (from its clone,
run `./install.sh`). This separate daemon is shared by the Plasma widget and
OpenChamber's onvtop extension; neither client needs to be installed to use
the other.

Then, from this repository:

1. Copy the plasmoid into place:
   ```bash
   cp -r com.daevid.knvtop ~/.local/share/plasma/plasmoids/
   ```
2. Restart plasmashell so it picks up the new plasmoid (QML doesn't
   hot-reload): `kquitapp6 plasmashell; nohup plasmashell &`
   (no logout/login needed).
3. Right-click the panel → **Add Widgets…** → search "knvtop" → add it.

For an AI-assisted installation, point your coding agent at the [knvtop install skill](SKILL.md). It covers the shared daemon dependency and Plasma widget setup without assuming a particular Linux username.

## Data sources

- **GPU** (util/mem/temp/power): primary `amd-smi metric --json`; falls back
  to sysfs (`/sys/class/drm/card*/device/gpu_busy_percent` + the hwmon
  resolved by `name == "amdgpu"`, not index, so it survives reboots) if
  `amd-smi` isn't available.
- **System** (RAM/swap/load/CPU%): `/proc/meminfo`, `/proc/loadavg`,
  `/proc/stat` (CPU% is a delta between consecutive samples).
- **LLM processes**: `/proc/*/cmdline` recognizes llama.cpp, Ollama, vLLM,
  SGLang, and Hugging Face TGI launchers; Ollama's loaded-model list comes
  from its `/api/ps` HTTP endpoint. Desktop clients such as VS Code are not
  treated as model processes.
- **Generic GPU process list** (the "AI/LLM processes only" checkbox, off):
  every process's `/proc/<pid>/fdinfo` is scanned for open DRM client file
  descriptors — the same mechanism nvtop itself uses. Which `drm-engine-*`
  keys are present classifies a process as Graphic/Compute; the cumulative
  `drm-engine-*` nanosecond counters, delta'd between samples, give
  per-process GPU%; `drm-memory-*` gives VRAM.

### Killing a process

Each process card has a kill button. The first click arms it ("Kill? Click",
3 seconds); the second click sends SIGTERM, escalating to SIGKILL if the
process is still alive after 3 seconds. Processes owned by your own user are
signaled directly; processes owned by anyone else (e.g. a dedicated
inference-service account) go through `sudo -n kill`, so the button only
appears for them when passwordless sudo works for the service's user. From a
shell you can do the same thing the widget does:

```bash
busctl --user call com.daevid.nvstats /com/daevid/nvstats/kill/<pid> com.daevid.nvstats.Process Kill
# or, with the PID as an argument:
busctl --user call com.daevid.nvstats /com/daevid/nvstats com.daevid.nvstats.Process Kill s <pid>
```

Both return `(bool ok, string message)`; PID 1 and the service itself are
refused.

### Restarting a service

Cards for processes that run inside a **systemd service** (e.g. `llama-server`,
`ollama`) also get a restart button — handy for reloading config files. It
uses the same two-click confirm, then runs `systemctl restart --no-block` on
the service that owns the process (the tooltip names it). The restart is
queued and returns immediately, so a slow start (a model warm-up) just means
the card reappears later. System services need the same passwordless sudo as
killing another user's process; your own user services don't. Processes that
aren't in a service (desktop apps, anything started from a shell) get no
restart button, and session-critical units (kwin, display manager, logind,
`user@`, dbus, nvstats itself) are always refused. From a shell:

```bash
busctl --user call com.daevid.nvstats /com/daevid/nvstats/restart/<pid> com.daevid.nvstats.Process Restart
```

The service works out the unit from the PID itself (via `/proc/<pid>/cgroup`);
it never accepts a unit name from the caller.

### Note: knvtop's MEM line is NOT nvtop's MEM bar

nvtop's GPU memory bar shows VRAM + GTT *heap* size — a few GB on this
hardware. knvtop's MEM line intentionally shows **true GTT usage**
(`used_gtt`/`total_gtt`, ~80 GB on a Strix Halo APU) instead, because on an
APU with unified memory that's the number that actually matters for "how
much room is left for a bigger model." This is a deliberate divergence from
nvtop, not a bug.

## Cross-user GPU stats (per-process GPU%/VRAM showing "N/A")

If you run your LLM server under a **different system account** than the
one this widget's D-Bus service runs as (a common setup — e.g. a dedicated
LLM service account, kept separate from the desktop login), per-process GPU%
and VRAM will read as
`N/A` for that process's card, even though everything else (CPU%, RSS,
CLI flags) works fine.

This isn't a bug — it's the kernel doing its job. `/proc/<pid>/fdinfo`
(needed to read a process's GPU engine/memory usage) is restricted to
**same-uid-or-root**, unlike `/proc/<pid>/stat` and `/proc/<pid>/status`
(world-readable, which is why CPU%/RSS work regardless of who owns the
process).

To close that gap, give the poller service `CAP_SYS_PTRACE` — enough to
read any process's `/proc/<pid>/fdinfo` regardless of owner, without
running the whole service as root. **Don't just `setcap` the system's
shared `python3` binary** — capabilities live on the file itself, so that
would hand `cap_sys_ptrace` to *every* Python script anyone runs on the
machine. Instead, make a dedicated copy and grant it only there:

```bash
sudo mkdir -p /usr/local/lib/nvstats-service
sudo cp "$(readlink -f "$(which python3)")" /usr/local/lib/nvstats-service/python3-ptrace
sudo setcap cap_sys_ptrace+ep /usr/local/lib/nvstats-service/python3-ptrace
```

`nvstats-service`'s user unit already checks for this dedicated
copy and uses it automatically if present, falling back to plain `python3`
(no cross-user GPU%/VRAM, everything else still works) if you skip this
step. After creating the copy, just restart the service:

```bash
systemctl --user restart nvstats.service
```

Why a *copy* and not the real binary: Linux capabilities are stored as an
extended attribute on the file's inode. Copying first gives you an
independent inode, so the capability grant is scoped to exactly this one
service — the system's real `python3` is never touched. (Verify the copy
still works before wiring it in: `/usr/local/lib/nvstats-service/python3-ptrace -c
"import sys; print(sys.prefix)"` should print the normal stdlib prefix, not
an error.)

## Scope

- **In**: single-GPU AMDGPU systems, an LLM-focused default view, an
  optional generic nvtop-style process view (user/type filtered).
- **Out**: multi-GPU, NVIDIA/Intel backends, packaging (`.plasmoid`/deb).

See `.github/prompts/knvtop.prompt.md` for the full design history,
research findings, and implementation learnings.
