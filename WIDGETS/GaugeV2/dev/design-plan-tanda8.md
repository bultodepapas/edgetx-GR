# GaugeV2 — Tanda 8 plan: the colour foundation, and findings from the render review

**Author role:** senior developer, visual review of the generated render set,
then a source-level audit of the firmware's theme system.
**Baseline:** `feat/gauge-v2` @ `d94d37d52` (Tanda 7 A/B/C shipped).
Suites green: 38 unit, 129 lifecycle, 18/18 collision zones, 77 gallery scenes
with 0 render warnings, luacheck 0/33.
**Status:** **IMPLEMENTED.** §17 records what shipped, and the four claims in
this document that the implementation falsified — including one that reverses
§16's recommendation on F1a.
**Revision:** **v3.**
v1 was written from the render set alone. Auditing the firmware **falsified
three of its claims** (§1) and the headline finding changed completely.
v3 adds a **UI/UX design pass** (§3), which reframes the remedy: v2 was still
fixing colours one at a time, and the design lens replaces most of that with a
single structural rule — plus three findings an engineering review had no way
to surface (§10–§12).
**Date:** 9 August 2026.

---

## 0. Summary

| # | Finding | Severity | Verdict |
|---|---|---|---|
| **§3** | **Status and data share one colour channel** — the structural cause behind F0, F1a and F1b | **design** | **adopt the rule** |
| **F0** | The "normal" status colour is a button-background role — 1.13 : 1 on the stock theme | **P0** | fix |
| **F7** | `dev/svgkit.lua` renders an invented palette, not EdgeTX's — why none of this was visible | **P0 (tooling)** | fix first |
| **F8** | The state chip is a hairline outline, not a badge (1.19 : 1 fill) | **P1** | fix |
| **F9** | Normal vs warning has no non-colour channel; `ShowChip = Off` removes the only one | **P1** | fix |
| F1a | Warning and critical are both red on the stock theme (Δ 53) | P2 | **subsumed by §3 + F8** |
| F1b | Gradient mode invents RGB and ignores the theme | P2 | **eliminated by §3** |
| F2 | "No data" muting is incomplete: reference bands outshine the live gauge | P2 | fix |
| F10 | Micro zones signal state by hue alone | P2 | accept + document, probably |
| F3 | 360° sweep gives value and name 2 px while 18 px sits unused | P3 | fix (cheap) |
| F4 | 480×272 min/max reads as three unrelated labels | P3 | fix (cheap) |
| F5 | Needle crosses the value at scale extremes | P3 | **no action** — settled |
| F6 | Renders capture the critical pulse at inconsistent phases | P3 | fix in tooling |

**Read §3 first.** F0, F1a and F1b are three symptoms of one cause: the status
colour is asked to signal a state *and* stay legible as text on a background
the widget cannot see. Real instruments never do that — coloured arcs on the
dial face, plain numerals. Splitting the two channels fixes the class, and it
is also what makes the widget look modern rather than merely compliant.

**F0 is the sharpest symptom.** On EdgeTX's stock theme the "all clear" arc
and value render at **1.13 : 1** against the screen background — effectively
invisible. It scores 9.87 : 1 on a dark theme, which is why nobody saw it.

**F7 is why nobody saw it.** Every render ever reviewed for this widget was
drawn with a palette invented in `dev/svgkit.lua`, in which the normal state
is a green that does not exist in EdgeTX, on a dark background that is not the
stock theme. Fix the tool first or the next review inherits the blind spot.

**The design pass paid for itself twice:** it deleted work (F1b disappears, F1a
turns out to be *unsolvable* as stated — see §3.3, no amber can clear 3 : 1 on
both backgrounds) and it found two P1s an engineering review had no lens for
(F8, F9).

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

## 3. Design review — the reading model, and one structural rule

*Written from a UI/UX lens after §4–§9 were drafted. It does not add fixes to
that list so much as **replace** several of them with a rule that makes the
whole class go away.*

### 3.1 What this device actually is

This is not a dashboard on a desk. It is a **transmitter held at chest height,
outdoors, in daylight, by someone whose eyes are on an aircraft 100 m away.**
That single sentence invalidates the target most of this plan has been aiming
at:

- **The screen is glanced at, not read.** One to two fixations, ~200 ms, often
  in peripheral vision. Peripheral vision resolves *position, size, motion and
  gross colour* — not digits.
- **Sunlight crushes contrast.** An LCD in daylight loses far more contrast
  than any WCAG figure assumes, and many pilots wear polarised sunglasses,
  which can dim an LCD dramatically at some angles.
- **The moments that matter are the worst moments.** Low battery, lost link,
  overheating — read under stress, one-handed, with the model still flying.
- **The audience skews male, so ~8 % have a red-green colour deficiency**
  (deuteranopia/protanopia). Green→amber→red is the single worst ramp for
  exactly that population. See §11.

WCAG's 4.5 : 1 and 3 : 1 were written for a web page at arm's length in an
office. Here they are a **floor, not a target** — and, more importantly, they
are aimed at the wrong element. The pilot is not reading the number in flight;
they are reading **where the needle is** and **whether anything turned red**.

### 3.2 The rule: separate the STATUS channel from the DATA channel

Everything in §4–§8 is the same mistake in different costumes: **the status
colour is being asked to do two incompatible jobs at once** — signal a state
*and* remain legible as text on an unknown background.

Real instruments never do this. On an aircraft airspeed indicator the arcs are
green, yellow and red **on the dial face**; the numerals are plain white. The
colour lives on the *scale*, the data stays neutral. The same split runs
through every modern instrument UI worth copying — Garmin, the DJI Fly app,
Tesla's cluster: **a bold coloured ring, crisp neutral numerals, a coloured
badge for state.**

So:

| channel | carries | coloured by | why |
|---|---|---|---|
| **STATUS** | arc, rail/section bands, threshold marks, the state chip | the semantic status colour | large, peripheral, glanceable — hue works here |
| **DATA** | value, unit, source name, min/max text | the theme's **text** role, always | must be legible at any size on any background; hue adds nothing you can read |

Adopting this one rule:

- fixes the **text half of F0** without choosing a colour at all;
- **eliminates F1b entirely** — a gradient cannot tint text that is never
  tinted;
- removes the whole *class* of "which colour is legible as text" findings,
  permanently;
- and it is what makes the widget look like an instrument rather than a
  webpage.

**The one deliberate exception:** at **critical**, tint the value red. That is
the single state where alarm outranks neutral legibility, it is a universal
convention, and EdgeTX's fixed `RED` measures 3.39 : 1 light / 3.30 : 1 dark —
it clears the bar on both. Warning does *not* get this: amber cannot (§3.3).

### 3.3 Why "one fixed colour per state" cannot work — and what does

Measured against both reference backgrounds, from real design systems:

| candidate | vs light | vs dark | passes both |
|---|---|---|---|
| Tailwind emerald-600 `#059669` | 3.20 : 1 | 3.50 : 1 | yes |
| Material green-700 `#388e3c` | 3.49 : 1 | 3.21 : 1 | yes |
| **Tailwind amber-600 `#d97706`** | 2.70 : 1 | 4.14 : 1 | **no** |
| **Material amber-700 `#ffa000`** | 1.73 : 1 | 6.46 : 1 | **no** |
| **GitHub attention `#9a6700`** | 4.13 : 1 | 2.71 : 1 | **no** |

**No amber clears 3 : 1 against both a near-white and a dark background.**
Amber is mid-luminance by nature; it is bright against dark and dim against
light, always. This is not a tuning problem, and it means §4's "pick a fixed
colour per state" strategy **cannot be completed** — warning has no answer.

The way out is the one modern dashboards already use: **stop asking the status
colour to contrast with an unknown background, and give it its own ground.**

A **filled badge** — status colour as the fill, label on top — is
*self-grounding*: its contrast is between the fill and its own label, both of
which we control. It works on a light theme, a dark theme, and a
`background.png` photograph alike.

| status fill | on black | on white | label |
|---|---|---|---|
| emerald-500 `#10b981` | **8.28 : 1** | 2.54 : 1 | black |
| amber-500 `#f59e0b` | **9.78 : 1** | 2.15 : 1 | black |
| red-600 `#dc2626` | 4.35 : 1 | **4.83 : 1** | white |

8–10 : 1 — twice what any "safe" flat colour achieved. And because the badge
carries its own contrast, the fills can be **bright, saturated and modern**
(the Tailwind 500 family) instead of the muted 3.1 : 1 compromises §4 was
driven to. Distinguishability of that set: normal↔warning **411**,
warning↔critical **247**, normal↔critical **458** — all far above the ~60
confusion threshold.

**This is the answer to "beautiful and modern" and "legible" at the same
time.** They stopped being in tension the moment the colour got its own
ground.

### 3.4 What this replaces

| was | becomes |
|---|---|
| F0-3: pick a muted fixed green (3.64 : 1) for arc **and** text | arc takes a **bright** status colour; text takes a theme text role. No compromise colour needed |
| F1a: pick a fixed amber for warning | impossible (§3.3) — warning is carried by a **filled badge** plus the arc |
| F1b: gradient must not tint text | falls out of the rule for free |
| F0's chip at 1.19 : 1 | inverted into the badge — see §10 (F8) |

### 3.5 What is still missing from this plan

Four review rounds, zero users. There is no task analysis, no glance test, no
outdoor test, and no colour-vision check anywhere in Tanda 5–8. The cheapest
high-value validation is not another contrast table — it is **putting it on a
radio, walking outside, and glancing at it from 1 m while doing something
else**. If the state is not readable in under a second, no ratio in this
document matters.

---

## 4. F0 — the "normal" status colour is a UI-background role (P0)

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

## 5. F7 — the render tool paints a palette EdgeTX does not have (P0, tooling)

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

## 6. F1a — warning and critical are the same red (P2)

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
*any* theme, or should defer to *this* theme — §13 Q3.

---

## 7. F1b — Gradient mode invents RGB (P2)

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

## 8. F2 — "no data" muting is incomplete (P2)

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

## 9. F3 / F4 / F5 / F6 — unchanged from v1

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

## 10. F8 — the state chip is an outline, not a badge (P1, design)

### F8.1 Evidence

Today: pill fill = `COLOR_THEME_SECONDARY2`, label = the status colour. On the
stock theme that is a `#b6e0f2` fill at **1.19 : 1** against the screen
background — the fill is invisible. The pill reads only through its 1 px
`chipEdge` outline, and the *word* inside carries the status colour at
3.4–4.3 : 1.

So the most important glanceable element in the widget — the thing that says
`CRIT` — is a hairline outline containing thin coloured text, on a screen
looked at for ~200 ms in sunlight.

It is also the **only** non-colour differentiator between normal and warning
(§11), which makes its weakness compound.

### F8.2 Options

| # | Option | Verdict |
|---|---|---|
| F8-0 | Status quo | rejected: the weakest element carries the strongest message |
| **F8-1** | **Invert it: fill = status colour, label = black/white chosen by the fill's luminance** | **recommended** — 8–10 : 1, self-grounding, and the modern badge idiom |
| F8-2 | Keep the fill, thicken the outline to the status colour | better, but still a thin cue peripherally |
| F8-3 | Drop the pill, colour the text only | worse: the pill *shape* is what reads at a glance |

### F8.3 Pseudocode

```lua
-- The pill is a BADGE: the status colour is its GROUND, not its ink.
--
-- It used to be a SECONDARY2 fill (a "label/button background" role) with the
-- status colour as text - which on the stock theme is a #b6e0f2 fill at
-- 1.19:1 against the screen, i.e. an invisible pill outlined by a 1 px edge.
-- A filled badge is SELF-GROUNDING: its contrast is between the fill and its
-- own label, both of which we control, so it survives a light theme, a dark
-- theme and a background.png photograph alike - which no flat colour can
-- (see 3.3: no amber clears 3:1 against both backgrounds, ever).
-- Measured: 8.3:1 (emerald), 9.8:1 (amber), 4.8:1 (red).
local fill = T.stateColor(key, widget.accent)
setProp(widget, ui.chip, "color", fill)
setProp(widget, ui.stateLabel, "color", T.labelOn(fill))
```

`T.labelOn(fill)` picks `PRIMARY1` or `PRIMARY2` by the fill's own luminance,
read through `lcd.getColor` (§1) — the first genuinely good use of that API.
For the muted states (`NO LINK`, `STALE`, `NO DATA`, `NO SOURCE`) the fill is
`DISABLED`, which keeps them recessive by design.

---

## 11. F9 — colour-vision deficiency: normal vs warning has no second channel (P1)

### F9.1 Evidence

Non-colour channels per state, read from `renderer.lua`:

| state | chip text | pulse | hue |
|---|---|---|---|
| normal | `""` — **nothing** | no | green |
| warning | `WARN` | no | amber |
| critical | `CRIT` | **yes** | red |

`stateText` returns `""` for normal, so **normal vs warning is distinguished
by the chip's presence and by hue — nothing else.** And the chip is optional:
`L.showState = mode ~= "micro" and cfg.showChip ~= false`, so **`ShowChip =
Off` removes it from every state**, leaving green-vs-amber as the sole
signal — precisely the discrimination ~8 % of a heavily male audience cannot
make.

`DOCS.md` §4.1 says of that option: *"Off leaves colour and the pulse as the
only state signal"* — but **there is no pulse on warning**. The documentation
overstates what remains.

### F9.2 Options

| # | Option | Verdict |
|---|---|---|
| F9-0 | Status quo | rejected: a safety signal invisible to 8 % of users |
| **F9-1** | **`ShowChip = Off` suppresses the chip only in the NORMAL state** (where it is empty anyway); warning and worse always show it | **recommended** — costs the option nothing real |
| F9-2 | Give warning its own motion (slower pulse than critical) | a second channel for everyone; more per-frame work, and two pulse rates may read as noise |
| F9-3 | Shape cue — e.g. a marker on the needle at warning | most code, least convention |
| F9-4 | Document it and move on | rejected |

F9-1 is nearly free: the chip already renders `""` in the normal state, so
"always on for warning+" hides nothing the user asked to hide.

**Also fix the doc**: `DOCS.md`'s pulse claim is wrong for warning.

---

## 12. F10 — micro zones signal state by hue alone (P2)

`L.showState = mode ~= "micro"` — a 60×60 gauge shows no chip in any state, so
warning and critical are hue-only there, with the pulse as the only extra
channel at critical. Combined with F9 this is the same gap in a zone too small
to fix with text.

**Recommended:** let the **arc** carry the second channel where a chip cannot
fit — the critical pulse already lives there; extend a subtler version to
warning, scoped to micro zones (F9-2's mechanism, narrowly applied).
**Cheaper alternative:** accept it, and document micro zones as an ambient
at-a-glance display rather than a diagnostic one. Given a 60×60 dial is
already a deliberate reduction, the cheap answer may be the right one.

---

## 13. Sequencing

```
F7  real palette in the render tool
      │
      └─→ §3  channel split: DATA text -> theme text role
                (fixes F0's text half, deletes F1b outright)
              │
              ├─→ F0   status palette: bright arc colours
              ├─→ F8   chip becomes a filled badge  (+ T.labelOn)
              └─→ F9   chip always on for warning+
                        │
                        └─→ BENCH TEST, stock theme, outdoors  ◀── gate
                                  │
                                  └─→ F2, F10, and the F1a decision
F3, F4, F6 — independent, any time
```

1. **F7 first, always.** Judging any of this in the fiction that hid it is
   worthless.
2. **§3's channel split next** — one rule, and it is subtractive: it removes
   colour decisions rather than adding them. Do it before choosing any palette,
   because it changes *which* colours still need choosing.
3. **F0 + F8 + F9 together**, as one design change with one visual identity.
   Splitting them across commits would mean reviewing three half-states of the
   same look.
4. **Then stop and bench-test.** Stock theme, outdoors, glance from 1 m. This
   is the gate, not a formality — four review rounds missed F0 for want of it.
5. **F2, F10, F1a** after the bench test says the new identity works.
6. **F3 / F4 / F6** whenever; independent and cheap.

---

## 14. Risk register

| Risk | Finding | Likelihood | Mitigation |
|---|---|---|---|
| A background image defeats every contrast claim | F0, F1b | **certain for some users** | prefer roles the theme author guaranteed; treat ratios as guidance, not proof |
| `#1e8c46` looks dull on a dark theme (3.08 : 1) | F0-3 | medium | bench check; F0-4 (adaptive) is the escape hatch |
| Theme authors lose their chosen warning colour | F1a-1 | medium | §13 Q3 is exactly this trade |
| The real palette makes other, unrelated scenes look wrong | F7 | **high** | that is the point; budget a full re-review after F7 |
| `lcd.getColor` behaves differently on hardware than in the source read | F0-4 | low | only F0-4 depends on it; F0-3 does not |

---

## 15. Acceptance checklist

- [ ] `dev/svgkit.lua` renders EdgeTX's real stock palette (F7)
- [ ] normal state ≥ 3 : 1 against both reference backgrounds (F0)
- [ ] `main.lua` Accent default == `theme.lua` accent (F0)
- [ ] no band opacity exceeds the value arc's in any non-valid state (F2)
- [ ] `G-10` green; `dev/collide.lua` 18/18 (F3)
- [ ] 38 unit / 129+ lifecycle / 0 luacheck
- [ ] **bench test on a radio or Companion, stock theme** — the gate this
      whole document exists because we skipped

---

## 16. Decisions needed from the owner

| # | Question | My recommendation |
|---|---|---|
| 1 | **F7**: correct the render tool's palette before judging any colour? | **Yes, first.** Everything colour-related is unreviewable until then |
| 2 | **§3**: adopt the channel split — status colour on the arc/bands/badge, **data text always on a theme text role**, with critical the one exception? | **Yes.** It is the whole design in one rule, and it *deletes* work rather than adding it |
| 3 | **F0 + F8**: bright modern status palette (emerald / amber / red at the 500 level) with the chip inverted into a filled badge? | **Yes** — it is the only combination that is both beautiful and legible; the badge is what makes bright colours safe (8–10 : 1) |
| 4 | **F9**: make `ShowChip = Off` apply only to the normal state, so warning and critical always show a badge? | **Yes** — the alternative leaves a safety signal invisible to ~8 % of pilots |
| 5 | **F1a**: with the badge carrying warning, is warn-vs-crit hue still worth chasing? | **No — drop it.** §3.3 shows no amber can clear 3 : 1 on both backgrounds anyway; the badge solves what F1a was for |
| 6 | **Bench test as a hard gate** after F0/F8/F9, on a stock-theme radio, outdoors? | **Yes.** This is the one that matters most |
| 7 | **F10**: micro zones — add a warning pulse, or document them as ambient-only? | **Document.** A 60×60 dial is already a deliberate reduction |
| 8 | F2 / F3 / F4 / F6 — proceed? | Yes; independent and cheap |

### A note on "beautiful"

The two goals stopped competing at §3.3. Chasing one flat colour per state
forced everything toward muted 3.1 : 1 compromises — safe, and drab. Giving
the status colour **its own ground** (a filled badge, a bold arc against a
neutral track) lets the palette be bright and confident *and* measure 8–10 : 1.
That is the same move Garmin, DJI and every modern cluster already made, and
it is why they look good rather than merely legible.

---

## 17. Implementation record

**Status: implemented**, §13 in order, on `feat/gauge-v2`. Suites after: 38
unit, 137 lifecycle, 18/18 collision zones, 77 gallery scenes with 0 render
warnings, luacheck 0/31.

Written last, and it exists mostly to record where **this plan was wrong**.
Four of its load-bearing claims did not survive contact with a measurement or a
render, and one of them reverses a recommendation in §16.

### 17.1 What the plan got wrong

**1. "No amber clears 3 : 1 against both backgrounds" (§3.3) — FALSE.**

The claim was drawn from five catalogue ambers, all of which do fail. But the
constraint is on *relative luminance*, not on hue: a fixed colour passes both
backgrounds iff its luminance lands in **[0.189, 0.247]**, a window 0.058 wide.
Design-system ambers miss it because they are tuned for one background at a
time, not because amber cannot sit there. Searching the RGB565 lattice for the
best warm orange returns **`#c86000` at 3.34 : 1 light / 3.35 : 1 dark** — and
3.35 : 1 is the arithmetic maximum any colour of any hue can reach against both.

So §3.3's conclusion ("warning has no answer", "§4's strategy cannot be
completed") was wrong, and with it **§16 Q5's recommendation to drop F1a**.
F1a is implemented: warning is a fixed amber, 213 perceptual units from
critical's red instead of the stock theme's 53. The hue channel that four
rounds of review wrote off as unrecoverable is recovered.

The narrower point stands, and is what made the window worth finding: a colour
picked by eye will miss a 0.058-wide target almost every time.

**2. The badge's "8–10 : 1" (§3.3, §16 Q3) — not reachable here.**

Those figures come from the Tailwind 500 family, whose luminance is far above
the window. A fill that must ALSO serve as the arc is pinned inside the window,
and at that luminance the best a black or white label can do is bounded at
about 5.9 : 1. Measured after RGB565 quantisation: **5.32 : 1 normal,
5.33 : 1 warning, 5.25 : 1 critical, 6.36 : 1 muted.**

Decoupling them — a bright badge and a darker arc — would buy the extra ratio
at the cost of two different greens meaning "good" in one widget. Not worth it.
The improvement over what shipped is still large: CRIT was **2.91 : 1** on the
old pill, under the floor.

**3. F1b's "cap the ramp's green at `0xa0`" (§7) — does not work.**

Capping the green end pulls the ramp's RED end down with it, and the worst case
moves from the light background to the dark one (1.63 : 1). The ramp's real
problem is that luminance is not linear in sRGB values, so mixes between two
in-window endpoints wander out of the window — through olive, which is bright.
Replaced by interpolation between the three status colours with the mix scaled
back into the window: **worst case 3.02 : 1 across all 21 steps**, against
1.54 : 1 before. Hue varies, brightness does not, which is what a dial's colour
scale should do anyway.

**4. §3.5's "no glance test" was the right criticism, and it caught four bugs
that no measurement did.** They are listed in 17.3, and the plan should be read
as under-weighting that section rather than over-weighting it.

### 17.2 What was implemented

| § | Change | Result |
|---|---|---|
| F7 | `dev/svgkit.lua` palettes are EdgeTX's real `defaultColors` (`stock`, default) plus a real dark theme | plus two more invented palettes found and removed — see 17.3 |
| §3 | value/unit/name/min-max take `COLOR_THEME_PRIMARY1`; status colour confined to arc, bands, marks, badge | F1b eliminated as predicted |
| F0 | `accent` → `#209058`, `warn` → `#c86000`, `crit` → `lcd.RGB(0xff,0,0)`; `main.lua` default follows | 1.13 : 1 → 3.35 : 1 |
| F1a | **implemented, not dropped** (see 17.1) | warn↔crit distance 53 → 213 |
| F1b | constant-luminance ramp between the status colours | 1.54 : 1 → 3.02 : 1 worst |
| F8 | badge inverted: status colour is the fill, label is `theme.labelOn(fill)` | 2.91 : 1 → 5.2 : 1 at CRIT |
| F9 | `ShowChip = Off` hides only the informational badges; the row is always reserved | WARN/CRIT survive the option |
| F2 | section bands, rail bands and bar marks follow the gauge into `muted` | bands 200/255 → 120, equal to the arc |
| F3 | 360° name distributed to the ring's INNER edge | value→name gap 2 px → 9 px |
| F4 | min/max row capped to the pair's own width | 202 px apart → 106 px |
| F6 | `dev/scenes.lua` settles the critical pulse on its crest | 13/13 critical scenes in one phase |
| F10 | documented: micro zones are ambient, not diagnostic | `DOCS.md` §4.6 |
| F5 | no action, as planned | needle still crosses the value at the extremes |

Supporting work the plan did not anticipate: `tests/mock_env.lua` now models
EdgeTX's real colour encoding (`COLOR2FLAGS`, `RGB2FLAGS`, RGB565 quantisation),
its real constant values, and `lcd.getColor` **including its guard** — which
returns nil for the fixed literals like `RED`, and is why the widget's status
colours are `lcd.RGB` literals rather than the `RED` constant.

### 17.3 What only the renders caught

Four defects survived every suite, every contrast table and the whole of
§§4–12. All four were found by rasterising the catalogue and looking at it.

1. **A hidden badge left its text behind.** With `ShowChip = Off` and no link,
   the pill and its outline hid but the *label* did not — "NO LINK" floating
   bare on the dial, which is the exact defect the pill was introduced to fix
   (P1-10). Invisible to the suite because visibility of the three objects was
   never asserted together; invisible to the render checker because bare text
   inside the zone is not a warning. Now pinned across both painters, every
   state and both settings of the option.
2. **The badge outline was a third colour.** `SECONDARY1` made sense under a
   `SECONDARY2` fill; over a status colour it is a blue hairline around an
   amber badge. It takes the badge's own ink now.
3. **The value went red at critical and the unit stayed blue** — "22" and "dB"
   are one token and were painted as two. Same split made a stale `78` grey
   beside a live-looking blue `dB`. The unit now follows the value in the two
   exception states only, keeping the ordinary hierarchy intact.
4. **The gallery rendered an ink the radio would not choose.** Once
   `theme.labelOn` reads the theme, a scene built under the stock colour table
   and repainted in the dark palette is a lie: it showed white on the amber
   badge at 3.94 : 1 where a dark-theme radio picks black at 5.32 : 1. The
   tools now point the mock's colour table at the palette before building, and
   the gallery builds once per theme.

Two more palettes were found during this: `dev/preview.lua` and
`dev/audit-preview.lua` each carried their own invented table, so F7's fix in
`svgkit.lua` would have left two tools still lying. Both now read svgkit's.

And one place the plan was right where the render first suggested otherwise:
**F3.** The 360° render looked worse at a glance because the needle crosses
the name — but an A/B against the unmodified layout shows the needle crosses it
identically in both (that is F5, owner-accepted), while the value→name gap goes
from cramped to comfortable. Kept.

### 17.4 Still owed

**The bench test (§16 Q6) has not happened.** Everything above is measured or
rendered, never seen on a radio, outdoors, at arm's length. §3.5 called that
the cheapest high-value validation left and it still is — in particular for the
one judgement no ratio settles: whether `#209058` and `#c86000` read as
*confidently* different at 100 m with the sun behind you.

---

*Implemented on `feat/gauge-v2`. Renders of the new identity in both the stock
light theme and a real dark theme are in `dev/shots/gallery/`.*
