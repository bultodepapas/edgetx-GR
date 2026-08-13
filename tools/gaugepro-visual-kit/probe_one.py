"""Capture ONE Track 1 case (or a few) through the real simulator.

    python probe_one.py f5-zero-h-blocks-positive [more-case-names...]

Same pipeline as `run.py capture`, restricted to the named cases so a single
diagnosis costs ~10 s instead of a full 214-screen run. Screenshots land in
`probe_out/` and the simulator log in the usual place, so any `print()` a
widget makes is visible there.

Not part of the published catalog: it writes nothing into docs/visual-kit.
"""

import itertools
import os
import sys
import time

import run as R
from driver import SimuDriver
from modelgen import Screen, write_model

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe_out")


def main(names):
    if not names:
        print(__doc__)
        return 2
    os.makedirs(OUT_DIR, exist_ok=True)

    class A:
        lua = os.environ.get("GAUGEPRO_LUA", "lua")
    defs, batches, _t2 = R.cmd_generate(A())

    wanted = []
    for batch in batches:
        for screen in batch:
            if screen.name in names:
                wanted.append(screen)
    if not wanted:
        print("no such case(s): %s" % ", ".join(names))
        return 2

    R.seed_sdcard()
    os.makedirs(os.path.dirname(R.LOG_PATH), exist_ok=True)
    open(R.LOG_PATH, "wb").close()

    counter = itertools.count(900)
    driver = SimuDriver(R.SIMU_EXE, R.SD_DIR, R.PIPE_PATH, R.LOG_PATH)
    driver.start()
    driver.stop()
    R.clear_generated_models()

    try:
        for screen in wanted:
            model_file = "model%d.yml" % next(counter)
            driver.stop()
            telem = screen.telemetry
            driver.set_telemetry(
                telem["values"] if telem else [],
                link=telem["link"] if telem else False,
                feed=telem["feed"] if telem else False,
                rssi=telem["rssi"] if telem else 0)
            write_model(defs,
                        os.path.join(R.SD_DIR, "MODELS", model_file),
                        "GPVK PROBE",
                        [Screen(screen.layout_id,
                                [(screen.zone_index, screen.family,
                                  screen.overrides)])],
                        sensors=R.TELEMETRY_SENSORS)
            R.set_current_model(model_file)
            driver.start(model_marker="GPVK PROBE")
            if telem and telem.get("post"):
                post = telem["post"]
                if post.get("steps"):
                    for step in post["steps"]:
                        driver.inject_telemetry(step)
                        time.sleep(post["settle"])
                else:
                    driver.set_telemetry(post["values"], link=post["link"],
                                         feed=post["feed"], rssi=post["rssi"])
                    driver.inject_telemetry(post["values"])
                    time.sleep(post["settle"])
            out = os.path.join(OUT_DIR, "%s.png" % screen.name)
            t0 = time.time()
            ok = driver.capture(out, settle_s=1.5)
            print("  [%s] %s -> %s (%d ms)"
                  % ("PASS" if ok else "FAIL", screen.name, out,
                     int((time.time() - t0) * 1000)))
    finally:
        driver.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
