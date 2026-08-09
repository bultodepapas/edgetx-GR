# GaugeV2 — Tanda 8 plan: the colour foundation, and findings from the render review

**Author role:** senior developer, visual review of the generated render set,
then a source-level audit of the firmware's theme system.
**Baseline:** `feat/gauge-v2` @ `d94d37d52` (Tanda 7 A/B/C shipped).
Suites green: 38 unit, 129 lifecycle, 18/18 collision zones, 77 gallery scenes
with 0 render warnings, luacheck 0/33.
**Status:** **PROPOSED — awaiting owner decision.** §12 lists what needs a
yes/no.
**Revision:** **v2.** v1 of this document was written from the render set
alone. Auditing the firmware afterwards **falsified three of its claims** —
see §1. The headline finding changed completely.
**Date:** 9 August 2026.

---

## 0. Summary

| # | Finding | Severity | Verdict |
|---|---|---|---|
| **F0** | **The "normal" status colour is a button-background role — 1.13 : 1 on the stock theme** | **P0** | fix |
| **F7** | **`dev/svgkit.lua` renders an invented palette, not EdgeTX's** — why none of this was visible | **P0 (tooling)** | fix first |
| **F1a** | Warning and critical are both red on the stock theme (Δ 53) | P2 | mitigated; decide |
| **F1b** | Gradient mode invents RGB and ignores the theme | P2 | fix |
| F2 | "No data" muting is incomplete: reference bands outshine the live gauge | P2 | fix |
| F3 | 360° sweep gives value and name 2 px while 18 px sits unused | P3 | fix (cheap) |
| F4 | 480×272 min/max reads as three unrelated labels | P3 | fix (cheap) |
| F5 | Needle crosses the value at scale extremes | P3 | **no action** — settled |
| F6 | Renders capture the critical pulse at inconsistent phases | P3 | fix in tooling |

**F0 is the finding.** On EdgeTX's stock theme the "all clear" arc and value
render at **1.13 : 1** against the screen background — effectively invisible.
Everything else in this document is decoration next to it.

**F7 is why nobody saw it.** Every render ever reviewed for this widget was
drawn with a palette invented in `dev/svgkit.lua`, in which the normal state
is a green that does not exist in EdgeTX. Fix the tool first or the next
review inherits the same blind spot.

---

## 1. Corrections to v1 of this document

Recorded because the plan was wrong, not the code. All three were found by
reading `radio/src/` in this tree after v1 was written.

1. **"No Lua API exposes the RGB behind a `COLOR_THEME_*` role" — FALSE.**
   `lcd.getColor(flags)` does exactly that, and has since 2.3.11
   (`radio/src/lua/api_colorlcd.cpp:956`, exported at :1477). It returns the
   RGB565 value in the high 16 bits. So the widget **can** read theme
   colours, **can** compute their luminance, and **can** therefore adapt to a
   light or dark theme at runtime. v1 marked the theme-adaptive option
   "impossible today" and built its recommendation around that. That was the
   central error.

2. **Every contrast number in v1 was measured against a fiction.** They came
   from `dev/svgkit.lua`'s palette, which is a designer's dark/light scheme,
   not EdgeTX's roles. See F7.

3. **F1 (gradient) was not the high-severity item.** The gradient's worst
   case is 1.72 : 1 and only in Gradient mode. The *normal state* is
   **1.13 : 1 in every colour mode** on the stock theme. v1 ranked a symptom
   above the disease.

---

## 2. Method, and the rule v1 got wrong

Facts are from this tree: `radio/src/gui/colorlcd/colors.cpp` (the compiled-in
colour table), `radio/src/lua/api_colorlcd.cpp` (the Lua colour API),
`radio/src/gui/colorlcd/themes/theme_manager.cpp`, and the role semantics
published at <https://github.com/EdgeTX/themes/blob/main/structure.md>.

Contrast is the WCAG 2.x relative-luminance ratio. Text thresholds are
4.5 : 1 (normal) and 3 : 1 (large — which most of this widget's value type is,
at 16–48 px). Non-text graphical objects are 3 : 1 (WCAG 1.4.11).

**The methodological rule v1 broke.** A *theme role* travels with its theme:
the author picked `WARNING` knowing their own `SECONDARY3` background, so a
role may only be judged against **its own theme's** background. A *fixed*
colour (`RED`, or any literal the widget introduces) has no such protection
and must clear the bar against **every** background it might land on. v1
cross-multiplied roles against foreign backgrounds and drew conclusions from
it. This document does not.

**One caveat that limits every contrast claim here.** A theme may ship a
`background.png` (`theme_manager.cpp:267,274`), so the screen behind a widget
is not necessarily `SECONDARY3` at all. Contrast against a photograph cannot
be guaranteed by any colour choice. This is the strongest argument for
*preferring the theme's own foreground roles*, whose author at least saw
their own background — rather than for computing ratios and inventing RGB.

---

## 3. F0 — the "normal" status colour is a UI-background role (P0)

### F0.1 Evidence

EdgeTX's compiled-in defaults (`colors.cpp:28`, mirrored into `lcdColorTable`
so widget colour options work):

| role | stock RGB | what the theme docs say it *means* |
|---|---|---|
| `PRIMARY1` | `#000000` | **label text**, unfocused button text |
| `PRIMARY3` | `#0c3f66` | scroll markers, inactive icon parts |
| `SECONDARY1` | `#125e99` | top/bottom bar backgrounds, slider paths |
| `SECONDARY2` | `#b6e0f2` | label and button backgrounds |
| `SECONDARY3` | `#e4eef2` | **main screen and popup background** |
| `EDIT` | `#009909` | editable field background (editing) |
| `ACTIVE` | `#ffde00` | **active button / variable field background** |
| `WARNING` | `#e00000` | **warning label text** |
| `DISABLED` | `#8c8c8c` | disabled UI elements |

`theme.lua` maps `accent = COLOR_THEME_ACTIVE` — the normal state and the
default Accent. `ACTIVE` is a *button background* role. Used as a foreground
against the stock background:

| widget use | role | stock RGB | vs stock bg | verdict |
|---|---|---|---|---|
| **normal / accent** | `ACTIVE` | `#ffde00` | **1.13 : 1** | **FAIL** |
| warning | `WARNING` | `#e00000` | 4.27 : 1 | AA-large ✓ |
| critical | `RED` (fixed) | `#ff0000` | 3.39 : 1 | AA-large ✓ |
| needle | `PRIMARY1` | `#000000` | 17.81 : 1 | ✓ |
| value / name / labels | `SECONDARY1` | `#125e99` | 5.77 : 1 | AA ✓ |
| track / rail / ticks | `SECONDARY1` | `#125e99` | 5.77 : 1 | ✓ (a slider path — correct role) |
| chip background | `SECONDARY2` | `#b6e0f2` | 1.19 : 1 | fill invisible; reads via its outline |
| muted | `DISABLED` | `#8c8c8c` | 2.85 : 1 | acceptable — deliberately recessive |

So on a stock radio the gauge is **near-invisible in its normal state** — the
arc *and* the value text, in every colour mode, because `accent` feeds both.
The same colour scores 9.87 : 1 on a dark theme, which is exactly why every
dark render looked perfect.

Note what is **not** wrong: the needle, the track/rail, the chip background
and the muted role all use roles whose published meaning matches the use.
Only `accent` is a category error.

### F0.2 Options

| # | Option | Stock light | Dark theme | Follows theme | Verdict |
|---|---|---|---|---|---|
| F0-0 | Status quo (`ACTIVE`) | **1.13 : 1** | 9.87 : 1 | yes | rejected: the defect |
| F0-1 | `EDIT` role (`#009909` stock) | 3.20 : 1 | 3.49 : 1 | yes | works, but "editable field background" is another category error |
| F0-2 | `PRIMARY1` / `PRIMARY3` (text roles) | 17.8 / 9.3 | ✓ | yes | safest, but normal loses all colour identity |
| **F0-3** | **A fixed green, symmetric with critical's fixed `RED`** | **3.64 : 1** | **3.08 : 1** | no | **recommended** |
| F0-4 | Read `SECONDARY3` via `lcd.getColor` and pick light/dark variants | best of both | best of both | adaptively | **strongest, most code** — see F0.3 |
| F0-5 | Keep `ACTIVE`, tell users to set Accent | — | — | — | rejected: a default that fails is still a failure |

Measured candidates for F0-3 (a fixed colour must clear 3 : 1 against **both**
a light and a dark background):

| candidate | vs stock light | vs dark (`#303030`) | verdict |
|---|---|---|---|
| `ACTIVE` today `#ffde00` | 1.13 : 1 | 9.87 : 1 | fails light |
| `GREEN` `#00ff00` | 1.16 : 1 | 9.62 : 1 | fails light |
| `BRIGHTGREEN` `#00b43c` | 2.35 : 1 | 4.77 : 1 | fails light |
| `DARKGREEN` `#00a000` | 2.95 : 1 | 3.79 : 1 | just fails light |
| `#00963c` | 3.28 : 1 | 3.41 : 1 | passes both |
| **`#1e8c46`** | **3.64 : 1** | **3.08 : 1** | **passes both — best balance** |
| `#008c78` (teal) | 3.55 : 1 | 3.16 : 1 | passes both |

The widget already accepted that **no theme role exists for "critical"** and
used a literal `RED`. The identical argument applies to "good": EdgeTX has no
"all clear" role, so inventing one is consistent, not a new sin — provided it
is chosen to clear the bar on both backgrounds, which `ACTIVE` never did.

### F0.3 The adaptive option (F0-4), now that `lcd.getColor` is on the table

```lua
-- theme.lua
-- EdgeTX exposes the RGB behind a role (lcd.getColor, api_colorlcd.cpp:956,
-- since 2.3.11). The value arrives as RGB565 in the HIGH 16 bits of the
-- returned flags, with RGB_FLAG set (colors.h: COLOR_VAL, GET_RED/GREEN/BLUE).
local function roleRGB(flag)
  if type(lcd) ~= "table" or type(lcd.getColor) ~= "function" then return nil end
  local ok, v = pcall(lcd.getColor, flag)
  if not ok or type(v) ~= "number" then return nil end
  local c = (v >> 16) & 0xFFFF
  return (c & 0xF800) >> 8, (c & 0x07E0) >> 3, (c & 0x001F) << 3
end

-- Relative luminance of the theme's own screen background. Used ONLY to
-- decide "is this a light theme or a dark one" - a one-bit question - never
-- to compute an exact ratio: a theme may ship a background.png
-- (theme_manager.cpp:267), so the real backdrop can be a photograph.
function M.themeIsLight()
  local r, g, b = roleRGB(COLOR_THEME_SECONDARY3)
  if not r then return true end        -- stock EdgeTX is light; assume it
  local function lin(c)
    c = c / 255
    if c <= 0.04045 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
  end
  return (0.2126*lin(r) + 0.7152*lin(g) + 0.0722*lin(b)) > 0.18
end
```

then `M.color.accent` becomes a lazily-resolved pair. **Cost:** one
`lcd.getColor` per widget at setup, plus the branch. **Benefit:** a brighter
green on dark themes (where `#1e8c46` is merely adequate at 3.08 : 1) and a
darker one on light. **Risk:** it is a heuristic that a background image
defeats, and it adds a second code path to every colour decision.

My read: **F0-3 now, F0-4 only if the bench test says `#1e8c46` looks weak on
a dark theme.** One colour that provably clears the bar everywhere beats a
clever mechanism that is right more often but can be wrong in a way nobody
can see coming.

### F0.4 Pseudocode (F0-3)

```lua
-- theme.lua
-- "All clear" has no theme role. EdgeTX's role set is a UI vocabulary -
-- PRIMARY* is text, SECONDARY* is chrome and backgrounds, ACTIVE is the
-- background of a CHECKED control, WARNING is warning label text
-- (github.com/EdgeTX/themes/blob/main/structure.md). There is no "good".
--
-- This used to map onto COLOR_THEME_ACTIVE, which is yellow on the stock
-- theme (#ffde00) and scores 1.13:1 against the stock screen background
-- (#e4eef2): the normal state - the arc AND the value text, in every colour
-- mode - was effectively invisible on a stock radio. It measured 9.87:1 on a
-- dark theme, which is why every render in this repo looked correct.
--
-- So the normal state takes a FIXED colour, exactly as `crit` already takes a
-- fixed RED for the same reason. Chosen to clear the 3:1 non-text floor
-- against BOTH a light and a dark background (3.64:1 / 3.08:1); the brighter
-- greens EdgeTX offers - GREEN, BRIGHTGREEN, DARKGREEN - all fail on light.
-- The Accent option still overrides it for anyone who wants their own.
M.color.accent = lcd.RGB(0x1e, 0x8c, 0x46)
```

`main.lua`'s `Accent` option default must move with it — today it is
`COLOR_THEME_ACTIVE`, and `theme.lua` documents that the two must agree or
the option's default silently shadows the fallback on 2.12+.

### F0.5 Tests

```lua
test("F0: the normal state does not use a UI-background role", function()
  -- COLOR_THEME_ACTIVE is the background of a CHECKED control, not an
  -- "all clear" colour; on the stock theme it is yellow at 1.13:1 against
  -- the screen background. A pin, not a re-measurement: the ratio depends on
  -- the user's theme, the ROLE CHOICE is what this repo controls.
  local T = w.mods.theme
  assertTrue(T.color.accent ~= COLOR_THEME_ACTIVE,
    "normal must not be COLOR_THEME_ACTIVE")
  assertTrue(T.color.accent ~= COLOR_THEME_SECONDARY2
         and T.color.accent ~= COLOR_THEME_SECONDARY3,
    "nor any other background role")
end)

test("F0: main.lua's Accent default matches theme.lua's accent", function()
  -- theme.lua's own contract: on 2.12+ the option is always populated, so a
  -- mismatched default silently shadows the fallback.
  local mod = dofile(widgetDir .. "main.lua")
  local accent
  for _, d in ipairs(mod.defs) do if d.key == "Accent" then accent = d end end
  local T = dofile(widgetDir .. "theme.lua")
  assertEq(accent.default, T.color.accent, "Accent default tracks theme accent")
end)
```

### F0.6 Files, risk, acceptance

| | |
|---|---|
| **Files** | `theme.lua` (`M.color.accent`), `main.lua` (`Accent` default), `DOCS.md` (§4.3 says "green" — currently true only by accident), `tests/smoke_test.lua` |
| **Renders changed** | **every scene in the normal state**, both palettes |
| **Risk** | low in code, high in visibility — this is the widget's primary colour |
| **Rollback** | one constant, plus the matching option default |
| **Acceptance** | ≥ 3 : 1 against both reference backgrounds; **bench-checked on a stock-theme radio**; suites green |

---

## 4. F7 — the render tool paints a palette EdgeTX does not have (P0, tooling)

### F7.1 Evidence

`dev/svgkit.lua:44-72` builds two palettes. Against the firmware's actual
`lcdColorTable`:

| role | svgkit "dark" | svgkit "light" | **EdgeTX stock** |
|---|---|---|---|
| `ACTIVE` | `#3fb950` green | `#1a7f37` green | **`#ffde00` yellow** |
| `WARNING` | `#e3b341` amber | `#9a6700` ochre | **`#e00000` red** |
| `SECONDARY1` | `#8fa0b3` grey | `#5b6b7c` grey | **`#125e99` blue** |
| `SECONDARY3` | `#1c2430` near-black | `#ffffff` | **`#e4eef2` near-white** |

The tool's palette is internally coherent and looks like a well-designed
product. It is not EdgeTX. Consequences:

- Every design review in this repo — Tanda 5's designer feedback, Tanda 7's
  before/after, and v1 of this document — judged colours the radio never
  draws. F0 was invisible for four review rounds because of it.
- The stock EdgeTX theme is **light**. The widget's canonical renders are
  dark. The default case has effectively never been reviewed.
- `dev/gallery.lua`'s two-palette sweep gives false confidence: it varies a
  palette that is fiction in both directions.

### F7.2 Options

| # | Option | Verdict |
|---|---|---|
| F7-0 | Status quo | rejected: the tool actively misleads |
| **F7-1** | **Replace both palettes with EdgeTX's `lcdColorTable` (stock light) and one real community dark theme; keep the invented one as a third, clearly labelled "concept"** | **recommended** |
| F7-2 | Replace with stock only | loses the dark check entirely; themes vary hugely |
| F7-3 | Read the palette from `colors.cpp` at render time | brittle path dependency into the firmware tree; do it once by hand instead |

Whichever is chosen, **F7 lands before anything colour-related is judged
again**, or the fix for F0 gets reviewed in the same fiction that hid it.

### F7.3 Acceptance

`dev/shots/` regenerated with the real stock palette; F0's before/after
reviewed in it; the invented palette either gone or captioned "concept, not
EdgeTX" wherever it appears.

---

## 5. F1a — warning and critical are the same red (P2)

### F1a.1 Evidence

Stock theme: `WARNING = #e00000`, critical = fixed `RED = #ff0000`.
Perceptual distance **53** — the two states are the same colour to the eye.
(Normal vs either is ~445, comfortably distinct.)

### F1a.2 Why this is P2 and not P0

The design already routes severity through **three** channels, and only one
of them is hue:

1. the chip text — literally `WARN` vs `CRIT`;
2. the **critical pulse** at ~1 Hz, which exists precisely so severity
   survives greyscale and colour blindness (Tanda 4);
3. hue.

So the states remain distinguishable; the colour channel is merely wasted.
That is a real loss — hue is the fastest channel to read at a glance in a
cockpit — but it is not a failure.

### F1a.3 Options

| # | Option | Verdict |
|---|---|---|
| F1a-0 | Status quo | acceptable; the pulse and chip carry it |
| **F1a-1** | **Critical keeps fixed `RED`; warning takes a fixed amber** (`WARNING` is red on stock and cannot be relied on to be amber) | **recommended** — restores the hue channel, symmetric with F0-3 and the existing `crit` |
| F1a-2 | Warning keeps the role; critical moves to a darker red | fights the convention that critical is *the* red |
| F1a-3 | Distinguish by thickness or a second ring instead of hue | more code, more geometry, no clearer |

F1a-1's amber must clear 3 : 1 on both backgrounds — the same test F0-3
passed; a candidate needs measuring (`#b26a00`-ish region), which is a
five-minute job once F0's harness exists.

**Counter-argument, stated honestly:** taking `warn` off `COLOR_THEME_WARNING`
means a theme author who carefully picked their warning colour no longer sees
it. That is a genuine cost, and it is the reason F1a-0 is defensible. The
deciding question is whether this widget's three states should be legible on
*any* theme, or should defer to *this* theme — §12 Q3.

---

## 6. F1b — Gradient mode invents RGB (P2)

`theme.gradientColor` returns `lcd.RGB(0xdf - g, g, 0)` — the only colour path
in the widget that is neither a theme role nor a measured fixed colour. Its
green end is `#00df00`: **1.16 : 1** against the stock background, i.e. the
same failure as F0 but confined to one mode.

**Recommendation, unchanged from v1 in shape but now for a better reason:**
the ARC keeps the ramp (a large graphic; position carries the reading), and
the **value text takes the semantic role** — which after F0-3 is a colour
proven against both backgrounds. Plus: cap the ramp's green so the *arc* also
clears 3 : 1 both ways. Full pseudocode as in v1 §2, with `GRAD_GREEN = 0xa0`.

The v1 justification — "no API can do better" — was wrong (§1). The correct
justification is simpler: **a continuously varying hue cannot be guaranteed
legible against an unknown background, so it must not carry text.**

---

## 7. F2 — "no data" muting is incomplete (P2)

Measured on the object tree at `availability = "disconnected"`:

| element | Rail | Sections |
|---|---|---|
| value arc | 120 (muted) | 120 (muted) |
| reference bands | **200** | **255** |
| track | 90 | 90 |

The passive threshold bands are the brightest coloured elements on a gauge
announcing it has no data, and one of them is red. `applyColors` lowers band
opacity only for `key == "critical"`; `muted` is unhandled and `ui.sections`
is never touched after build.

**Recommended:** bands follow the gauge to `T.opacity.muted` when the key is
`muted`. Options and pseudocode as in v1 §3 — that analysis stands; it is
opacity, not palette, so F7 does not disturb it.

---

## 8. F3 / F4 / F5 / F6 — unchanged from v1

These are palette-independent and the v1 analysis holds. In brief:

- **F3** — 360° sweep: value and name 2 px apart with 18 px unused. Give the
  name to `stackTextRows` with the band bottom at the ring's **inner** edge
  (`cy + clearR`), so G-10 holds by construction. **Pre-existing**, verified
  against `git HEAD`.
- **F4** — 480×272: min/max thrown 202 px apart, name stacked under `min`.
  Cap the row to the value group's width and centre it — **before** the
  `minTextBox`/`maxTextBox` split.
- **F5** — needle crosses the value at scale extremes. **No action**:
  verified identical on `git HEAD`, owner-accepted in Tanda 5 3.13 / P2-5,
  and Tanda 7 B's larger value depends on that decision holding.
- **F6** — shots capture the pulse at inconsistent phases, so two critical
  scenes render visibly different reds. Settle every scene on one phase.

---

## 9. Sequencing

```
F7 (real palette in the tool)
      │
      ├─→ F0 (normal colour)  ──→  bench check on a stock-theme radio
      │        │
      │        └─→ F1a (warn/crit hue)   [needs F0's contrast harness]
      │        └─→ F1b (gradient text + capped ramp)
      │
      └─→ F2 (band muting)
F3, F4, F6 — independent, any time
```

1. **F7 first, always.** Judging F0 in the fiction that hid it is worthless.
2. **F0** next, own commit. Then **stop and bench-test** — this is the change
   that most needs a real radio, and the stock theme is the default case.
3. **F1a / F1b / F2** after the bench test confirms F0.
4. **F3 / F4 / F6** whenever; they are independent and cheap.

---

## 10. Risk register

| Risk | Finding | Likelihood | Mitigation |
|---|---|---|---|
| A background image defeats every contrast claim | F0, F1b | **certain for some users** | prefer roles the theme author guaranteed; treat ratios as guidance, not proof |
| `#1e8c46` looks dull on a dark theme (3.08 : 1) | F0-3 | medium | bench check; F0-4 (adaptive) is the escape hatch |
| Theme authors lose their chosen warning colour | F1a-1 | medium | §12 Q3 is exactly this trade |
| The real palette makes other, unrelated scenes look wrong | F7 | **high** | that is the point; budget a full re-review after F7 |
| `lcd.getColor` behaves differently on hardware than in the source read | F0-4 | low | only F0-4 depends on it; F0-3 does not |

---

## 11. Acceptance checklist

- [ ] `dev/svgkit.lua` renders EdgeTX's real stock palette (F7)
- [ ] normal state ≥ 3 : 1 against both reference backgrounds (F0)
- [ ] `main.lua` Accent default == `theme.lua` accent (F0)
- [ ] no band opacity exceeds the value arc's in any non-valid state (F2)
- [ ] `G-10` green; `dev/collide.lua` 18/18 (F3)
- [ ] 38 unit / 129+ lifecycle / 0 luacheck
- [ ] **bench test on a radio or Companion, stock theme** — the gate this
      whole document exists because we skipped

---

## 12. Decisions needed from the owner

| # | Question | My recommendation |
|---|---|---|
| 1 | **F7**: correct the render tool's palette before judging any colour? | **Yes, first.** Everything colour-related is unreviewable until then |
| 2 | **F0**: move the normal state off `COLOR_THEME_ACTIVE` to a fixed green (F0-3)? | **Yes** — `#1e8c46`, 3.64/3.08 |
| 3 | **F1a**: should the three states be legible on *any* theme (fixed amber) or defer to *this* theme (keep `COLOR_THEME_WARNING`)? | Lean **fixed** — an instrument's states should not depend on a theme author's taste; but this is a real trade and yours to make |
| 4 | **F0-4**: adaptive light/dark via `lcd.getColor`, or one fixed colour? | **Fixed now**; adaptive only if the bench test says it is needed |
| 5 | **Bench test as a gate after F0?** | **Yes** — four review rounds missed F0 because nothing ran on a radio |
| 6 | F3 / F4 / F6 — proceed? | Yes; independent and cheap |

---

*Nothing here is implemented. On a "go" I will work §9 in order, one commit
per concern, and report measured before/after — including the contrast table
re-measured against the real palette.*
