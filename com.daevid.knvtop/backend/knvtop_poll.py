#!/usr/bin/env python3
"""knvtop telemetry poller.

Emits one JSON object per line on stdout, once per second:

    {
      "gpu": {"util": int|None, "mem_used": int|None, "mem_total": int|None,
              "temp": float|None, "power_w": float|None, "power_cap_w": float|None},
      "sys": {"ram_used": int, "ram_total": int, "swap_used": int,
              "swap_total": int, "load1": float, "load5": float, "load15": float},
      "llm": {"llama": [ {...}, ... ], "ollama": [ {...}, ... ], "vllm": [ {...} ]},
      "gpu_procs": [ {pid, user, name, cmdline, argv, type: [...], gpu_pct, vram_kb}, ... ]
    }

GPU source: `amd-smi metric --json` (one-shot). On failure, fall back to
sysfs: /sys/class/drm/card*/device/gpu_busy_percent and the hwmon whose
name == "amdgpu" (resolved by name, not index, so it survives reboots).
Missing values are null (QML renders N/A).
"""

import json
import os
import pwd
import re
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


def _nvidia_smi():
    # nvidia-smi CSV, noheader/nounits: util %, VRAM MiB, VRAM MiB, temp C,
    # power W, power limit W. "N/A" for any unavailable field (e.g. power
    # limit on some cards) -- treat as None, same convention as _amd_smi().
    try:
        out = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=utilization.gpu,memory.used,memory.total,"
                "temperature.gpu,power.draw,power.limit",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout
        fields = [f.strip() for f in out.strip().split(",")]
        if len(fields) < 6:
            return None

        def num(s):
            try:
                v = float(s)
            except ValueError:
                return None
            return int(v) if v == int(v) else v

        return {
            "util": num(fields[0]),
            "mem_used": num(fields[1]),
            "mem_total": num(fields[2]),
            "temp": num(fields[3]),
            "power_w": num(fields[4]),
            "power_cap_w": num(fields[5]),
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
        g = _nvidia_smi()
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


def _is_ollama_owned(argv):
    """Ollama bundles its own llama-server binary (e.g.
    /usr/local/lib/ollama/llama-server) and launches one per loaded model.
    Those are implementation detail of the ollama section, not a separate
    standalone llama.cpp instance the user started themselves — skip them
    here so they don't show up as a phantom duplicate "llama.cpp" card."""
    return "ollama" in argv[0].split("/")[:-1]


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
        exe = os.path.basename(argv[0])
        if exe.startswith("llama") and _is_ollama_owned(argv):
            continue
        st = _proc_status(pid, {"Name", "VmRSS", "Threads"})
        clean_argv = [a for a in argv if a]
        entry = {
            "pid": int(pid),
            "name": st.get("Name", os.path.basename(argv[0])),
            "cmdline": " ".join(clean_argv),
            # Full argv (not just the flattened cmdline string) so the UI can
            # pair each flag with its own value unambiguously -- a value
            # containing spaces (e.g. a JSON flag argument) is one argv
            # element but would be impossible to re-split correctly out of
            # the joined "cmdline" string alone.
            "argv": clean_argv,
            "rss_kb": int(st["VmRSS"].split()[0])
            if "VmRSS" in st and st["VmRSS"].split()
            else None,
            "threads": int(st["Threads"]) if st.get("Threads", "").isdigit() else None,
            "cpu_pct": _proc_cpu_pct(pid),
        }
        gpu_stats = _fdinfo_gpu_stats(pid)
        entry["gpu_pct"] = gpu_stats["gpu_pct"] if gpu_stats else None
        entry["vram_kb"] = gpu_stats["vram_kb"] if gpu_stats else None
        # user/type so the config page's User/Type filters can apply to
        # these cards too, not just the generic gpu_procs list.
        entry["type"] = gpu_stats["types"] if gpu_stats else []
        entry["user"] = _username(pid) or "?"
        entry["unit"] = owning_unit(pid)
        if exe.startswith("llama"):
            # llama-server/llama-cli use --model; llama-bench uses -m
            entry["model"] = _find("--model", argv) or _find("-m", argv)
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


_prev_gpu_engines = {}  # pid -> {"time": monotonic, "engines": {name: ns}}


def _fdinfo_engines(pid):
    """Aggregate DRM fdinfo (drm-engine-*/drm-memory-*) across all of this
    pid's open DRM client fds, or None if it has none (not a GPU client).

    /proc/<pid>/fdinfo/* is only readable by that pid's own owner (or root)
    -- unlike /proc/<pid>/cmdline, which is world-readable. Since this
    poller runs as an unprivileged user, GPU-using processes owned by a
    *different* user (e.g. a service running under its own system account)
    are invisible to this generic scan and silently skipped, even though
    the same process would still show up in llm_sample() above (which only
    needs the world-readable cmdline). This is a real limitation, not a
    bug -- there's no way around it without running privileged."""
    fd_dir = f"/proc/{pid}/fdinfo"
    try:
        fds = os.listdir(fd_dir)
    except OSError:
        return None
    engines, mem, found = {}, {}, False
    seen_clients = set()
    for fd in fds:
        try:
            with open(f"{fd_dir}/{fd}") as f:
                content = f.read()
        except OSError:
            continue
        if "drm-driver" not in content:
            continue
        # A process can have multiple DRM fds referring to the same client.
        # fdinfo reports the client's complete allocation/counters on each
        # such fd, so summing them would double-count memory and engine time
        # (llama-server commonly has two amdgpu fds).  Deduplicate by the
        # kernel DRM client id; fall back to the fd when older drivers omit it.
        client_id = next(
            (
                line.split(":", 1)[1].strip()
                for line in content.splitlines()
                if line.startswith("drm-client-id:")
            ),
            fd,
        )
        if client_id in seen_clients:
            continue
        seen_clients.add(client_id)
        found = True
        for line in content.splitlines():
            if ":" not in line:
                continue
            k, _, v = line.partition(":")
            k, v = k.strip(), v.strip().split()
            if not v:
                continue
            if k.startswith("drm-engine-"):
                try:
                    engines[k[len("drm-engine-") :]] = engines.get(
                        k[len("drm-engine-") :], 0
                    ) + int(v[0])
                except ValueError:
                    pass
            elif k.startswith("drm-memory-"):
                try:
                    mem[k[len("drm-memory-") :]] = mem.get(
                        k[len("drm-memory-") :], 0
                    ) + int(v[0])
                except ValueError:
                    pass
    return {"engines": engines, "mem": mem} if found else None


def _gpu_engine_pct(pid, engines):
    """% busy per engine since the last sample (nvtop's own approach:
    delta of the cumulative ns counter / elapsed wall time). None on a
    process's first-ever sample (no baseline yet), matching _cpu_sample()."""
    now = time.monotonic()
    prev = _prev_gpu_engines.get(pid)
    _prev_gpu_engines[pid] = {"time": now, "engines": dict(engines)}
    if prev is None:
        return None
    dt = now - prev["time"]
    if dt <= 0:
        return None
    pct = {}
    for name, ns in engines.items():
        d_ns = max(0, ns - prev["engines"].get(name, ns))
        pct[name] = round(min(100.0, d_ns / (dt * 1e9) * 100.0), 1)
    return pct


def _username(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("Uid:"):
                    return pwd.getpwuid(int(line.split()[1])).pw_name
    except (OSError, ValueError, KeyError):
        pass
    return None


# Units whose restart would take the desktop session or this monitor down.
_UNIT_DENY = re.compile(
    r"^(sddm|gdm|lightdm|display-manager|systemd-logind|dbus|knvtop)\b"
    r"|kwin|^user@|^user-runtime-dir@|^session-"
)
_UNIT_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:_.@\-]*\.service$")


def owning_unit(pid):
    """The systemd *service* that owns pid, as "system:<name>" or
    "user:<name>", or None when pid isn't in a restartable service (desktop
    app scopes, another user's session units, anything on the deny list).

    Read from /proc/<pid>/cgroup, which is world-readable, so this needs no
    privileges. The name is validated so it is safe to hand to systemctl.
    """
    try:
        with open(f"/proc/{pid}/cgroup") as f:
            path = next(
                (line.split(":", 2)[2].strip() for line in f if line.startswith("0::")),
                "",
            )
    except (OSError, IndexError):
        return None
    comps = [c for c in path.split("/") if c]
    scope = name = None
    if comps and comps[0] == "system.slice":
        scope = "system"
        name = next((c for c in comps[1:] if c.endswith(".service")), None)
    else:
        # .../user@<uid>.service/<slice>/<unit>.service -- the unit is the
        # first .service *after* this user's manager, and only our own
        # user's units are ours to restart.
        manager = f"user@{os.getuid()}.service"
        if manager in comps:
            scope = "user"
            rest = comps[comps.index(manager) + 1 :]
            name = next((c for c in rest if c.endswith(".service")), None)
    if not name or not _UNIT_NAME.match(name) or _UNIT_DENY.search(name):
        return None
    return f"{scope}:{name}"


def _fdinfo_gpu_stats(pid):
    """{'gpu_pct': float|None, 'vram_kb': int|None, 'types': [...]} for one
    pid, or None if it has no open DRM client fd (not a GPU client).
    Shared by gpu_proc_sample() (every GPU process) and llm_sample() (so
    llama.cpp/ollama/vllm cards can show their own live GPU load/memory,
    not just the system-wide totals)."""
    fdinfo = _fdinfo_engines(pid)
    if fdinfo is None:
        return None
    # A DRM client fd with no drm-engine-* key yet is still a real GPU
    # client (nvtop shows these too, e.g. systemd-logind/init holding a
    # DRM master fd for VT handoff with no measurable engine time) --
    # only "no DRM fd at all" should exclude a process, not "idle so far".
    pct = _gpu_engine_pct(int(pid), fdinfo["engines"]) or {}
    types = []
    if "gfx" in fdinfo["engines"]:
        types.append("graphic")
    if "compute" in fdinfo["engines"]:
        types.append("compute")
    if not types:
        types.append("other")  # decode/encode-only (e.g. video playback)
    return {
        "gpu_pct": round(sum(pct.values()), 1) if pct else None,
        "vram_kb": sum(fdinfo["mem"].values()) or None,
        "types": types,
    }


_prev_proc_cpu = {}  # pid -> {"time": monotonic, "ticks": utime+stime}


def _proc_cpu_pct(pid):
    """Per-process CPU%, same delta-of-a-cumulative-counter approach as
    _cpu_sample()/_gpu_engine_pct() -- None on a process's first sample."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            content = f.read()
    except OSError:
        return None
    # comm (field 2) is parenthesized and can itself contain spaces/parens,
    # so split after the LAST ')' rather than just splitting on whitespace.
    rest = content.rsplit(")", 1)[-1].split()
    try:
        ticks = int(rest[11]) + int(rest[12])  # utime + stime
    except (IndexError, ValueError):
        return None
    now = time.monotonic()
    key = int(pid)
    prev = _prev_proc_cpu.get(key)
    _prev_proc_cpu[key] = {"time": now, "ticks": ticks}
    if prev is None:
        return None
    dt = now - prev["time"]
    if dt <= 0:
        return None
    hz = os.sysconf("SC_CLK_TCK")
    d_ticks = max(0, ticks - prev["ticks"])
    # Multi-threaded processes can exceed 100% (e.g. 2 full cores = 200%),
    # same convention as `top`/`ps` -- just sanity-clamp to the core count.
    return round(min(100.0 * os.cpu_count(), d_ticks / hz / dt * 100.0), 1)


def gpu_proc_sample():
    """Every process with an open DRM client fd on the GPU -- the generic,
    nvtop-style process list (as opposed to llm_sample()'s LLM-only view).
    See _fdinfo_engines() for the same-user visibility caveat."""
    procs = []
    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        pids = []
    alive = set()
    for pid_s in pids:
        stats = _fdinfo_gpu_stats(pid_s)
        if stats is None:
            continue
        argv = [a for a in (_proc_cmdline(pid_s) or []) if a]
        if not argv:
            continue
        alive.add(int(pid_s))
        # Name from /proc/status, not argv[0] -- some processes (observed:
        # Chromium/Electron GPU helpers) rewrite their own argv into one
        # long descriptive blob for `ps` display, which makes a poor "name".
        st = _proc_status(pid_s, {"Name", "VmRSS"})
        name = st.get("Name") or os.path.basename(argv[0])
        procs.append(
            {
                "pid": int(pid_s),
                "user": _username(pid_s) or "?",
                "unit": owning_unit(pid_s),
                "name": name,
                "cmdline": " ".join(argv),
                "argv": argv,
                "type": stats["types"],
                "gpu_pct": stats["gpu_pct"],
                "vram_kb": stats["vram_kb"],
                "cpu_pct": _proc_cpu_pct(pid_s),
                "rss_kb": int(st["VmRSS"].split()[0])
                if "VmRSS" in st and st["VmRSS"].split()
                else None,
            }
        )
    # Drop tracking state for pids that no longer exist so this dict
    # doesn't grow without bound across a long-running poller session.
    for tracked in list(_prev_gpu_engines.keys()):
        if tracked not in alive:
            del _prev_gpu_engines[tracked]
    return procs


def main():
    while True:
        try:
            llm = llm_sample()
            llm["ollama_models"] = ollama_ps() or []
            sample = {
                "gpu": gpu_sample(),
                "sys": sys_sample(),
                "llm": llm,
                "gpu_procs": gpu_proc_sample(),
            }
        except Exception:
            sample = {
                "gpu": {},
                "sys": {},
                "llm": {"llama": [], "ollama": [], "vllm": [], "ollama_models": []},
                "gpu_procs": [],
            }
        try:
            sys.stdout.write(json.dumps(sample) + "\n")
            sys.stdout.flush()
        except BrokenPipeError:
            return
        time.sleep(1.0)


if __name__ == "__main__":
    main()
