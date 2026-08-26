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
"""

import os
import signal
import sys
import threading

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "com.daevid.knvtop", "backend"
    ),
)
from knvtop_poll import gpu_sample, sys_sample, llm_sample, ollama_ps

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BUS_NAME = "com.daevid.knvtop"
OBJECT_PATH = "/com/daevid/knvtop"


class KnvtopService:
    def __init__(self):
        self._latest = {
            "gpu": {},
            "sys": {},
            "llm": {"llama": [], "ollama": [], "vllm": [], "ollama_models": []},
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
        while not self._stop.is_set():
            try:
                llm = llm_sample()
                llm["ollama_models"] = ollama_ps() or []
                sample = {"gpu": gpu_sample(), "sys": sys_sample(), "llm": llm}
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


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    service.start()
    loop = GLib.MainLoop()
    bus = dbus.SessionBus()
    bus_name = dbus.service.BusName(BUS_NAME, bus=bus)
    obj = KnvtopDBusObject(bus_name, OBJECT_PATH)

    def on_signal(signum, frame):
        service.stop()
        loop.quit()

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    loop.run()
    service.stop()


if __name__ == "__main__":
    main()
