#!/usr/bin/env python3
"""knvtop telemetry poller.

Emits one JSON object per line on stdout, once per second:

    {
      "gpu": {"util": int|None, "mem_used": int|None, "mem_total": int|None,
              "temp": float|None, "power_w": float|None, "power_cap_w": float|None},
      "sys": {"ram_used": int, "ram_total": int, "swap_used": int,
              "swap_total": int, "load1": float, "load5": float, "load15": float},
      "llm": {"llama": [ {...}, ... ], "ollama": [ {...}, ... ], "vllm": [ {...} ]}
    }

GPU source: `amd-smi metric --json` (one-shot). On failure, fall back to
sysfs: /sys/class/drm/card*/device/gpu_busy_percent and the hwmon whose
name == "amdgpu" (resolved by name, not index, so it survives reboots).
Missing values are null (QML renders N/A).
"""

import json
import os
import subprocess
import sys
import time

HWMON_GLOB = "/sys/class/hwmon/hwmon*"
DRM_GLOB = "/sys/class/drm/card*/device/gpu_busy_percent"


def _read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def _read_float(path):
    try:
        with open(path) as f:
            return float(f.read().strip())
    except (OSError, ValueError):
        return None


def _amd_smi():
    try:
        out = subprocess.run(
            ["amd-smi", "metric", "--json"],
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout
        d = json.loads(out)["gpu_data"][0]
        g = d.get("usage", {}).get("gfx_activity", {})
        m = d.get("mem_usage", {})
        t = d.get("temperature", {})
        p = d.get("power", {})

        def val(dct):
            v = dct.get("value") if isinstance(dct, dict) else None
            return v if isinstance(v, (int, float)) else None

        return {
            "util": val(g),
            "mem_used": val(m.get("used_gtt")),
            "mem_total": val(m.get("total_gtt")),
            "temp": val(t.get("apu_temperature_gfx")) or val(t.get("edge")),
            "power_w": val(p.get("socket_power"))
            or val(p.get("apu_average_gfx_power")),
            "power_cap_w": None,  # amd-smi does not expose the cap; try sysfs
        }
    except Exception:
        return None


def _amdgpu_hwmon():
    import glob

    for hw in sorted(glob.glob(HWMON_GLOB)):
        try:
            if open(hw + "/name").read().strip() != "amdgpu":
                continue
        except OSError:
            continue
        return hw
    return None


def _sysfs_gpu():
    import glob

    util = None
    for path in sorted(glob.glob(DRM_GLOB)):
        v = _read_int(path)
        if v is not None:
            util = v
            break

    temp = None
    power_w = None
    power_cap_w = None
    hw = _amdgpu_hwmon()
    if hw:
        t = _read_int(hw + "/temp1_input")
        if t is not None:
            temp = t / 1000.0
        pw = _read_int(hw + "/power1_input")
        if pw is not None:
            power_w = pw / 1e6
        cap = _read_int(hw + "/power1_cap")
        if cap is not None:
            power_cap_w = cap / 1e6
    return {
        "util": util,
        "mem_used": None,
        "mem_total": None,
        "temp": temp,
        "power_w": power_w,
        "power_cap_w": power_cap_w,
    }


def gpu_sample():
    g = _amd_smi()
    if g is None:
        g = _sysfs_gpu()
    if g.get("power_cap_w") is None:
        # amd-smi has no cap; try sysfs hwmon power1_cap
        hw = _amdgpu_hwmon()
        if hw:
            cap = _read_int(hw + "/power1_cap")
            if cap is not None:
                g["power_cap_w"] = cap / 1e6
    return g


_prev_cpu = None


def _cpu_sample():
    global _prev_cpu
    try:
        with open("/proc/stat") as f:
            parts = f.readline().split()
    except OSError:
        return None
    vals = [int(x) for x in parts[1:]]
    idle = vals[3] + vals[4]
    total = sum(vals)
    if _prev_cpu is None:
        _prev_cpu = (idle, total)
        return None
    d_idle = idle - _prev_cpu[0]
    d_total = total - _prev_cpu[1]
    _prev_cpu = (idle, total)
    if d_total <= 0:
        return None
    return round((1.0 - d_idle / d_total) * 100.0, 1)


def sys_sample():
    mi = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                k, _, rest = line.partition(":")
                mi[k.strip()] = int(rest.strip().split()[0])  # kB
    except OSError:
        pass
    ram_total = mi.get("MemTotal", 0)
    ram_used = ram_total - mi.get("MemAvailable", ram_total)
    swap_total = mi.get("SwapTotal", 0)
    swap_used = swap_total - mi.get("SwapFree", 0)
    load1 = load5 = load15 = 0.0
    try:
        with open("/proc/loadavg") as f:
            parts = f.read().split()
        load1, load5, load15 = (float(parts[0]), float(parts[1]), float(parts[2]))
    except (OSError, ValueError, IndexError):
        pass
    return {
        "ram_used": ram_used * 1024,
        "ram_total": ram_total * 1024,
        "swap_used": swap_used * 1024,
        "swap_total": swap_total * 1024,
        "load1": load1,
        "load5": load5,
        "load15": load15,
        "cpu": _cpu_sample(),
    }


def _proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().decode(errors="replace").split("\0")
    except OSError:
        return None


def _proc_status(pid, keys):
    out = {}
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                k, _, rest = line.partition(":")
                if k.strip() in keys:
                    out[k.strip()] = rest.strip()
    except OSError:
        pass
    return out


def _find(name, argv):
    """Return argv value for --name or -name (if present), else None."""
    for i, a in enumerate(argv):
        if a == name and i + 1 < len(argv):
            return argv[i + 1]
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return None


def _is_llm(argv):
    if not argv:
        return False
    exe = os.path.basename(argv[0])
    return (
        exe in ("llama-server", "llama-cli", "llama-bench", "ollama", "vllm")
        or "vllm" in argv[0]
    )


def llm_sample():
    llama, ollama, vllm = [], [], []
    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        pids = []
    for pid in pids:
        argv = _proc_cmdline(pid)
        if argv is None or not _is_llm(argv):
            continue
        st = _proc_status(pid, {"Name", "VmRSS", "Threads"})
        entry = {
            "pid": int(pid),
            "name": st.get("Name", os.path.basename(argv[0])),
            "cmdline": " ".join(a for a in argv if a),
            "rss_kb": int(st["VmRSS"].split()[0])
            if "VmRSS" in st and st["VmRSS"].split()
            else None,
            "threads": int(st["Threads"]) if st.get("Threads", "").isdigit() else None,
        }
        exe = os.path.basename(argv[0])
        if exe.startswith("llama"):
            entry["model"] = _find("--model", argv)
            entry["ngl"] = _find("--n-gpu-layers", argv)
            entry["ctx"] = _find("--ctx-size", argv)
            entry["parallel"] = _find("--parallel", argv)
            entry["alias"] = _find("--alias", argv)
            entry["port"] = _find("--port", argv)
            llama.append(entry)
        elif exe == "ollama":
            entry["subcmd"] = argv[1] if len(argv) > 1 else None
            entry["port"] = _find("--port", argv)
            ollama.append(entry)
        elif "vllm" in exe or "vllm" in argv[0]:
            entry["model"] = _find("--model", argv) or (
                argv[1] if len(argv) > 1 and not argv[1].startswith("-") else None
            )
            entry["port"] = _find("--port", argv)
            vllm.append(entry)
    return {"llama": llama, "ollama": ollama, "vllm": vllm}


def ollama_ps():
    try:
        out = subprocess.run(
            ["curl", "-s", "--max-time", "3", "http://127.0.0.1:11434/api/ps"],
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout
        models = json.loads(out).get("models", [])
        return [
            {
                "name": m.get("name"),
                "model": m.get("model"),
                "size_vram": m.get("size_vram"),
                "size": m.get("size"),
                "quantization": (m.get("details") or {}).get("quantization_level"),
                "parameter_size": (m.get("details") or {}).get("parameter_size"),
                "expires_at": m.get("expires_at"),
            }
            for m in models
        ]
    except Exception:
        return None


def main():
    while True:
        try:
            llm = llm_sample()
            llm["ollama_models"] = ollama_ps() or []
            sample = {"gpu": gpu_sample(), "sys": sys_sample(), "llm": llm}
        except Exception:
            sample = {
                "gpu": {},
                "sys": {},
                "llm": {"llama": [], "ollama": [], "vllm": [], "ollama_models": []},
            }
        try:
            sys.stdout.write(json.dumps(sample) + "\n")
            sys.stdout.flush()
        except BrokenPipeError:
            return
        time.sleep(1.0)


if __name__ == "__main__":
    main()
