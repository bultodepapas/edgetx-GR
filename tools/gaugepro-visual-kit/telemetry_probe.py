"""Minimal native proof for model-declared + Lua-fed telemetry.

Runs one BarPro RSSI/Auto screen through the real model YAML reader, real
SOURCE binding, real telemetry registry and Widget Studio transport hook.
The screenshot is diagnostic only; successful integration moves the same
contract into run.py's catalog pipeline.
"""

import os
import re
import sys

import run as R
from driver import SimuDriver
from modelgen import Screen, write_model

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe_out")
SENSOR = {
    "id": 0x0C00, "subId": 0, "instance": 0,
    "name": "RSSI", "value": 78, "unit": 17, "prec": 0,
}


def main():
    class Args:
        lua = os.environ.get("GAUGEPRO_LUA", "lua")

    defs, _batches, _t2 = R.cmd_generate(Args())
    R.seed_sdcard()
    R.clear_generated_models()
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(R.LOG_PATH), exist_ok=True)
    open(R.LOG_PATH, "wb").close()

    model_file = "model901.yml"
    marker = "GPVKTeleProbe"
    options = {
        "Source": "RSSI", "Scale": "Manual", "Min": 0, "Max": 100,
        "Warn": 55, "Crit": 35, "BarPreset": "Auto", "Damping": 0,
    }
    write_model(
        defs, os.path.join(R.SD_DIR, "MODELS", model_file), marker,
        [Screen("Layout1x1", [(0, "bar", options)])], sensors=[SENSOR])
    R.set_current_model(model_file)

    driver = SimuDriver(R.SIMU_EXE, R.SD_DIR, R.PIPE_PATH, R.LOG_PATH)
    driver.set_telemetry([SENSOR], link=True, feed=True, rssi=78)
    try:
        driver.start(model_marker=marker)
        out = os.path.join(OUT_DIR, "telemetry-rssi-auto.png")
        if not driver.capture(out, settle_s=1.5):
            print("FAIL: capture timed out")
            return 1
        # A valid PNG can still contain the widget's NO SOURCE fallback.
        # EdgeTX auto-saves the decoded model during this boot, so assert the
        # firmware's own persisted SOURCE value rather than trusting capture
        # completion as proof of a successful binding.
        parsed_model = os.path.join(R.SD_DIR, "MODELS", model_file)
        with open(parsed_model, "r", encoding="utf-8") as f:
            persisted = f.read()
        if not re.search(r"\bsource:\s+tele\(0\)\s*$", persisted, re.MULTILINE):
            print("FAIL: firmware did not resolve RSSI to telemetry slot 0")
            return 1
        print("PASS: %s" % out)
        return 0
    finally:
        driver.stop()


if __name__ == "__main__":
    sys.exit(main())
