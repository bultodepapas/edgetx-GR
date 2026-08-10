"""Gauge Pro visual kit -- CLI entrypoint. See myplans/gaugepro-visual-kit-plan.md.

Usage (from tools/gaugepro-visual-kit, matching this repo's other tools/*.py
invocation style):
  python run.py all
  python run.py generate     # defs+scenes dump, catalog build, model YAML only
  python run.py capture      # boot simu, drive the already-generated batch
"""

import argparse
import itertools
import json
import os
import subprocess
import sys
import time

from defs import Defs
from catalog import (load_scenes, build_track1_screens, batch_by_section,
                      build_track2_screens, SKIPPED_CASES)
from modelgen import Screen, write_model, MAX_CUSTOM_SCREENS
from driver import SimuDriver, CaptureTimeout

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(TOOL_DIR, "..", ".."))
WIDGET_DIR = os.path.join(REPO_ROOT, "WIDGETS", "GaugePro")
RUN_DIR = os.path.join(WIDGET_DIR, "dev", "visual-kit-run")
SD_DIR = os.path.join(RUN_DIR, "sdcard")
PIPE_PATH = os.path.join(RUN_DIR, "pipe.txt")
LOG_PATH = os.path.join(RUN_DIR, "simu.log")
RUNLOG_PATH = os.path.join(RUN_DIR, "run.log.jsonl")

DOCS_DIR = os.path.join(WIDGET_DIR, "docs", "visual-kit")
SHOTS_DIR = os.path.join(DOCS_DIR, "screenshots")

SIMU_EXE = os.path.join(REPO_ROOT, "build", "simu", "simu.exe")

# Theme comparison subset (plan Sec 4.1): stock (no THEMES/ folder needed --
# the compiled-in fallback, selectedTheme reverted to the auto-created
# default's own identity string) plus the two authored GaugeProLab themes.
THEME_STOCK_NAME = "EdgeTX Default"
THEMES = ["stock", "GaugeProLab Light", "GaugeProLab Dark"]
THEME_SECTIONS = {"estado", "color"}

GAUGEPRO_FILES = [
    "main.lua", "app.lua", "options.lua", "theme.lua", "geometry.lua",
    "ranges.lua", "presets.lua", "format.lua", "smoothing.lua",
    "motion.lua", "telemetry.lua", "layout.lua", "renderer.lua",
    "bar_style.lua", "bar_faces.lua", "bar.lua", "alerts.lua",
]

def _copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(src, "rb") as f:
        data = f.read()
    with open(dst, "wb") as f:
        f.write(data)


def seed_sdcard():
    for name in GAUGEPRO_FILES:
        _copy(os.path.join(WIDGET_DIR, name),
              os.path.join(SD_DIR, "WIDGETS", "GaugePro", name))
    _copy(os.path.join(TOOL_DIR, "sd_extra", "WIDGETS", "TeleInject", "main.lua"),
          os.path.join(SD_DIR, "WIDGETS", "TeleInject", "main.lua"))
    _copy(os.path.join(TOOL_DIR, "sd_extra", "SCRIPTS", "gpvk_telemetry.lua"),
          os.path.join(SD_DIR, "SCRIPTS", "gpvk_telemetry.lua"))


def seed_themes():
    for name in ("GaugeProLab Light", "GaugeProLab Dark"):
        _copy(os.path.join(TOOL_DIR, "themes", name, "theme.yml"),
              os.path.join(SD_DIR, "THEMES", name, "theme.yml"))


def _patch_radio_fields(string_fields):
    """Patch one or more RADIO/radio.yml top-level string fields in place.

    REGRESSION FIXED HERE: patching a string field alone corrupted the file
    from the firmware's point of view -- radio.yml carries a `checksum`
    computed over its original content, and editing it without also setting
    `manuallyEdited: 1` (a real escape hatch the schema provides for exactly
    this -- YAML_UNSIGNED("manuallyEdited", 1)) made the next boot reject
    the file outright ("radio settings: Reading failed. File is corrupted"),
    trigger storageEraseAll(), and silently regenerate fresh defaults --
    which is why a `currModelFilename` patch kept reverting to "model1.yml"
    no matter how many times it was written. Every patch now also sets
    manuallyEdited, unquoted (YAML_UNSIGNED, not a string)."""
    path = os.path.join(SD_DIR, "RADIO", "radio.yml")
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    remaining = dict(string_fields)
    manually_edited_found = False
    for i, line in enumerate(lines):
        for field, value in list(remaining.items()):
            if line.startswith(field + ":"):
                lines[i] = '%s: "%s"\n' % (field, value)
                del remaining[field]
        if line.startswith("manuallyEdited:"):
            lines[i] = "manuallyEdited: 1\n"
            manually_edited_found = True
    for field, value in remaining.items():
        lines.append('%s: "%s"\n' % (field, value))
    if not manually_edited_found:
        lines.append("manuallyEdited: 1\n")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(lines)


def set_selected_theme(theme_name):
    """Theme selection is a general-settings field, not a per-model one
    (plan Sec 3), so switching themes means editing this one field and
    restarting, same as switching models."""
    _patch_radio_fields({"selectedTheme": theme_name})


def set_current_model(filename):
    """Patch RADIO/radio.yml's currModelFilename (17-char limit, hal
    dataconstants.h/currModelFilename) -- the ROOT FIX for a real
    regression: repeatedly overwriting the SAME MODELS/model1.yml between
    batches raced the firmware's own periodic autosave, which re-serializes
    the CURRENTLY LOADED model back to its file on a timer independent of
    anything this driver does. If that autosave lands between this driver's
    write and the firmware processing `reset`, it clobbers the freshly
    written batch with a re-save of the model that was already loaded --
    confirmed directly: simu.log showed the SAME model name reloading over
    and over no matter how many times a different batch was written to
    model1.yml and reset. Writing every batch to its OWN never-reused
    filename and switching the ACTIVE one via this field sidesteps the
    clobber entirely: the autosave can only ever stomp the file that is
    already loaded, which this driver is done with by the time it moves on."""
    _patch_radio_fields({"currModelFilename": filename})


def dump_defs_and_scenes(lua_exe="lua"):
    defs_json = os.path.join(TOOL_DIR, "defs.json")
    scenes_json = os.path.join(TOOL_DIR, "scenes.json")
    subprocess.run([lua_exe, os.path.join(TOOL_DIR, "defs_dump.lua"),
                     WIDGET_DIR + os.sep, defs_json], check=True, cwd=WIDGET_DIR)
    subprocess.run([lua_exe, os.path.join(TOOL_DIR, "scenes_dump.lua"),
                     WIDGET_DIR + os.sep, scenes_json], check=True, cwd=WIDGET_DIR)
    return defs_json, scenes_json


class RunLog:
    def __init__(self, path):
        self.path = path
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.rows = []
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        self.rows.append(json.loads(line))

    def drop_sections(self, sections):
        """Remove prior rows for `sections` before a re-run of just those
        sections, so run.log.jsonl never accumulates stale duplicates when
        capture is invoked with --track1-only / --track2-only separately."""
        self.rows = [r for r in self.rows if r.get("section") not in sections]

    def add(self, **kw):
        self.rows.append(kw)

    def flush(self):
        with open(self.path, "w", encoding="utf-8") as f:
            for row in self.rows:
                f.write(json.dumps(row, sort_keys=True))
                f.write("\n")

    def summary(self):
        total = len(self.rows)
        passed = sum(1 for r in self.rows if r["status"] == "PASS")
        failed = sum(1 for r in self.rows if r["status"] == "FAIL")
        warned = sum(1 for r in self.rows if r["status"] == "WARN")
        return {"total": total, "pass": passed, "warn": warned, "fail": failed}


def cmd_generate(args):
    dump_defs_and_scenes(args.lua)
    defs = Defs.load(os.path.join(TOOL_DIR, "defs.json"))
    scenes = load_scenes(os.path.join(TOOL_DIR, "scenes.json"))
    screens = build_track1_screens(scenes, defs)
    batches = batch_by_section(screens)
    print("Track 1: %d screens (%d skipped) in %d model batches"
          % (len(screens), len(SKIPPED_CASES), len(batches)))
    t2 = build_track2_screens()
    print("Track 2: %d layout-gallery screens" % len(t2))
    return defs, batches, t2


def _run_track1(driver, defs, batches, runlog, file_counter, seq_start=1):
    seq = seq_start
    for batch in batches:
        model_name = "GPVK T1 %s" % batch[0].section
        # Unique, never-reused filename per batch -- see driver.py's module
        # docstring for why in-place overwrite of one model1.yml raced the
        # firmware's own periodic autosave. MUST match model<digits>.yml
        # exactly: ModelsList::loadYaml() (storage/modelslist.cpp) only
        # recognizes that pattern when scanning MODELS/ at boot -- any other
        # name is silently skipped, which is why an earlier "t1_01.yml"
        # naming scheme never got found ("ERROR no Current Model Found").
        model_file = "model%d.yml" % next(file_counter)
        model_screens = [Screen(s.layout_id, [(s.zone_index, s.overrides)])
                          for s in batch]
        # Stop BEFORE writing: a live process can autosave-clobber these
        # files mid-write just as easily as it clobbers them mid-reset (see
        # driver.py's module docstring) -- there must be no running process
        # while this driver is the one touching MODELS/*.yml or radio.yml.
        driver.stop()
        write_model(defs, os.path.join(SD_DIR, "MODELS", model_file),
                    model_name, model_screens)
        set_current_model(model_file)
        driver.start(model_marker=model_name)
        for i, s in enumerate(batch):
            fname = "%03d_%s_%s.png" % (seq, s.section, s.name)
            out = os.path.join(SHOTS_DIR, fname)
            t0 = time.time()
            try:
                # First screen of a fresh batch gets extra settle: the
                # occasional race where a capture right after reset() still
                # shows the previous batch's last frame only ever hit this
                # position (empirically observed and root-caused via an
                # isolated repro -- see verify_dupes.py for the follow-up
                # check this doesn't fully rule out).
                settle = 1.5 if i == 0 else 0.5
                ok = driver.capture(out, settle_s=settle)
            except CaptureTimeout as e:
                runlog.add(seq=seq, name=s.name, section=s.section,
                           file=fname, status="FAIL", error=str(e))
                raise
            status = "PASS" if ok else "FAIL"
            runlog.add(seq=seq, name=s.name, section=s.section, file=fname,
                       status=status, ms=int((time.time() - t0) * 1000),
                       overrides={k: v for k, v in s.overrides.items()})
            print(("  [%s] %03d %-10s %s" % (status, seq, s.section, s.name)))
            seq += 1
            if i < len(batch) - 1:
                driver.page_down()
    for name, reason in SKIPPED_CASES.items():
        runlog.add(seq=None, name=name, section="skipped", file=None,
                    status="SKIP", reason=reason)
    return seq


def _run_track2(driver, defs, screens, runlog, file_counter, seq_start):
    seq = seq_start
    model_screens = [Screen(s.layout_id, s.zones, comment=s.title) for s in screens]
    model_file = "model%d.yml" % next(file_counter)
    driver.stop()
    write_model(defs, os.path.join(SD_DIR, "MODELS", model_file),
                "GPVK Layouts", model_screens)
    set_current_model(model_file)
    driver.start(model_marker="GPVK Layouts")
    for i, s in enumerate(screens):
        fname = "%s.png" % s.key
        out = os.path.join(SHOTS_DIR, fname)
        t0 = time.time()
        settle = 1.5 if i == 0 else 0.5
        ok = driver.capture(out, settle_s=settle)
        status = "PASS" if ok else "FAIL"
        runlog.add(seq=seq, name=s.key, section="layouts", file=fname,
                   status=status, ms=int((time.time() - t0) * 1000),
                   layout=s.layout_id, title=s.title)
        print(("  [%s] %s %s (%s)" % (status, s.key, s.title, s.layout_id)))
        seq += 1
        if i < len(screens) - 1:
            driver.page_down()
    return seq


def build_theme_subset(batches, t2):
    """Plan Sec 4.1: the estado + color sections (exercise the DATA-channel
    theme roles alongside Gauge Pro's fixed status colours) plus one layout
    gallery screen and one fullscreen hero, captured under all 3 themes."""
    t1_screens = []
    for batch in batches:
        for s in batch:
            if s.section in THEME_SECTIONS:
                t1_screens.append(s)
    gallery = [s for s in t2 if s.key in ("L05_layout2p3_dial_vs_bar", "L01_fullscreen_bar")]
    return t1_screens, gallery


def _run_theme_subset(driver, defs, t1_screens, gallery, runlog, file_counter, seq_start):
    # LEN_MODEL_NAME is 15 on colorlcd boards (dataconstants.h) -- "GPVK
    # Theme GaugeProLab Dark" would silently truncate, and the marker match
    # would then never see the (untruncated) name it expects. Short,
    # unique-per-(theme,track) codes stay well under that. Filenames must
    # still be model<digits>.yml (see _run_track1's model_file comment).
    THEME_CODE = {"stock": "S", "GaugeProLab Light": "L", "GaugeProLab Dark": "D"}
    seed_themes()
    seq = seq_start
    for theme in THEMES:
        theme_name = THEME_STOCK_NAME if theme == "stock" else theme
        slug = theme.lower().replace(" ", "-")
        code = THEME_CODE[theme]

        # MAX_CUSTOM_SCREENS=10 per model -- t1_screens (estado+color, 14
        # cases) needs 2+ model files, same constraint as Track 1's batches.
        for chunk_start in range(0, len(t1_screens), MAX_CUSTOM_SCREENS):
            chunk = t1_screens[chunk_start:chunk_start + MAX_CUSTOM_SCREENS]
            model_screens = [Screen("Layout1x1", [(0, s.overrides)]) for s in chunk]
            m1_name = "GPVKTh%s1%d" % (code, chunk_start // MAX_CUSTOM_SCREENS)
            m1_file = "model%d.yml" % next(file_counter)
            driver.stop()
            set_selected_theme(theme_name)
            write_model(defs, os.path.join(SD_DIR, "MODELS", m1_file),
                        m1_name, model_screens)
            set_current_model(m1_file)
            driver.start(model_marker=m1_name)
            for i, s in enumerate(chunk):
                fname = "%03d_%s_%s__%s.png" % (seq, s.section, s.name, slug)
                out = os.path.join(SHOTS_DIR, fname)
                ok = driver.capture(out, settle_s=1.5 if i == 0 else 0.5)
                status = "PASS" if ok else "FAIL"
                runlog.add(seq=seq, name=s.name, section="themes", file=fname,
                           status=status, theme=theme, title="%s [%s]" % (s.name, theme))
                print("  [%s] theme=%s %s" % (status, theme, s.name))
                seq += 1
                if i < len(chunk) - 1:
                    driver.page_down()

        model_screens2 = [Screen(s.layout_id, s.zones, comment=s.title) for s in gallery]
        m2_name = "GPVKTh%s2" % code
        m2_file = "model%d.yml" % next(file_counter)
        driver.stop()
        write_model(defs, os.path.join(SD_DIR, "MODELS", m2_file),
                    m2_name, model_screens2)
        set_current_model(m2_file)
        driver.start(model_marker=m2_name)
        for i, s in enumerate(gallery):
            fname = "%s__%s.png" % (s.key, slug)
            out = os.path.join(SHOTS_DIR, fname)
            ok = driver.capture(out, settle_s=1.5 if i == 0 else 0.5)
            status = "PASS" if ok else "FAIL"
            runlog.add(seq=seq, name=s.key, section="themes", file=fname,
                       status=status, theme=theme, title="%s [%s]" % (s.title, theme))
            print("  [%s] theme=%s %s" % (status, theme, s.key))
            seq += 1
            if i < len(gallery) - 1:
                driver.page_down()
    driver.stop()
    set_selected_theme(THEME_STOCK_NAME)
    return seq


def cmd_capture(args, defs, batches, t2):
    os.makedirs(SHOTS_DIR, exist_ok=True)
    seed_sdcard()
    runlog = RunLog(RUNLOG_PATH)

    # model<digits>.yml is a hard firmware requirement (ModelsList::loadYaml,
    # storage/modelslist.cpp) -- start past "model1.yml" (the bootstrap
    # default) and never reuse a number within one run, so every batch's
    # file is untouched by the time this driver moves on (see
    # set_current_model's docstring for why that matters).
    file_counter = itertools.count(2)

    if args.themes_only:
        runlog.drop_sections({"themes"})
        driver = SimuDriver(SIMU_EXE, SD_DIR, PIPE_PATH, LOG_PATH)
        driver.start()
        print("simu started (themes only)")
        try:
            t1_screens, gallery = build_theme_subset(batches, t2)
            _run_theme_subset(driver, defs, t1_screens, gallery, runlog,
                               file_counter, seq_start=1)
        finally:
            driver.stop()
            runlog.flush()
        s = runlog.summary()
        print("\nRESULT: %d total, %d pass, %d warn, %d fail"
              % (s["total"], s["pass"], s["warn"], s["fail"]))
        return 0 if s["fail"] == 0 else 1

    t1_sections = {b[0].section for b in batches}
    if not args.track2_only:
        runlog.drop_sections(t1_sections | {"skipped"})
    if not args.track1_only:
        runlog.drop_sections({"layouts"})

    driver = SimuDriver(SIMU_EXE, SD_DIR, PIPE_PATH, LOG_PATH)
    driver.start()
    print("simu started")
    try:
        seq = 1
        if not args.track2_only:
            seq = _run_track1(driver, defs, batches, runlog, file_counter, seq_start=1)
        if not args.track1_only:
            _run_track2(driver, defs, t2, runlog, file_counter, seq_start=seq)
    finally:
        driver.stop()
        runlog.flush()

    s = runlog.summary()
    print("\nRESULT: %d total, %d pass, %d warn, %d fail"
          % (s["total"], s["pass"], s["warn"], s["fail"]))
    return 0 if s["fail"] == 0 else 1


def cmd_report():
    from report import load_runlog, write_catalog_md, write_index_md, write_run_summary
    rows = load_runlog(RUNLOG_PATH)
    os.makedirs(DOCS_DIR, exist_ok=True)
    write_catalog_md(os.path.join(DOCS_DIR, "CATALOG.md"), rows, SKIPPED_CASES)
    write_index_md(os.path.join(DOCS_DIR, "INDEX.md"), rows)
    write_run_summary(os.path.join(DOCS_DIR, "RUN_SUMMARY.md"), rows)
    print("wrote CATALOG.md, INDEX.md, RUN_SUMMARY.md -> %s" % DOCS_DIR)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["generate", "capture", "report", "all"])
    ap.add_argument("--lua", default="lua")
    ap.add_argument("--track1-only", action="store_true")
    ap.add_argument("--track2-only", action="store_true")
    ap.add_argument("--themes-only", action="store_true")
    args = ap.parse_args()

    if args.action == "report":
        return cmd_report()

    defs, batches, t2 = cmd_generate(args)
    if args.action == "generate":
        return 0
    rc = cmd_capture(args, defs, batches, t2)
    if args.action == "all":
        cmd_report()
    return rc


if __name__ == "__main__":
    sys.exit(main())
