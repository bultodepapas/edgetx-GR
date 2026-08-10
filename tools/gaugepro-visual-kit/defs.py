"""Gauge Pro option table: loads defs.json (produced by defs_dump.lua from
the REAL WIDGETS/GaugePro/main.lua) and translates readable option overrides
into the model-YAML wire format.

The wire format below (which storage type each Lua option type maps to, and
the exact YAML field name per type) is not documented anywhere in the C++ --
it was determined empirically by round-tripping a hand-authored Gauge Pro
zone through the real firmware in the Widget Studio Phase 1 spike
(myplans/widget-visual-emulator-plan.md Sec 9a) and re-confirmed against the
saved MODELS/model1.yml from that session. See THEME_ROLE_INDEX for the
COLIDXn convention (radio/src/gui/colorlcd/colors.h LcdColorIndex order).
"""

import json

# widget.h WidgetOption::Type -> storage WidgetOptionValueEnum + YAML field.
# CHOICE/SLIDER/SWITCH all collapse onto "Unsigned"; VALUE (signed range) onto
# "Signed"; empirically confirmed, see module docstring.
_WIRE = {
    "VALUE": ("Signed", "signedValue"),
    "SOURCE": ("Source", "source"),
    "BOOL": ("Bool", "boolValue"),
    "STRING": ("String", "stringValue"),
    "SWITCH": ("Unsigned", "unsignedValue"),
    "COLOR": ("Color", "color"),
    "SLIDER": ("Unsigned", "unsignedValue"),
    "CHOICE": ("Unsigned", "unsignedValue"),
}

# radio/src/gui/colorlcd/colors.h LcdColorIndex, variable-colour roles only
# (mirrors tests/mock_env.lua's COLOR_INDEX table exactly).
THEME_ROLE_INDEX = {
    "COLOR_THEME_PRIMARY1": 0, "COLOR_THEME_PRIMARY2": 1,
    "COLOR_THEME_PRIMARY3": 2, "COLOR_THEME_SECONDARY1": 3,
    "COLOR_THEME_SECONDARY2": 4, "COLOR_THEME_SECONDARY3": 5,
    "COLOR_THEME_FOCUS": 6, "COLOR_THEME_EDIT": 7, "COLOR_THEME_ACTIVE": 8,
    "COLOR_THEME_WARNING": 9, "COLOR_THEME_DISABLED": 10,
    "COLOR_THEME_QM_BG": 11, "COLOR_THEME_QM_FG": 12,
}

RGB_FLAG = 0x8000


def rgb(r, g, b):
    """lcd.RGB(r,g,b) equivalent, same packed format tests/mock_env.lua's
    lcd.RGB produces: (rgb565 << 16) | RGB_FLAG. This is the ONE colour
    representation used throughout this tool -- defs.json's COLOR defaults
    and scenes.json's ported option overrides are both already in this
    format (they came out of the same mock), so a hand-authored override
    from Python must match it too, or resolve()'s COLOR branch (which always
    decodes via _decode_mock_color) would misread it."""
    r5 = (r & 0xF8)
    g6 = (g & 0xFC)
    b5 = (b & 0xF8)
    rgb565 = (r5 << 8) + (g6 << 3) + (b5 >> 3)
    return (rgb565 << 16) | RGB_FLAG


def _decode_mock_color(packed):
    """Decode a tests/mock_env.lua lcd.RGB()-style packed value:
    (rgb565 << 16) | RGB_FLAG for a literal colour, or (index << 16) for a
    theme role (no RGB_FLAG bit). Returns ('literal', 0xRRGGBB) or
    ('role', index)."""
    low16 = packed & 0xFFFF
    if low16 & RGB_FLAG:
        rgb565 = (packed >> 16) & 0xFFFF
        r5 = (rgb565 >> 11) & 0x1F
        g6 = (rgb565 >> 5) & 0x3F
        b5 = rgb565 & 0x1F
        r8 = (r5 << 3) | (r5 >> 2)
        g8 = (g6 << 2) | (g6 >> 4)
        b8 = (b5 << 3) | (b5 >> 2)
        return ("literal", (r8 << 16) | (g8 << 8) | b8)
    index = (packed >> 16) & 0xFF
    return ("role", index)


class Defs:
    def __init__(self, rows):
        self.rows = rows
        self.by_key = {r["key"]: r for r in rows}
        assert len(rows) == len(self.by_key), "duplicate DEFS key in defs.json"

    @classmethod
    def load(cls, path):
        with open(path, "r", encoding="utf-8") as f:
            rows = json.load(f)
        return cls(rows)

    def keys(self):
        return [r["key"] for r in self.rows]

    def default_wire(self, key):
        """(yaml_type, field_name, field_value) for a DEFS option's own
        declared default -- used to fill every slot a case does not
        override (see plan Sec 1.2: VALUE/COLOR/STRING/SWITCH/SOURCE never
        auto-default from a stored 0, so every slot must get a real value)."""
        row = self.by_key[key]
        t = row["type"]
        yaml_type, field = _WIRE[t]
        default = row["default"]
        if t == "COLOR":
            kind, val = _decode_mock_color(default)
            if kind == "literal":
                return yaml_type, field, "0x%06X" % val
            return yaml_type, field, "COLIDX%d" % val
        if t == "SOURCE":
            # DEFS' default is a fallback-candidate list (used only when no
            # source is configured at all); every generated screen supplies
            # an explicit source instead, so this branch is never emitted
            # for real -- resolve() below always overrides SOURCE.
            return yaml_type, field, "NONE"
        if t == "STRING":
            return yaml_type, field, default if default else ""
        return yaml_type, field, default

    def resolve(self, key, value):
        """(yaml_type, field_name, field_value) for an explicit override.
        `value` forms accepted, matching dev/scenes.lua's own readable
        vocabulary:
          CHOICE : choice label (str) or 1-based index (int)
          BOOL   : True/False or 0/1
          COLOR  : int 0xRRGGBB (use defs.rgb()) or "@COLOR_THEME_X" role name
          SOURCE : symbolic source name (str), passed through verbatim
          STRING : literal text
          VALUE/SLIDER/SWITCH : int
        """
        row = self.by_key[key]
        t = row["type"]
        yaml_type, field = _WIRE[t]
        if t == "CHOICE":
            if isinstance(value, str):
                choices = row["choices"]
                if value not in choices:
                    raise ValueError(
                        "defs.resolve: %r is not a choice of %s (have %s)"
                        % (value, key, choices))
                return yaml_type, field, choices.index(value) + 1
            return yaml_type, field, int(value)
        if t == "BOOL":
            return yaml_type, field, (1 if value else 0)
        if t == "COLOR":
            if isinstance(value, str) and value.startswith("@"):
                role = value[1:]
                if role not in THEME_ROLE_INDEX:
                    raise ValueError("defs.resolve: unknown theme role %r" % role)
                return yaml_type, field, "COLIDX%d" % THEME_ROLE_INDEX[role]
            # Every numeric COLOR value in this tool -- defaults, values
            # ported from scenes.json, and defs.rgb() calls -- uses the same
            # mock lcd.RGB() packed format; decode it the one way (see
            # default_wire's identical COLOR branch).
            kind, val = _decode_mock_color(int(value))
            if kind == "literal":
                return yaml_type, field, "0x%06X" % val
            return yaml_type, field, "COLIDX%d" % val
        if t == "SOURCE":
            return yaml_type, field, str(value)
        if t == "STRING":
            return yaml_type, field, str(value)
        return yaml_type, field, int(value)

    def build_options(self, overrides):
        """Full 44-slot wire option list for one Gauge Pro instance: every
        DEFS key gets an explicit value, defaults for anything `overrides`
        doesn't touch. Returns a list of (index, yaml_type, field, value) in
        DEFS order -- the model-YAML options block's positional contract."""
        out = []
        for row in self.rows:
            key = row["key"]
            if key in overrides:
                yaml_type, field, value = self.resolve(key, overrides[key])
            else:
                yaml_type, field, value = self.default_wire(key)
            out.append((row["index"], yaml_type, field, value))
        return out
