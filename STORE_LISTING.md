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

nvtop-style GPU and model-process monitor for the KDE Plasma 6 panel

## Category

Plasma 6 / Widgets (or "Plasma Addons" — whichever the current taxonomy
calls the widget category)

## Tags

gpu, nvtop, monitor, system-monitor, llm, ollama, llama.cpp, vllm, sglang,
tgi, nvstats-service, amdgpu, process-monitor, plasmoid

## Full description

Copy everything between the two `---` lines, nothing else:

---
knvtop is a KDE Plasma 6 panel widget that brings nvtop-style GPU
telemetry to your desktop: a live multi-line graph (utilization, memory,
temperature, power, plus CPU%) that expands into a detailed process view
on click.

Two views in one widget. AI/LLM focus (default) recognizes running
llama.cpp, Ollama, vLLM, SGLang, and Hugging Face TGI model servers and
shows model processes as cards with launch parameters and available live
per-process GPU%/VRAM/CPU%/memory. Full process view (one checkbox away)
shows every GPU-touching process on the system, nvtop-style, filterable by
user and by engine type (Graphic/Compute/Both).

Each process card has a two-click kill button, and a restart button for
processes running inside a systemd service (handy for reloading a
llama.cpp config).

Uses Linux process data and GPU telemetry from the shared nvstats-service.
Tested on an AMD Strix Halo APU with unified memory; nvstats-service also
supports NVIDIA telemetry through nvidia-smi. Per-process GPU counters vary
by GPU and driver.

Requires the separate nvstats-service daemon (a Python D-Bus service) to be
installed once for the current Linux user. It uses the `com.daevid.nvstats`
D-Bus API. The same daemon can serve the
onvtop OpenChamber extension, so users do not need to install both clients.
The widget shows setup instructions directly in the popup if it isn't
running yet. Install instructions: https://github.com/DAE51D/nvstats-service

Version 1.3.0 is a breaking backend update. Version 1.2.0 uses the retired
com.daevid.knvtop D-Bus API; 1.3.0 uses nvstats-service and
com.daevid.nvstats. Upgrade the service and widget together. No compatibility
alias is provided.

Source, issue tracker, and full documentation:
https://github.com/DAE51D/knvtop
---

## Changelog (paste into the "Changelog" field when uploading a release)

1.3.0 — BREAKING BACKEND UPDATE:

---
- BREAKING: knvtop 1.3.0 requires the separate nvstats-service and its
  com.daevid.nvstats D-Bus API. knvtop 1.2.0 uses the retired
  com.daevid.knvtop API. Upgrade the service and widget together; they are
  incompatible, and no legacy D-Bus alias is provided.
- The telemetry daemon is now a shared per-user service that can serve both
  the Plasma widget and OpenChamber's onvtop extension. The widget no longer
  bundles or owns a poller.
- Adds process-card detection for SGLang and Hugging Face TGI and improves
  vLLM launch-form detection.
---

(1.2.0 added kill/restart controls; 1.1.1 fixed GPU vs process memory
statistics; 1.1.0 added NVIDIA support.)

## Note for whoever submits this

The source-link field should point to the public repository:
https://github.com/DAE51D/knvtop

## Screenshots to attach

See `screenshots/` in the repo root (also embedded in README.md):
- `tooltip.png` — the hover tooltip
- `popup-expanded.png` — expanded popup, AI/LLM cards view
- `config-page.png` — the config page (line defaults + process filters)
