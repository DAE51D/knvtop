# store.kde.org submission — draft copy

Everything else in this file (this line included) is a note to whoever's
filling out the form — do not paste it. Only the text inside the fenced
block under "Full description" is meant to go in the Description field.

The store's Description field does **not** render Markdown — it showed
literal `#`/`##` characters and `**bold**` markers as plain text the
first time this got pasted in wholesale. The block below is plain text on
purpose: no headers, no bold, no markdown of any kind. Safe to copy start
to finish.

## Title

knvtop

## Tagline / short description (one line)

nvtop-style GPU + LLM process monitor for the panel

## Category

Plasma 6 / Widgets (or "Plasma Addons" — whichever the current taxonomy
calls the widget category)

## Tags

gpu, nvtop, monitor, system-monitor, llm, ollama, llama.cpp, amdgpu,
process-monitor, plasmoid

## Full description

Copy everything between the two `---` lines, nothing else:

---
knvtop is a KDE Plasma 6 panel widget that brings nvtop-style GPU
telemetry to your desktop: a live multi-line graph (utilization, memory,
temperature, power, plus CPU%) that expands into a detailed process view
on click.

Two views in one widget. AI/LLM focus (default) recognizes running
llama.cpp, ollama, and vLLM instances and shows each as a card with its
model, CLI flags (sorted, searchable at a glance), and live per-process
GPU%/VRAM/CPU%/memory. Full process view (one checkbox away) shows every
GPU-touching process on the system, nvtop-style, filterable by user and
by engine type (Graphic/Compute/Both).

Built for AMD/AMDGPU: reads the same /proc/<pid>/fdinfo data nvtop
itself uses, plus amd-smi/sysfs for system-wide GPU stats. Tested on an
AMD Strix Halo APU (unified memory) but the process-discovery code isn't
hardware-specific beyond the AMDGPU driver.

Requires a small backend service (a Python D-Bus helper, no other
runtime dependencies) that must be installed and started once via
systemd. The widget shows setup instructions directly in the popup if
it isn't running yet. Full instructions in the README.

Source, issue tracker, and full documentation:
https://github.com/DAE51D/knvtop
---

## Note for whoever submits this

Resolved: Gitea (`gitea.home.lan`, LAN-only) stays the working source of
truth; a push mirror auto-syncs every commit (plus an 8h fallback
interval, same pattern as `strix-halo-power`) to
https://github.com/DAE51D/knvtop, which is what the store listing's
source-link field should point at.

## Screenshots to attach

See `screenshots/` in the repo root (also embedded in README.md):
- `tooltip.png` — the hover tooltip
- `popup-expanded.png` — expanded popup, AI/LLM cards view
- `config-page.png` — the config page (line defaults + process filters)
