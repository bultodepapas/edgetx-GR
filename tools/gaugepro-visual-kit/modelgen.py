"""Model YAML generator for the split Gauge Pro visual kit.

The overall model skeleton (mixData/expoData/switchWarning/... boilerplate)
below is copied VERBATIM from a model file the real firmware itself wrote
(simuCreateDefaults) and then successfully reloaded after a hand-edit in the
Widget Studio Phase 1 spike (myplans/widget-visual-emulator-plan.md Sec 9a).
It is intentionally not re-derived through a generic YAML library: this
repo's YAML reader (radio/src/storage/yaml) is a bespoke, indentation- and
key-order-sensitive parser, and the fastest way to stay inside what it
accepts is to keep using bytes it has already accepted, changing only the
`header.name` and `screenData` block.

LayoutId / zone-count table: see myplans/gaugepro-visual-kit-plan.md Sec 2
(verified against radio/src/gui/colorlcd/layouts/*.cpp).
"""

import zlib

MAX_CUSTOM_SCREENS = 10

# Zone counts per LayoutId, verified against radio/src/gui/colorlcd/layouts.
LAYOUT_ZONES = {
    "Layout1x1": 1, "Layout1x2": 2, "Layout1x3": 3, "Layout1x4": 4,
    "Layout1x6": 6, "Layout2x1": 2, "Layout2x2": 4, "Layout2x3": 6,
    "Layout2x4": 8, "Layout1P2": 3, "Layout1P3": 4, "Layout1P4": 5,
    "Layout2P1": 3, "Layout2P3": 5, "Layout4P2": 6, "Layout4P2B": 6,
}

_HEADER = """semver: 3.0.0
header:
   name: "%(name)s"
   bitmap: ""
   labels: ""
telemetryProtocol: 0
thrTrim: 0
noGlobalFunctions: 0
displayTrims: 0
ignoreSensorIds: 0
trimInc: 0
disableThrottleWarning: 0
displayChecklist: 0
extendedLimits: 0
extendedTrims: 0
throttleReversed: 0
enableCustomThrottleWarning: 0
disableTelemetryWarning: 0
showInstanceIds: 0
checklistInteractive: 0
customThrottleWarningPosition: 0
beepANACenter: 0
mixData:
 -
   destCh: 0
   srcRaw: "I0"
   carryTrim: 0
   mixWarn: 0
   mltpx: ADD
   delayPrec: 0
   speedPrec: 0
   flightModes: 000000000
   weight: 100
   offset: 0
   swtch: "NONE"
   delayUp: 0
   delayDown: 0
   speedUp: 0
   speedDown: 0
   name: ""
 -
   destCh: 1
   srcRaw: "I1"
   carryTrim: 0
   mixWarn: 0
   mltpx: ADD
   delayPrec: 0
   speedPrec: 0
   flightModes: 000000000
   weight: 100
   offset: 0
   swtch: "NONE"
   delayUp: 0
   delayDown: 0
   speedUp: 0
   speedDown: 0
   name: ""
 -
   destCh: 2
   srcRaw: "I2"
   carryTrim: 0
   mixWarn: 0
   mltpx: ADD
   delayPrec: 0
   speedPrec: 0
   flightModes: 000000000
   weight: 100
   offset: 0
   swtch: "NONE"
   delayUp: 0
   delayDown: 0
   speedUp: 0
   speedDown: 0
   name: ""
 -
   destCh: 3
   srcRaw: "I3"
   carryTrim: 0
   mixWarn: 0
   mltpx: ADD
   delayPrec: 0
   speedPrec: 0
   flightModes: 000000000
   weight: 100
   offset: 0
   swtch: "NONE"
   delayUp: 0
   delayDown: 0
   speedUp: 0
   speedDown: 0
   name: ""
expoData:
 -
   mode: 3
   scale: 0
   trimSource: 0
   srcRaw: "Rud"
   weight: 100
   offset: 0
   swtch: "NONE"
   curve:
      type: 1
      value: 0
   chn: 0
   flightModes: 000000000
   name: ""
 -
   mode: 3
   scale: 0
   trimSource: 0
   srcRaw: "Ele"
   weight: 100
   offset: 0
   swtch: "NONE"
   curve:
      type: 1
      value: 0
   chn: 1
   flightModes: 000000000
   name: ""
 -
   mode: 3
   scale: 0
   trimSource: 0
   srcRaw: "Thr"
   weight: 100
   offset: 0
   swtch: "NONE"
   curve:
      type: 1
      value: 0
   chn: 2
   flightModes: 000000000
   name: ""
 -
   mode: 3
   scale: 0
   trimSource: 0
   srcRaw: "Ail"
   weight: 100
   offset: 0
   swtch: "NONE"
   curve:
      type: 1
      value: 0
   chn: 3
   flightModes: 000000000
   name: ""
thrTraceSrc: Thr
switchWarning:
   SA:
      pos: up
   SB:
      pos: up
   SC:
      pos: up
   SD:
      pos: up
   SE:
      pos: up
   SF:
      pos: up
   SG:
      pos: up
   SH:
      pos: up
   SW1:
      pos: down
   SW2:
      pos: up
   SW3:
      pos: up
   SW4:
      pos: up
   SW5:
      pos: up
   SW6:
      pos: up
rssiSource: none
rfAlarms:
   warning: 45
   critical: 42
thrTrimSw: 0
potsWarnMode: WARN_OFF
jitterFilter: GLOBAL
inputNames:
   0:
      val: "Rud"
   1:
      val: "Ele"
   2:
      val: "Thr"
   3:
      val: "Ail"
potsWarnEnabled: 0
screenData:
"""

_FOOTER = """topbarData:
   zones:
      0:
         widgetName: TeleInject
         widgetData:
topbarWidgetWidth:
   0:
      val: 1
view: 0
modelRegistrationID: "%(regid)s"
customSwitches:
   SW1:
      name: ""
      type: 2POS
      group: 1
      start: START_ON
      state: 1
      onColorLuaOverride: OFF
      offColorLuaOverride: OFF
      onColor:
         r: 255
         g: 255
         b: 255
      offColor:
         r: 0
         g: 0
         b: 0
   SW2:
      name: ""
      type: 2POS
      group: 1
      start: START_OFF
      state: 0
      onColorLuaOverride: OFF
      offColorLuaOverride: OFF
      onColor:
         r: 255
         g: 255
         b: 255
      offColor:
         r: 0
         g: 0
         b: 0
   SW3:
      name: ""
      type: 2POS
      group: 1
      start: START_OFF
      state: 0
      onColorLuaOverride: OFF
      offColorLuaOverride: OFF
      onColor:
         r: 255
         g: 255
         b: 255
      offColor:
         r: 0
         g: 0
         b: 0
   SW4:
      name: ""
      type: 2POS
      group: 1
      start: START_OFF
      state: 0
      onColorLuaOverride: OFF
      offColorLuaOverride: OFF
      onColor:
         r: 255
         g: 255
         b: 255
      offColor:
         r: 0
         g: 0
         b: 0
   SW5:
      name: ""
      type: 2POS
      group: 1
      start: START_OFF
      state: 0
      onColorLuaOverride: OFF
      offColorLuaOverride: OFF
      onColor:
         r: 255
         g: 255
         b: 255
      offColor:
         r: 0
         g: 0
         b: 0
   SW6:
      name: ""
      type: 2POS
      group: 1
      start: START_OFF
      state: 0
      onColorLuaOverride: OFF
      offColorLuaOverride: OFF
      onColor:
         r: 255
         g: 255
         b: 255
      offColor:
         r: 0
         g: 0
         b: 0
cfsGroupOn:
   1:
      v: 1
   2:
      v: 0
   3:
      v: 0
usbJoystickExtMode: 0
usbJoystickIfMode: JOYSTICK
usbJoystickCircularCut: 0
radioThemesDisabled: GLOBAL
radioGFDisabled: GLOBAL
radioTrainerDisabled: GLOBAL
modelHeliDisabled: GLOBAL
modelFMDisabled: GLOBAL
modelCurvesDisabled: GLOBAL
modelGVDisabled: GLOBAL
modelLSDisabled: GLOBAL
modelSFDisabled: GLOBAL
modelCustomScriptsDisabled: GLOBAL
modelTelemetryDisabled: GLOBAL
"""


class Screen:
    """One screenData[] entry with ``(zone, family, options)`` instances."""

    def __init__(self, layout_id, zones, comment=""):
        if layout_id not in LAYOUT_ZONES:
            raise ValueError("modelgen: unknown LayoutId %r" % layout_id)
        for zi, family, _opts in zones:
            if zi < 0 or zi >= LAYOUT_ZONES[layout_id]:
                raise ValueError(
                    "modelgen: zone %d out of range for %s (%d zones)"
                    % (zi, layout_id, LAYOUT_ZONES[layout_id]))
            if family not in ("dial", "bar"):
                raise ValueError("modelgen: invalid Gauge Pro family %r" % family)
        self.layout_id = layout_id
        self.zones = zones
        self.comment = comment


def _yaml_scalar(value):
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return value
    raise TypeError("modelgen: cannot emit YAML scalar for %r" % (value,))


def _render_options_block(defs, overrides, indent):
    pad = " " * indent
    lines = []
    for index, yaml_type, field, value in defs.build_options(overrides):
        lines.append("%s%d:" % (pad, index))
        lines.append("%s   type: %s" % (pad, yaml_type))
        lines.append("%s   value: " % pad)
        lines.append("%s      %s: %s" % (pad, field, _yaml_scalar(value)))
    return "\n".join(lines) + "\n"


def render_screen_data(defs_by_family, screens):
    if len(screens) > MAX_CUSTOM_SCREENS:
        raise ValueError(
            "modelgen: %d screens exceeds MAX_CUSTOM_SCREENS=%d"
            % (len(screens), MAX_CUSTOM_SCREENS))
    out = []
    for si, screen in enumerate(screens):
        if screen.comment:
            out.append("   # screen %d: %s" % (si, screen.comment))
        out.append("   %d:" % si)
        out.append("      LayoutId: %s" % screen.layout_id)
        out.append("      layoutData: ")
        if screen.zones:
            out.append("         zones: ")
            for zi, family, overrides in screen.zones:
                defs = defs_by_family[family]
                out.append("            %d:" % zi)
                out.append("               widgetName: %s" % defs.widget_name)
                out.append("               widgetData: ")
                out.append("                  options: ")
                out.append(_render_options_block(defs, overrides, 21).rstrip("\n"))
    return "\n".join(out) + "\n"


def render_model(defs_by_family, name, screens, regid=None):
    """Full model YAML text for one MODELS/*.yml file (<=10 screens)."""
    if regid is None:
        # zlib.crc32, not the builtin hash(): str hashing is salted per
        # process (PYTHONHASHSEED) by default, which would silently make
        # this ID -- and with it every byte of the written file -- differ
        # between two otherwise-identical runs (plan Sec 15's
        # reproducibility gate: two consecutive runs must be byte-identical).
        regid = ("GPVK%03d" % (zlib.crc32(name.encode("utf-8")) % 1000)).ljust(8, "0")[:8]
    header = _HEADER % {"name": name}
    body = render_screen_data(defs_by_family, screens)
    footer = _FOOTER % {"regid": regid}
    return header + body + footer


def write_model(defs_by_family, path, name, screens, regid=None):
    text = render_model(defs_by_family, name, screens, regid=regid)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return path
