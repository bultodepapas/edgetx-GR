"""Open and visually traverse the real BarPro WidgetSettings dialog."""

import os
import sys

import run as R
from driver import SimuDriver
from modelgen import Screen, write_model


OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "probe_out", "settings")


def capture(driver, name, settle=0.4):
    path = os.path.join(OUT_DIR, name + ".png")
    if not driver.capture(path, settle_s=settle):
        raise RuntimeError("capture timed out: %s" % name)
    print("PASS %s" % name)


def main():
    class Args:
        lua = os.environ.get("GAUGEPRO_LUA", "lua")

    defs, _batches, _t2 = R.cmd_generate(Args())
    bar_rows = defs["bar"].rows
    if len(bar_rows) != 42 or bar_rows[-1]["key"] != "LabelPos":
        raise RuntimeError("Bar settings contract must end at slot 42 LabelPos")
    R.seed_sdcard()
    R.clear_generated_models()
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(R.LOG_PATH), exist_ok=True)
    open(R.LOG_PATH, "wb").close()

    model_file = "model990.yml"
    marker = "GPVKSettings"
    write_model(
        defs, os.path.join(R.SD_DIR, "MODELS", model_file), marker,
        [Screen("Layout1x1", [(0, "bar", {
            "Source": "TX_VOLTAGE", "Scale": "Manual",
            "Min": 0, "Max": 20, "BarPreset": "Theme",
        })])])
    R.set_current_model(model_file)

    driver = SimuDriver(R.SIMU_EXE, R.SD_DIR, R.PIPE_PATH, R.LOG_PATH)
    try:
        driver.start(model_marker=marker)
        capture(driver, "01-home")
        driver.long_enter()
        capture(driver, "02-widget-selected")
        driver.enter()
        capture(driver, "03-widget-menu")
        # Popup menus are touch-native; PAGE_DOWN belongs to main-view page
        # navigation and intentionally does not move this selection.
        driver.tap(400, 283, settle_s=0.8)
        capture(driver, "04-settings-open")
        capture(driver, "05-settings-top", settle=0.2)

        # Drag the scrollable form upward repeatedly until the final BarPro
        # controls (Motion through Name position) are visible.
        for _ in range(7):
            driver.swipe(650, 410, 650, 105, steps=10, step_s=0.025,
                         settle_s=0.12)
        capture(driver, "06-settings-bottom", settle=0.3)
        return 0
    finally:
        driver.stop()


if __name__ == "__main__":
    sys.exit(main())
