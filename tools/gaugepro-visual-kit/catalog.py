"""Track 1 (single-widget, ported from dev/scenes.lua) and Track 2 (layout
galleries) screen catalogs -- see myplans/gaugepro-visual-kit-plan.md Sec 4.

TELEMETRY SCOPE NOTE (read before touching source handling below): dynamic
sensor injection (setTelemetryValue) needs a matching `telemetrySensors[]`
entry pre-declared in the model YAML for the Source option's name string to
resolve at all (confirmed empirically: without one, the widget shows "NO
SOURCE" even though the sensor gets registered correctly at runtime -- the
Source option binds to a name at model-load time, before any Lua has run).
A follow-up session attempted this: the struct_TelemetrySensor union
encoding (radio/src/storage/yaml/yaml_datastructs_tx16smk3.cpp) was decoded
(type=TYPE_CUSTOM selects id="<16-bit>" for the id1 union, instance=
"<8-bit>" for id2, and custom={ratio,offset} for cfg when unit is below
UNIT_FIRST_VIRTUAL; ratio=0 skips the linear transform in
TelemetrySensor::getValue entirely -- telemetry_sensors.cpp:717-739) and a
hand-written `telemetrySensors:` block DID load without a parse error
(confirmed via the model-load marker), but the captured screen showed the
radio's setup/decoration chrome instead of the Gauge Pro home view, with no
error in simu's log to explain why. Root cause not found within a bounded
follow-up effort -- still deferred. This pass uses the one proven,
zero-setup real source -- TX_VOLTAGE, already confirmed live and stable --
for every scalar case, via a linear remap (see voltage_window()) that
preserves each case's *relative* value/threshold positions (so colour
bands, markers and sweep angles are still exercised correctly) even though
the literal displayed number is no longer the scene's original one.
CELLS-aggregation cases (`bateria` section, 7 cases) genuinely need a real
multi-instance sensor and are skipped, listed explicitly in SKIPPED_CASES
with the reason.
"""

import json

from defs import Defs
import layouts

SCREEN_W, SCREEN_H = 480, 272
MAX_CUSTOM_SCREENS = 10

# Empirically observed, deterministic (raw-ADC-independent, see catalog.py's
# module docstring investigation): TX_VOLTAGE reads ~7.9 on every boot of
# this simu build with no calibration changes.
V0 = 7.9
WINDOW = 20.0

# Cases skipped in this pass because they need a controllable/injectable
# source (real telemetry sensor registration, deferred per the module
# docstring) and can't be honestly reproduced with the fixed, always-live
# TX_VOLTAGE substitution:
SKIPPED_CASES = {
    "ba-cels-low": "CELLS aggregation needs a real multi-instance telemetry sensor",
    "ba-cels-tot": "same as ba-cels-low",
    "ba-cels-avg": "same as ba-cels-low",
    "ba-pct-low": "same as ba-cels-low",
    "ba-pct-tot": "same as ba-cels-low",
    "ba-liion": "same as ba-cels-low",
    "ba-rxbt": "needs a registered RxBt sensor with min/max history siblings",
    "tx-timer": "timer-typed source display is a distinct code path, not exercised by TX_VOLTAGE",
    "st-stale": "needs a source that can stop updating on command; TX_VOLTAGE is always live",
    "st-nolink": "same as st-stale",
    "st-nodata": "same as st-stale",
    "op-chip-on": "same as st-stale (chip-on scene specifically needs a no-link state)",
    "op-chip-off": "same as st-stale",
    "ne-damp0": "needs a source whose value can step on command; TX_VOLTAGE is fixed",
    "ne-damp9": "same as ne-damp0",
    "br-desc-history": "same as ne-damp0",
}


def voltage_window(min_, max_, warn, crit, value, v0=V0, window=WINDOW):
    """Linear remap placing `value` at v0 and scaling min_/max_/warn_/crit_
    around it, preserving direction (ascending/descending scales both work,
    matching sc-descending's own supported-on-purpose semantics) and every
    threshold's *relative* position. Returns (min, max, warn, crit) as ints
    (the wire format is Signed/integer -- see defs.py)."""
    span = max_ - min_
    if span == 0:
        span = 1
    a = window / span
    b = v0 - a * value
    f = lambda x: a * x + b
    return (round(f(min_)), round(f(max_)), round(f(warn)), round(f(crit)))


def _effective_range(overrides, defs: Defs):
    """(min, max, warn, crit) after applying a case's overrides on top of
    DEFS defaults -- needed before build_options() so voltage_window() can
    remap them consistently."""
    def get(key):
        row = defs.by_key[key]
        if key in overrides:
            return overrides[key]
        return row["default"]
    return get("Min"), get("Max"), get("Warn"), get("Crit")


def track1_gauge_options(case, defs: Defs):
    """Readable option-override dict for one scenes.json case, ready for
    Defs.build_options(). Always sets Source=TX_VOLTAGE (see module
    docstring) and folds the case's value/thresholds through voltage_window
    so the rendered state (band/markers/sweep) matches the original intent.

    Scale defaults to "Manual" (DEFS' own default is "Auto", which makes the
    widget derive Min/Max from the SOURCE's own preset table and ignore the
    configured Min/Max entirely -- confirmed by a real regression: every
    case that didn't explicitly set Scale="Manual" rendered the exact same
    generic TX_VOLTAGE auto-range regardless of voltage_window's output).
    A case's own `opts` can still override this back to "Auto" if it wants
    to (rare, and moot for TX_VOLTAGE, which has no dedicated preset)."""
    overrides = {"Scale": "Manual"}
    overrides.update(case.get("opts") or {})
    overrides["Source"] = "TX_VOLTAGE"

    if case.get("noSource"):
        overrides["Source"] = "NONE"
        return overrides

    min_, max_, warn, crit = _effective_range(overrides, defs)
    value = case.get("value")
    if isinstance(value, list):
        value = sum(value) / len(value)  # pre-CELLS-support approximation
    if value is None:
        return overrides

    nmin, nmax, nwarn, ncrit = voltage_window(min_, max_, warn, crit, value)
    overrides["Min"], overrides["Max"] = nmin, nmax
    overrides["Warn"], overrides["Crit"] = nwarn, ncrit
    return overrides


def load_scenes(path="scenes.json"):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


class Track1Screen:
    def __init__(self, case, overrides, layout_id="Layout1x1", zone_index=0,
                 model_note=""):
        self.case = case
        self.overrides = overrides
        self.layout_id = layout_id
        self.zone_index = zone_index
        self.model_note = model_note

    @property
    def name(self):
        return self.case["name"]

    @property
    def section(self):
        return self.case["section"]


def build_track1_screens(scenes_data, defs: Defs):
    """One Track1Screen per non-skipped case, in scenes.json's own order
    (grouped by section already, since scenes_dump.lua flattens M.sections
    in order). Every case renders full-screen (Layout1x1) EXCEPT the
    `zonas` section, whose entire purpose is showing the same
    configuration at different real EdgeTX zone sizes -- those get the
    real (LayoutId, zone_index) whose size best matches the case's
    original target via layouts.nearest_zone() (built in Sec B but not
    wired in until this pass: every zonas case was rendering fullscreen,
    i.e. all 12 identically, which defeated the section's own point)."""
    out = []
    for case in scenes_data["cases"]:
        name = case["name"]
        if name in SKIPPED_CASES:
            continue
        overrides = track1_gauge_options(case, defs)
        if case["section"] == "zonas" and case.get("zone"):
            target_w, target_h = case["zone"]
            layout_id, zone_index, _rect = layouts.nearest_zone(target_w, target_h)
            out.append(Track1Screen(case, overrides, layout_id=layout_id,
                                     zone_index=zone_index))
        else:
            out.append(Track1Screen(case, overrides))
    return out


def batch_by_section(screens, max_per_model=MAX_CUSTOM_SCREENS):
    """Group screens into <=max_per_model chunks, never splitting a
    section's cases across a chunk boundary unless the section itself
    exceeds max_per_model (then it spans multiple models, chunked in
    declaration order)."""
    batches = []
    current = []
    current_section = None
    for s in screens:
        if s.section != current_section and current and len(current) < max_per_model:
            # section boundary with room left in the current batch: still
            # start a fresh batch anyway, so a model file's name always maps
            # to exactly one section (cleaner reporting/naming, Sec 7).
            batches.append(current)
            current = []
        current_section = s.section
        current.append(s)
        if len(current) == max_per_model:
            batches.append(current)
            current = []
            current_section = None
    if current:
        batches.append(current)
    return batches


# ------------------------------------------------------------- Track 2 -----

class LayoutGalleryScreen:
    """One Track 2 screen: a real LayoutId with a distinct Gauge Pro config
    per zone. `zones` is a list of (zone_index, overrides) pairs."""

    def __init__(self, key, title, layout_id, zones):
        self.key = key
        self.title = title
        self.layout_id = layout_id
        self.zones = zones


def build_track2_screens():
    """Curated layout-gallery screens, Sec 4 Track 2 of the plan. Every
    zone gets Source=TX_VOLTAGE with its own voltage_window() so multiple
    zones on one screen can show different bands simultaneously even though
    they all read the same live source."""
    def w(min_, max_, warn, crit, value, **extra):
        nmin, nmax, nwarn, ncrit = voltage_window(min_, max_, warn, crit, value)
        # Scale="Manual" is required for Min/Max below to take effect at all
        # -- see track1_gauge_options' docstring for the regression this
        # fixes (Scale defaults to "Auto", which ignores configured Min/Max
        # entirely and derives a range from the source's own preset table).
        extra.setdefault("Scale", "Manual")
        extra.update(Source="TX_VOLTAGE", Min=nmin, Max=nmax, Warn=nwarn, Crit=ncrit)
        return extra

    screens = []

    screens.append(LayoutGalleryScreen(
        "L01_fullscreen_bar", "Full-screen bar gauge", "Layout1x1",
        [(0, w(0, 100, 55, 35, 78, Style="Bar", ColorMode="Sections"))]))

    screens.append(LayoutGalleryScreen(
        "L02_fullscreen_needle", "Full-screen needle (clock-style, 360 deg)",
        "Layout1x1",
        [(0, w(0, 100, 55, 35, 62, Style="Needle", Sweep="360 deg"))]))

    screens.append(LayoutGalleryScreen(
        "L03_fullscreen_bar_details", "Full-screen bar with min/max + label/unit",
        "Layout1x1",
        [(0, w(0, 100, 55, 35, 45, Style="Bar", ColorMode="Threshold",
               ShowMinMax="Markers + text", Label="PACK VOLTAGE",
               Suffix="volt"))]))

    screens.append(LayoutGalleryScreen(
        "L04_fullscreen_bar_hex", "Full-screen segmented bar (Hex face)",
        "Layout1x1",
        [(0, w(0, 100, 55, 35, 78, Style="Bar", BarFace="Hex",
               Segments="10", ColorMode="Sections"))]))

    # Layout2P3 "2 + 3": the request's literal "three on one side, two on
    # another" example (verified layout2+3.cpp: left column 2 zones, right
    # column 3 zones).
    screens.append(LayoutGalleryScreen(
        "L05_layout2p3_dial_vs_bar", "Layout 2+3: dials (left) vs bars (right)",
        "Layout2P3", [
            (0, w(0, 100, 55, 35, 78, Style="Needle", ColorMode="Sections")),
            (1, w(0, 100, 55, 35, 40, Style="Arc", ColorMode="Threshold")),
            (2, w(0, 100, 55, 35, 78, Style="Bar", ColorMode="Sections")),
            (3, w(0, 100, 55, 35, 45, Style="Bar", ColorMode="Threshold")),
            (4, w(0, 100, 55, 35, 20, Style="Bar", ColorMode="Gradient")),
        ]))

    screens.append(LayoutGalleryScreen(
        "L06_layout1p2_mixed", "Layout 1+2: hero dial + two bars",
        "Layout1P2", [
            (0, w(0, 100, 55, 35, 78, Style="Needle", ColorMode="Rail")),
            (1, w(0, 100, 55, 35, 45, Style="Bar", ColorMode="Sections")),
            (2, w(0, 100, 55, 35, 22, Style="Bar", ColorMode="Sections")),
        ]))

    screens.append(LayoutGalleryScreen(
        "L07_layout4p2_mixed", "Layout 4+2: four compact bars + two dials",
        "Layout4P2", [
            (0, w(0, 100, 55, 35, 78, Style="Bar", BarFace="Ticks")),
            (1, w(0, 100, 55, 35, 45, Style="Bar", BarFace="Blocks")),
            (2, w(0, 100, 55, 35, 22, Style="Bar", BarFace="Steps")),
            (3, w(0, 100, 55, 35, 60, Style="Bar", BarFace="Continuous")),
            (4, w(0, 100, 55, 35, 78, Style="Arc", ColorMode="Sections")),
            (5, w(0, 100, 55, 35, 30, Style="Needle", ColorMode="Threshold")),
        ]))

    screens.append(LayoutGalleryScreen(
        "L08_layout2x2_grid", "Layout 2x2: four independent gauges",
        "Layout2x2", [
            (0, w(0, 100, 55, 35, 90, Style="Auto", ColorMode="Sections")),
            (1, w(0, 100, 55, 35, 50, Style="Auto", ColorMode="Sections")),
            (2, w(0, 100, 55, 35, 20, Style="Auto", ColorMode="Sections")),
            (3, w(-100, 100, -30, -60, 65, Style="Bar", BarOrigin="Zero",
                  BarFace="Dual rail")),
        ]))

    return screens
