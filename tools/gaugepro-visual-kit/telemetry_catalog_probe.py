"""Focused native visual proof for scalar telemetry catalog recovery."""

import os
import sys
import time

import run as R
from catalog import TELEMETRY_SENSORS
from driver import SimuDriver
from modelgen import Screen, write_model


NAMES = {
    "st-stale", "st-nolink", "st-nodata", "op-chip-on", "op-chip-off",
    "sc-preset", "sc-lowgood", "ba-rxbt", "pal-preset-auto",
    "br-lowgood", "br-gradient-lowgood", "f4-auto-rssi", "f5-auto-ch1",
    "ne-damp0", "ne-damp9",
}
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "probe_out", "catalog")


def main():
    class Args:
        lua = os.environ.get("GAUGEPRO_LUA", "lua")

    defs, batches, _t2 = R.cmd_generate(Args())
    screens = [screen for batch in batches for screen in batch
               if screen.name in NAMES]
    missing = NAMES - {screen.name for screen in screens}
    if missing:
        print("FAIL: catalog cases still absent: %s" % ", ".join(sorted(missing)))
        return 1

    R.seed_sdcard()
    R.clear_generated_models()
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(R.LOG_PATH), exist_ok=True)
    open(R.LOG_PATH, "wb").close()
    driver = SimuDriver(R.SIMU_EXE, R.SD_DIR, R.PIPE_PATH, R.LOG_PATH)
    start_at = max(1, int(os.environ.get("GPVK_PROBE_START", "1")))
    only = {name.strip() for name in
            os.environ.get("GPVK_PROBE_ONLY", "").split(",") if name.strip()}
    try:
        for index, screen in enumerate(screens, 1):
            if index < start_at or (only and screen.name not in only):
                continue
            driver.stop()
            pose = screen.telemetry
            driver.set_telemetry(
                pose["values"] if pose else [],
                link=pose["link"] if pose else False,
                feed=pose["feed"] if pose else False,
                rssi=pose["rssi"] if pose else 0)
            marker = "GPVKTP%02d" % index
            model_file = "model%d.yml" % (920 + index)
            model_path = os.path.join(R.SD_DIR, "MODELS", model_file)
            write_model(
                defs, model_path, marker,
                [Screen(screen.layout_id,
                        [(screen.zone_index, screen.family, screen.overrides)])],
                sensors=TELEMETRY_SENSORS)
            R.set_current_model(model_file)
            driver.start(model_marker=marker)
            if pose and pose.get("post"):
                post = pose["post"]
                driver.set_telemetry(post["values"], link=post["link"],
                                     feed=post["feed"], rssi=post["rssi"])
                driver.inject_telemetry(post["values"])
                time.sleep(post["settle"])
            out = os.path.join(OUT_DIR, "%02d_%s.png" % (index, screen.name))
            if not driver.capture(out, settle_s=1.0):
                print("FAIL: capture timed out for %s" % screen.name)
                return 1
            with open(model_path, "r", encoding="utf-8") as f:
                persisted = f.read()
            if "source: NONE" in persisted:
                print("FAIL: source unresolved for %s" % screen.name)
                return 1
            expected_source = None
            if pose:
                source_slots = {
                    sensor["name"]: "tele(%d)" % slot
                    for slot, sensor in enumerate(TELEMETRY_SENSORS)
                }
                expected_source = source_slots[screen.overrides["Source"]]
            elif screen.name == "f5-auto-ch1":
                expected_source = "ch(0)"
            if expected_source and ("source: %s" % expected_source) not in persisted:
                print("FAIL: %s did not persist as %s" %
                      (screen.name, expected_source))
                return 1
            print("PASS %02d/%02d %s" % (index, len(screens), screen.name))
        return 0
    finally:
        driver.stop()


if __name__ == "__main__":
    sys.exit(main())
