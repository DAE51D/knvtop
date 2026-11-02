---
name: knvtop-install
description: Install or troubleshoot the knvtop KDE Plasma GPU/LLM monitor and its nvstats-service dependency on Linux. Use whenever someone asks an AI agent to set up knvtop, install the plasmoid, or make its model-process cards work.
---

# knvtop install skill

Install the shared telemetry service for the current desktop user, then install the Plasma widget. Never assume a particular username, service account, host, or home directory.

## 1. Install the telemetry service

Follow the [nvstats-service install skill](https://github.com/DAE51D/nvstats-service/blob/main/SKILL.md). It must run as the desktop user on the same host/session as Plasma. Do not run its installer with `sudo`. Cross-user process GPU details are optional and require explicit approval for the dedicated `CAP_SYS_PTRACE` helper.

## 2. Install knvtop

- **Recommended for most users:** install knvtop from the KDE Store using Plasma's widget installer, then add it from the panel's **Add Widgets…** menu.
- **From a source checkout:** install the `com.daevid.knvtop/` directory into `~/.local/share/plasma/plasmoids/` as the desktop user. The directory name must remain `com.daevid.knvtop`.
- Do not edit Plasma's applet configuration file to add the widget. Have the user add it through Plasma's UI.
- Plasma may need to reload plasmashell before it sees newly copied files. Ask before restarting it because that re-instantiates other widgets; otherwise have the user log out/in or restart Plasma when convenient.

## 3. Verify

Confirm `nvstats.service` is active and the session bus owns `com.daevid.nvstats`. Ask the user to add the widget and confirm it displays live GPU/system telemetry. The LLM filter is driven by observed model-serving processes; it is not tied to fixed account names.

The current lightweight process matcher covers llama.cpp, Ollama, vLLM, SGLang, and Hugging Face TGI. It reads Linux process arguments and `/proc` stats; it does not inspect Docker containers or desktop-client APIs. For debugging, do not paste full process samples into chat because command-line arguments can contain private values.

## Uninstall

Remove the plasmoid from Plasma's widget UI, then remove `~/.local/share/plasma/plasmoids/com.daevid.knvtop/` if it was installed from a source checkout. Uninstall nvstats only if the user also wants to remove the shared service; onvtop may use it too.
