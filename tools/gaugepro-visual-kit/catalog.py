"""Track 1 (single-widget, ported from dev/scenes.lua) and Track 2 (layout
galleries) screen catalogs for Gauge Dial Pro and Gauge Bar Pro.

TELEMETRY SCOPE NOTE: model YAML stores widget telemetry sources as tele(N)
slots, while sensor identities use the nested id1/id2/cfg union spelling.
modelgen.py now emits both contracts and TeleInject feeds those predeclared
sensors through the public setTelemetryValue() API. Scalar source-specific
scenes use that path. Most generic value-position scenes intentionally keep
the cheaper, stable TX_VOLTAGE remap; CELLS aggregation remains skipped until
the harness can inject the real multi-cell value structure.
"""

import json

from defs import Defs
import layouts

# The simu build this tool drives captures at 800x480 (confirmed by measuring
# every screenshot in a full run -- see docs/visual-kit/INFORME-DEFECTOS.md
# H-02); it does NOT run at the 480x272 this constant held before, which
# silently fed the wrong screen into every layouts.nearest_zone() call.
SCREEN_W, SCREEN_H = 800, 480
MAX_CUSTOM_SCREENS = 10

# Empirically observed, deterministic (raw-ADC-independent, see catalog.py's
# module docstring investigation): TX_VOLTAGE reads ~7.9 on every boot of
# this simu build with no calibration changes.
V0 = 7.9
WINDOW = 20.0

# Model declarations shared by telemetry-backed Track 1 batches. IDs, units
# and precisions mirror dev/scenes.lua's source contract.
TELEMETRY_SENSORS = [
    {"id": 3072, "subId": 0, "instance": 0, "name": "RSSI", "unit": 17, "prec": 0},
    {"id": 3081, "subId": 0, "instance": 0, "name": "RxBt", "unit": 1, "prec": 2},
    {"id": 3078, "subId": 0, "instance": 0, "name": "T1",   "unit": 11, "prec": 0},
]
TELEMETRY_BY_NAME = {sensor["name"]: sensor for sensor in TELEMETRY_SENSORS}

# Cases whose exact source semantics are now driven by native telemetry.
TELEMETRY_CASES = {
    "st-stale", "st-nolink", "st-nodata", "op-chip-on", "op-chip-off",
    "sc-preset", "sc-lowgood", "ba-rxbt", "pal-preset-auto",
    "br-lowgood", "br-gradient-lowgood", "f4-auto-rssi",
    "ne-damp0", "ne-damp9",
}

# Remaining cases that still need richer orchestration than a scalar value.
SKIPPED_CASES = {
    "ba-cels-low": "CELLS aggregation needs a real multi-instance telemetry sensor",
    "ba-cels-tot": "same as ba-cels-low",
    "ba-cels-avg": "same as ba-cels-low",
    "ba-pct-low": "same as ba-cels-low",
    "ba-pct-tot": "same as ba-cels-low",
    "ba-liion": "same as ba-cels-low",
    "tx-timer": "timer-typed source display is a distinct code path, not exercised by TX_VOLTAGE",
    "br-desc-history": "same as ne-damp0",
}

LOCAL_SOURCE_CASES = {
    "f5-auto-ail", "f5-auto-thr", "f5-auto-ail-one", "f5-auto-ch1",
}


def telemetry_plan(case):
    """Return an isolated, boot-time scalar telemetry pose for a scene."""
    if case["name"] not in TELEMETRY_CASES:
        return None
    source_name = case.get("source") or "RSSI"
    sensor = TELEMETRY_BY_NAME[source_name]

    def row(value):
        out = dict(sensor)
        out["value"] = int(round(float(value) * (10 ** sensor["prec"])))
        return out

    values = [row(value) for value in (case.get("history") or [])]
    values.append(row(case.get("value", 0)))
    plan = {
        "values": values,
        "link": case["name"] not in {"st-nolink", "op-chip-on", "op-chip-off"},
        # NO LINK scenes must have nil value as well as RSSI=0. If a previous
        # numeric value is fed, Gauge Pro truthfully classifies the now-old
        # TelemetryItem as STALE before it ever reaches the nil/disconnected
        # branch.
        "feed": case["name"] not in {
            "st-nodata", "st-nolink", "op-chip-on", "op-chip-off",
        },
        "rssi": 78,
    }
    if case["name"] == "st-stale":
        plan["post"] = {
            "values": [], "link": True, "feed": False, "rssi": 78,
            # TelemetryItem timeout is 20 s at the firmware's nominal 160 ms
            # aging cadence. The Widget Studio transport poses 10 Hz packets,
            # which deterministically reaches OLD in about 12.5 s.
            "settle": 13.5,
        }
    elif case["name"] in {"ne-damp0", "ne-damp9"}:
        plan["post"] = {
            "values": [row(90)], "link": True, "feed": True, "rssi": 78,
            "settle": 0.18,
        }
    return plan


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


def _family_and_options(case, defs_by_family):
    """Translate one legacy scene's Style selector into a fixed split family.

    The audited scene catalogue intentionally remains the visual source of
    truth. This adapter is the only place that understands its old Style
    option: Bar selects BarPro; Needle/Arc select DialPro + DialStyle; Auto
    follows the old wide-zone threshold. Family-only keys are validated so a
    scene cannot silently lose an override during the conversion.
    """
    overrides = dict(case.get("opts") or {})
    style = overrides.pop("Style", None)
    dial_only = set(defs_by_family["dial"].by_key) - set(defs_by_family["bar"].by_key)
    bar_only = set(defs_by_family["bar"].by_key) - set(defs_by_family["dial"].by_key)
    has_dial = bool(set(overrides) & dial_only)
    has_bar = bool(set(overrides) & bar_only)
    if has_dial and has_bar:
        raise ValueError("scene %s mixes DialPro and BarPro options" % case["name"])

    if style == "Bar" or has_bar:
        family = "bar"
    elif style in ("Needle", "Arc") or has_dial:
        family = "dial"
    elif style in (None, "Auto"):
        zone = case.get("zone") or [1, 1]
        family = "bar" if zone[0] / max(zone[1], 1) > 2.6 else "dial"
    else:
        raise ValueError("scene %s has unknown legacy Style %r" %
                         (case["name"], style))

    if family == "dial" and style in ("Auto", "Needle", "Arc"):
        overrides["DialStyle"] = style
    unknown = sorted(set(overrides) - set(defs_by_family[family].by_key))
    if unknown:
        raise ValueError("scene %s has invalid %s options: %s" %
                         (case["name"], family, ", ".join(unknown)))
    return family, overrides


def track1_gauge_options(case, defs_by_family):
    """Readable option-override dict for one scenes.json case, ready for
    Defs.build_options(). Uses TX_VOLTAGE for value-driven cases and folds
    the case's value/thresholds through voltage_window
    so the rendered state (band/markers/sweep) matches the original intent.

    Scale defaults to "Manual" (DEFS' own default is "Auto", which makes the
    widget derive Min/Max from the SOURCE's own preset table and ignore the
    configured Min/Max entirely -- confirmed by a real regression: every
    case that didn't explicitly set Scale="Manual" rendered the exact same
    generic TX_VOLTAGE auto-range regardless of voltage_window's output).
    A case's own `opts` can still override this back to "Auto" if it wants
    to (rare, and moot for TX_VOLTAGE, which has no dedicated preset)."""
    family, authored = _family_and_options(case, defs_by_family)
    defs = defs_by_family[family]
    overrides = {"Scale": "Manual"}
    overrides.update(authored)
    if case["name"] in TELEMETRY_CASES:
        # Preserve the widget's real default (Auto) unless the authored scene
        # explicitly chose a scale. The TX_VOLTAGE substitution below needs a
        # forced Manual scale; a native RSSI/T1/RxBt source does not.
        if "Scale" not in authored:
            overrides.pop("Scale", None)
        overrides["Source"] = case.get("source") or "RSSI"
        return family, overrides
    if case["name"] in LOCAL_SOURCE_CASES:
        # These cases test BarPreset's source classifier, not an authored
        # reading. Built-in model sources resolve at load time without the
        # telemetrySensors[] registration external sensors require.
        overrides["Source"] = case["source"]
        if case["name"] == "f5-auto-thr":
            # The simulator exposes raw stick units for Thr (-1024..1024),
            # unlike the injected -100..100 scene value. Match that real
            # source so the typography test is not polluted by overflow.
            overrides.update(Min=-1024, Max=1024, Warn=-512, Crit=-768)
        return family, overrides
    overrides["Source"] = "TX_VOLTAGE"

    if case.get("noSource"):
        overrides["Source"] = "NONE"
        return family, overrides

    min_, max_, warn, crit = _effective_range(overrides, defs)
    value = case.get("value")
    if isinstance(value, list):
        value = sum(value) / len(value)  # pre-CELLS-support approximation
    if value is None:
        return family, overrides

    nmin, nmax, nwarn, ncrit = voltage_window(min_, max_, warn, crit, value)
    overrides["Min"], overrides["Max"] = nmin, nmax
    overrides["Warn"], overrides["Crit"] = nwarn, ncrit
    return family, overrides


def load_scenes(path="scenes.json"):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


class Track1Screen:
    def __init__(self, case, family, overrides, layout_id="Layout1x1", zone_index=0,
                 model_note="", real_rect=None, telemetry=None):
        self.case = case
        self.family = family
        self.overrides = overrides
        self.layout_id = layout_id
        self.zone_index = zone_index
        self.model_note = model_note
        self.telemetry = telemetry
        # (x, y, w, h) pixels of the REAL zone this screen renders into, when
        # known (layouts.nearest_zone's own return value -- see
        # build_track1_screens). None for a plain fullscreen Layout1x1 case
        # that never asked for a specific zone.
        self.real_rect = real_rect

    @property
    def name(self):
        return self.case["name"]

    @property
    def section(self):
        return self.case["section"]


def build_track1_screens(scenes_data, defs_by_family):
    """One Track1Screen per non-skipped case, in scenes.json's own order
    (grouped by section already, since scenes_dump.lua flattens M.sections
    in order).

    Every case that declares a `zone` renders into the real (LayoutId,
    zone_index) whose size best matches it, via layouts.nearest_zone() --
    NOT only the `zonas` section (docs/visual-kit/INFORME-DEFECTOS.md H-01:
    210 of 222 cases declare a zone and were still rendering fullscreen,
    which is a size no real widget zone has except Layout1x1 itself, so
    cases whose whole point IS their size -- e.g. `tx-prec2-micro` at
    60x60, or the `br-narrow`/`br-short`/`br-nochip` trio at 300x44/160x44/
    300x70 -- never actually exercised the layout code paths gated on small
    zones, and several collapsed into byte-identical screenshots that still
    reported PASS). Only a case with NO declared zone keeps the previous
    plain fullscreen Layout1x1 behaviour."""
    out = []
    for case in scenes_data["cases"]:
        name = case["name"]
        if name in SKIPPED_CASES:
            continue
        family, overrides = track1_gauge_options(case, defs_by_family)
        telem = telemetry_plan(case)
        zone = case.get("zone")
        if zone:
            target_w, target_h = zone
            layout_id, zone_index, rect = layouts.nearest_zone(
                target_w, target_h, SCREEN_W, SCREEN_H)
            out.append(Track1Screen(case, family, overrides, layout_id=layout_id,
                                     zone_index=zone_index, real_rect=rect,
                                     telemetry=telem))
        else:
            out.append(Track1Screen(case, family, overrides, telemetry=telem))
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
        # Boot-time injection is deterministic and also guarantees that a
        # no-data case starts with a genuinely empty TelemetryItem. Keep each
        # such pose in its own process/model batch.
        if s.telemetry:
            if current:
                batches.append(current)
                current = []
                current_section = None
            batches.append([s])
            continue
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
    """One Track 2 screen with a distinct split-widget config per zone.

    Callers provide ``(zone_index, (family, overrides))`` pairs; ``zones`` is
    normalized to the model generator's ``(zone_index, family, overrides)``.
    """

    def __init__(self, key, title, layout_id, zones):
        self.key = key
        self.title = title
        self.layout_id = layout_id
        self.zones = [(zi, family, overrides)
                      for zi, (family, overrides) in zones]


def build_track2_screens(defs_by_family):
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
        case = {"name": "track2", "zone": [1, 1], "opts": extra}
        family, split = _family_and_options(case, defs_by_family)
        return family, split

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
