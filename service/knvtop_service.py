#!/usr/bin/env python3
"""knvtop D-Bus service.

Runs the poller in a background thread and exposes the latest sample
on the session bus at com.daevid.knvtop / /com/daevid/knvtop.

Interfaces:
  com.daevid.knvtop.Sample
    Get() -> (a{sv})  # {gpu: a{sv}, sys: a{sv}, llm: a{sv}}
  com.daevid.knvtop.Status
    IsAlive() -> (b)
    Restart() -> (b)
  com.daevid.knvtop.Process
    Kill(pid:int) -> (b, s)  # SIGTERM then SIGKILL if needed
"""

import os
import signal
import subprocess
import sys
import threading
import time

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "com.daevid.knvtop", "backend"
    ),
)

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib
from knvtop_poll import (
    gpu_proc_sample,
    gpu_sample,
    llm_sample,
    ollama_ps,
    owning_unit,
    sys_sample,
)

BUS_NAME = "com.daevid.knvtop"
OBJECT_PATH = "/com/daevid/knvtop"
KILL_PATH_PREFIX = "/com/daevid/knvtop/kill"
RESTART_PATH_PREFIX = "/com/daevid/knvtop/restart"


class KnvtopService:
    def __init__(self):
        self._latest = {
            "gpu": {},
            "sys": {},
            "llm": {"llama": [], "ollama": [], "vllm": [], "ollama_models": []},
            "gpu_procs": [],
        }
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = None

    def start(self):
        self._thread = threading.Thread(target=self._poll_loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=3)
            self._thread = None
        self._stop.clear()

    def _poll_loop(self):
        # Current username, so the QML side can decide which processes are
        # killable by this user (only same-user processes can be signaled).
        try:
            import pwd

            current_user = pwd.getpwuid(os.getuid()).pw_name
        except (KeyError, ImportError):
            current_user = os.environ.get("USER", "")
        # Detect passwordless sudo once at startup (cached): if sudo -n
        # works without a password, we can kill any process; otherwise we
        # can only kill same-user processes.
        try:
            r = subprocess.run(
                ["sudo", "-n", "true"],
                capture_output=True,
                timeout=5,
            )
            can_kill_all = r.returncode == 0
            import logging

            logging.warning(
                "knvtop: sudo -n true rc=%d can_kill_all=%s stderr=%s",
                r.returncode,
                can_kill_all,
                r.stderr,
            )
        except Exception as e:
            can_kill_all = False
            import logging

            logging.warning("knvtop: sudo check failed: %s", e)
        while not self._stop.is_set():
            try:
                llm = llm_sample()
                llm["ollama_models"] = ollama_ps() or []
                sample = {
                    "gpu": gpu_sample(),
                    "sys": sys_sample(),
                    "llm": llm,
                    "gpu_procs": gpu_proc_sample(),
                    "current_user": current_user,
                    "can_kill_all": can_kill_all,
                }
                with self._lock:
                    self._latest = sample
            except Exception:
                pass
            self._stop.wait(1.0)

    def get_sample(self):
        with self._lock:
            return {
                k: dict(v) if isinstance(v, dict) else v
                for k, v in self._latest.items()
            }


service = KnvtopService()


def _to_dbus_value(v):
    if v is None:
        return dbus.String("null")
    if isinstance(v, bool):
        return dbus.Boolean(v)
    if isinstance(v, int):
        return dbus.Int64(v)
    if isinstance(v, float):
        return dbus.Double(v)
    return dbus.String(str(v))


def _dict_to_dbus(d):
    return dbus.Dictionary({k: _to_dbus_value(v) for k, v in d.items()}, signature="sv")


def _proc_list_to_dbus(procs):
    out = []
    for p in procs:
        out.append(_dict_to_dbus(p))
    return dbus.Array(out, signature="a{sv}")


def _llm_to_dbus(llm):
    return dbus.Dictionary(
        {
            "llama": _proc_list_to_dbus(llm.get("llama", [])),
            "ollama": _proc_list_to_dbus(llm.get("ollama", [])),
            "vllm": _proc_list_to_dbus(llm.get("vllm", [])),
            "ollama_models": _proc_list_to_dbus(llm.get("ollama_models", [])),
        },
        signature="sv",
    )


class KnvtopDBusObject(dbus.service.Object):
    def __init__(self, bus_name, obj_path):
        bus = dbus.SessionBus()
        super().__init__(bus, obj_path)
        self._bus = bus

    @staticmethod
    def _gone(pid):
        """True once the process has exited (a zombie counts as gone)."""
        try:
            with open("/proc/{}/stat".format(pid)) as f:
                # state is the first field after the ")" that closes comm
                return f.read().rsplit(")", 1)[1].split()[0] == "Z"
        except OSError:
            return True

    @staticmethod
    def _signal(pid, sig):
        """Send sig to pid. Returns (ok, error). Same-user processes are
        signaled directly; anything else goes through passwordless sudo."""
        try:
            os.kill(pid, sig)
            return True, ""
        except ProcessLookupError:
            return True, ""
        except PermissionError:
            pass
        except OSError as e:
            return False, str(e)
        try:
            r = subprocess.run(
                ["sudo", "-n", "kill", "-{}".format(int(sig)), str(pid)],
                capture_output=True,
                text=True,
                timeout=5,
            )
        except (subprocess.TimeoutExpired, OSError) as e:
            return False, str(e)
        if r.returncode == 0:
            return True, ""
        err = r.stderr.strip() or "exit code {}".format(r.returncode)
        if "password" in err.lower() or "not allowed" in err.lower():
            return (
                False,
                "process owned by another user and passwordless sudo is unavailable",
            )
        return False, err

    def _wait_gone(self, pid, seconds):
        for _ in range(int(seconds * 10)):
            if self._gone(pid):
                return True
            time.sleep(0.1)
        return self._gone(pid)

    def _do_kill(self, pid_str):
        """SIGTERM, then SIGKILL if it hasn't exited. Returns (ok, message).
        Blocking (up to ~8s), so only call it off the GLib main loop."""
        pid, why = self._valid_pid(pid_str)
        if why:
            return False, why
        if self._gone(pid):
            return False, "process not found"

        ok, err = self._signal(pid, signal.SIGTERM)
        if not ok:
            return False, "SIGTERM failed: {}".format(err)
        if self._wait_gone(pid, 3):
            return True, ""

        ok, err = self._signal(pid, signal.SIGKILL)
        if not ok:
            return False, "SIGKILL failed: {}".format(err)
        if self._wait_gone(pid, 2):
            return True, ""
        return False, "still alive after SIGKILL"

    @staticmethod
    def _valid_pid(pid_str):
        """(pid, None) for a pid we're willing to act on, else (None, why)."""
        try:
            pid = int(pid_str)
        except (ValueError, TypeError):
            return None, "invalid pid"
        if pid <= 1 or pid == os.getpid():
            return None, f"refusing to act on pid {pid}"
        return pid, None

    def _do_restart(self, pid_str):
        """Restart the systemd service that owns pid. Returns (ok, message).

        The unit is re-resolved from the pid here -- never taken from the
        caller -- so a D-Bus client can only restart a service that really
        contains a process it can see. --no-block queues the restart and
        returns: a model warm-up in ExecStartPost can take minutes, and the
        card simply reappears once the service is back.
        """
        pid, why = self._valid_pid(pid_str)
        if why:
            return False, why
        if self._gone(pid):
            return False, "process not found"
        unit = owning_unit(pid)
        if not unit:
            return False, "not in a restartable systemd service"
        scope, name = unit.split(":", 1)
        if scope == "system":
            cmd = ["sudo", "-n", "systemctl", "restart", "--no-block", name]
        else:
            cmd = ["systemctl", "--user", "restart", "--no-block", name]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        except (subprocess.TimeoutExpired, OSError) as e:
            return False, f"systemctl failed: {e}"
        if r.returncode != 0:
            return False, r.stderr.strip() or f"systemctl exit code {r.returncode}"
        return True, f"restarting {name}"

    @staticmethod
    def _async(fn, pid_str, reply_cb):
        # Kill/restart can take seconds. Doing that on the GLib main loop
        # would stall the 1s Sample.Get polls (and the widget would flash
        # its "not installed" panel), so work in a thread and hand the
        # reply back via the main loop.
        def work():
            try:
                ok, msg = fn(pid_str)
            except Exception as e:
                ok, msg = False, str(e)
            GLib.idle_add(reply_cb, dbus.Boolean(ok), dbus.String(msg))

        threading.Thread(target=work, daemon=True).start()

    def kill_async(self, pid_str, reply_cb):
        self._async(self._do_kill, pid_str, reply_cb)

    def restart_async(self, pid_str, reply_cb):
        self._async(self._do_restart, pid_str, reply_cb)

    @dbus.service.method("com.daevid.knvtop.Sample", in_signature="", out_signature="s")
    def Get(self):
        import json

        s = service.get_sample()
        return dbus.String(json.dumps(s))

    @dbus.service.method("com.daevid.knvtop.Status", in_signature="", out_signature="b")
    def IsAlive(self):
        return True

    @dbus.service.method("com.daevid.knvtop.Status", in_signature="", out_signature="b")
    def Restart(self):
        service.stop()
        service.start()
        return True

    @dbus.service.method(
        "com.daevid.knvtop.Process",
        in_signature="s",
        out_signature="bs",
        async_callbacks=("reply_cb", "error_cb"),
    )
    def Kill(self, pid_str, reply_cb, error_cb):
        self.kill_async(pid_str, reply_cb)


class KnvtopKillObject(dbus.service.FallbackObject):
    """Argument-free kill endpoint for the QML widget.

    Plasma's QML dbusMessage does not deliver method arguments (verified
    against plasma-workspace here: typed or plain, with or without a
    signature, the callee sees zero args). So the PID travels in the object
    path instead: Kill() on /com/daevid/knvtop/kill/<pid>. A FallbackObject
    serves every path under its prefix and tells the method which one.
    """

    def __init__(self, bus, prefix, target):
        super().__init__(bus, prefix)
        self._target = target

    @dbus.service.method(
        "com.daevid.knvtop.Process",
        in_signature="",
        out_signature="bs",
        async_callbacks=("reply_cb", "error_cb"),
        path_keyword="path",
    )
    def Kill(self, reply_cb, error_cb, path=""):
        # path_keyword hands us the full object path; the PID is the last
        # element. _do_kill validates it's a positive integer.
        self._target.kill_async(path.rsplit("/", 1)[-1], reply_cb)


class KnvtopRestartObject(dbus.service.FallbackObject):
    """Restart() on /com/daevid/knvtop/restart/<pid> -- same path-encoded-PID
    scheme as KnvtopKillObject, for the same no-arguments reason."""

    def __init__(self, bus, prefix, target):
        super().__init__(bus, prefix)
        self._target = target

    @dbus.service.method(
        "com.daevid.knvtop.Process",
        in_signature="",
        out_signature="bs",
        async_callbacks=("reply_cb", "error_cb"),
        path_keyword="path",
    )
    def Restart(self, reply_cb, error_cb, path=""):
        self._target.restart_async(path.rsplit("/", 1)[-1], reply_cb)


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    service.start()
    loop = GLib.MainLoop()
    bus = dbus.SessionBus()
    bus_name = dbus.service.BusName(BUS_NAME, bus=bus)
    obj = KnvtopDBusObject(bus_name, OBJECT_PATH)
    # Held in locals so dbus-python keeps the fallback objects registered.
    kill_obj = KnvtopKillObject(bus, KILL_PATH_PREFIX, obj)  # noqa: F841
    restart_obj = KnvtopRestartObject(bus, RESTART_PATH_PREFIX, obj)  # noqa: F841

    def on_signal(signum, frame):
        service.stop()
        loop.quit()

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    loop.run()
    service.stop()


if __name__ == "__main__":
    main()
