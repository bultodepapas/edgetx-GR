# GaugeV2 — Tanda 8 plan: findings from the render review

**Author role:** senior developer, visual review of the generated render set.
**Baseline:** `feat/gauge-v2` @ `d94d37d52` (Tanda 7 A/B/C shipped).
Suites green: 38 unit, 129 lifecycle, 18/18 collision zones, 77 gallery scenes
with 0 render warnings, luacheck 0/33.
**Status:** **PROPOSED — awaiting owner decision.** Nothing here is
implemented. §10 lists what needs a yes/no.
**Date:** 9 August 2026.

---

## 0. Summary

Six findings from reviewing all 336 generated images (83 scenes × SVG+PNG ×
dark/light, plus 2 gallery sheets) as grouped contact sheets, then verifying
every suspicion against the object tree rather than the picture.

| # | Finding | Severity | Verdict |
|---|---|---|---|
| **F1** | Gradient mode ignores the theme and fails contrast — at **opposite ends in each theme** | **high** | fix |
| **F2** | "No data" muting is incomplete: reference bands outshine the live gauge | **medium** | fix |
| **F3** | 360° sweep gives value and name 2 px while 18 px sits unused | low | fix (cheap) |
| **F4** | 480×272 min/max reads as three unrelated labels | low | fix (cheap) |
| **F5** | Needle crosses the value at scale extremes | low | **no action** — settled design |
| **F6** | Renders capture the critical pulse at inconsistent phases | low | fix in tooling |

**F1 is the only one I would call a defect.** It is a measurable
accessibility failure on a device used outdoors, and the light theme exists
precisely for that case.

Two findings were checked against `git HEAD` before being written down, and
are **pre-existing, not regressions from Tanda 7**: F3 and F5.

---

## 1. Method

All renders regenerated from scratch, then verified:

```sh
lua5.3 dev/shots.lua   ./ ./dev/shots/       --theme dark
lua5.3 dev/shots.lua   ./ ./dev/shots/light/ --theme light
lua5.3 dev/gallery.lua ./
```

Contrast figures are WCAG 2.x relative-luminance ratios computed against the
palette `dev/svgkit.lua` renders with — panel `#171c24` (dark) and `#f7f9fb`
(light) — which mirrors the EdgeTX theme roles it stands in for. Layout
figures come from driving the widget through `create → update → refresh`
against `tests/mock_env.lua` and reading `widget.layout` / `widget.ui`.

**A hard constraint, verified in the firmware source of this tree.**
`lcd.RGB` (`radio/src/lua/api_colorlcd.cpp:1000`, exported at :1478) only
*builds* a colour from components. `colorToRGB` is C-side only and is **not**
exported to Lua, and nothing else returns the RGB behind a `COLOR_THEME_*`
role. So a Lua widget:

- **cannot** read a theme role's RGB, therefore cannot interpolate between
  roles to build a theme-correct ramp, and
- **cannot** detect whether the active theme is light or dark by inspecting
  one.

This rules out the obvious fixes for F1 and drives the recommendation. If a
future firmware exposes either, F1's option **F1-2** becomes available and is
strictly better.

---

## 2. F1 — Gradient mode ignores the theme and fails contrast

### F1.1 Evidence

`theme.gradientColor(t)` returns `lcd.RGB(0xdf - g, g, 0)` with `g = 0xdf*t`
— fixed RGB, never a theme role. It is the **only** colour path in the widget
that does not go through `T.stateColor`, and the only one that ignores the
Accent option.

Contrast of the value text it produces, measured across the ramp:

| t | colour | vs dark bg | vs light bg |
|---|---|---|---|
| 0.00 | `#df0000` | 3.37 : 1 | 4.81 : 1 |
| 0.20 | `#b32c00` | **2.67 : 1** | 6.07 : 1 |
| 0.30 | `#9d4200` | **2.62 : 1** | 6.19 : 1 |
| 0.50 | `#706f00` | 3.23 : 1 | 5.02 : 1 |
| 0.70 | `#439c00` | 4.88 : 1 | 3.32 : 1 |
| 0.80 | `#2db200` | 6.09 : 1 | **2.66 : 1** |
| 1.00 | `#00df00` | 9.41 : 1 | **1.72 : 1** |

For comparison, every other colour mode uses theme roles and passes
everywhere:

| role | dark | light |
|---|---|---|
| green (`#3fb950` / `#1a7f37`) | 6.73 : 1 | 4.81 : 1 |
| red (`#f85149` / `#cf222e`) | 5.10 : 1 | 5.07 : 1 |

So the ramp fails **at opposite ends in each theme**: the green end collapses
on light (1.72 : 1 — the "all clear" reading is the least readable thing on
the screen), and the red-to-amber middle drops to 2.6 : 1 on dark. This is
worse than the "light theme green" I first reported: the ramp is unsafe in
both themes, just in different places.

Visible in `dev/shots/light/color-gradient-ok.png` next to
`dev/shots/light/st-normal.png`: the same value, one a pale wash, the other
crisp.

### F1.2 Why the obvious fixes do not work

A single fixed colour **cannot** satisfy AA (4.5 : 1) on both themes. For
4.5 : 1 against light the foreground luminance must be ≤ 0.171; against dark
it must be ≥ 0.226. The intervals do not intersect — this is arithmetic, not
a tuning problem. Any fixed ramp is a compromise, and per §1 the widget
cannot detect the theme to choose between two ramps.

Non-text contrast (WCAG 1.4.11, graphical objects) is 3 : 1, and *that* is
satisfiable by a single colour: luminance in [0.134, 0.282] clears 3 : 1
against both backgrounds. That is the opening the recommendation uses.

### F1.3 Options

| # | Option | Text contrast | Arc | Keeps the feature | Verdict |
|---|---|---|---|---|---|
| F1-0 | Status quo | 1.72–9.41, theme dependent | ramp | yes | rejected: the defect |
| F1-1 | Darken the whole ramp to a mid band | ~3.3–4.9, **never AA** | ramp | yes | half a fix; text still sub-AA |
| **F1-2** | Detect the theme, ship two ramps | AA both | ramp | yes | **impossible today** (§1); revisit if firmware exposes it |
| **F1-3** | **Value TEXT uses the semantic role; ARC keeps the ramp** | **4.81–6.73, AA both** | ramp | yes | **recommended** |
| F1-4 | F1-3 **+ cap the ramp's green channel at `0xa0`** so the arc clears 3 : 1 both ways | AA both | ramp, muted on dark | yes | **recommended companion** — needs an eye check |
| F1-5 | Drop Gradient; alias it to Threshold | n/a | n/a | **no** | rejected: removes a shipped option |
| F1-6 | Blend role colours by opacity toward the background | worse — opacity blending *reduces* contrast | — | partly | rejected |

**F1-3 is the core.** The contrast failure is specifically the *text*. A
12 px-thick arc is a large graphical object whose **position** carries the
reading; its hue is secondary, and the state chip plus the value already carry
the semantics. Colouring the value text by `data.state` — exactly what every
other mode does — makes it theme-correct and AA everywhere, and costs the
Gradient mode nothing a user would notice, because a number that changes hue
continuously was never the point of the feature. The *arc* is.

**F1-4 is worth doing with it** but is a visual change on the dark theme
(vivid green → a more muted green), so it wants an eye check. Measured for the
capped ramp:

| end | colour | vs dark | vs light |
|---|---|---|---|
| green | `#00a000` | 4.91 : 1 | 3.30 : 1 |
| red | `#df0000` (unchanged) | 3.37 : 1 | 4.81 : 1 |

Red is left alone: it already clears 3 : 1 both ways, and darkening it fails
on the dark theme (`#900000` → 1.78 : 1).

### F1.4 Pseudocode

**`renderer.lua` — `applyColors`**

```lua
local function applyColors(widget, key)
  local ui = widget.ui
  local c = resolveColor(widget, key)
  local opa = (key == "muted") and T.opacity.muted or T.opacity.full
  setProp(widget, ui.valueArc, "color", c)
  setProp(widget, ui.valueArc, "opacity", opa)

  -- The value TEXT never takes the gradient ramp (Tanda 8 F1). The ramp is
  -- fixed RGB - the only colour path in the widget that is not a theme role
  -- - and no Lua API exposes the RGB behind a role, so it cannot be derived
  -- from the theme or adapted to it. Measured: the green end reads 1.72:1 on
  -- the light theme and the red-to-amber middle 2.62:1 on the dark one, where
  -- every theme role clears 4.8:1 in both. A large arc can carry a hue that
  -- is merely visible; a NUMBER has to be readable. The arc keeps the ramp -
  -- that is the feature - and the text falls back to the semantic role, which
  -- is what every other colour mode already uses.
  local textColor = c
  if string.sub(key, 1, 4) == "grad" then
    textColor = T.stateColor(widget.data.state or "normal", widget.accent)
  end
  setProp(widget, ui.valueLabel, "color", textColor)
  ...
```

`bar.lua` needs the identical two lines where it sets `ui.valueLabel` colour —
or, better, the branch moves into a shared `R.valueTextColor(widget, key)` so
the two renderers cannot drift (the Tanda 6 F-15 lesson).

**`theme.lua` — the capped ramp (F1-4)**

```lua
-- Continuous red -> amber -> green ramp (Gradient colour mode).
--
-- GREEN_MAX is not 0xdf. Green carries most of the luminance in sRGB, so a
-- full-intensity green is the brightest thing the widget can draw - great on
-- the dark theme (9.41:1) and nearly invisible on the light one (1.72:1).
-- Capping the green channel puts the whole ramp inside the luminance band
-- [0.134, 0.282] that clears the 3:1 non-text contrast floor against BOTH
-- theme backgrounds (measured: 4.91:1 dark / 3.30:1 light at the green end).
-- Red is deliberately left at full: it already clears 3:1 both ways, and
-- darkening it fails on the dark theme (1.78:1).
-- No single colour can clear the 4.5:1 TEXT floor on both themes - the
-- required luminance intervals do not intersect - which is why the value
-- text does not use this ramp at all (renderer.applyColors, Tanda 8 F1).
local GRAD_RED, GRAD_GREEN = 0xdf, 0xa0

function M.gradientColor(t)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return lcd.RGB(floor(GRAD_RED * (1 - t)), floor(GRAD_GREEN * t), 0)
end
```

### F1.5 Tests

```lua
test("F1: the gradient value text uses a theme role, not the ramp", function()
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Gradient" })
  local T = w.mods.theme
  for _, v in ipairs({ 10, 45, 78 }) do
    mock.setValue(ID_RSSI, v)
    refresh(w, 3)
    assertTrue(string.sub(w.frame.colorKey, 1, 4) == "grad",
      "still in the gradient ramp for the ARC")
    local want = T.stateColor(w.data.state, w.accent)
    assertEq(w.ui.valueLabel.props.color, want,
      "value text follows the semantic role at value " .. v)
    assertTrue(w.ui.valueArc.props.color ~= want
      or w.data.state == nil, "the arc still carries the ramp")
  end
end)

test("F1: the bar agrees with the dial about gradient text", function()
  -- one implementation per concept (Tanda 6 F-15)
  local d = newWidget(nil, { Source = ID_RSSI, ColorMode = "Gradient" })
  local b = newWidget({ x = 0, y = 0, w = 300, h = 70 },
    { Source = ID_RSSI, ColorMode = "Gradient", Style = "Bar" })
  mock.setValue(ID_RSSI, 45); refresh(d, 3); refresh(b, 3)
  assertEq(b.ui.valueLabel.props.color, d.ui.valueLabel.props.color,
    "bar and dial pick the same value-text colour")
end)
```

A contrast unit test is deliberately **not** proposed: the widget emits theme
role *flags*, not RGB, so the ratio is a property of the firmware theme, not
of this code. The numbers in F1.1 belong in the review record (this document),
not in an assertion that would only ever re-measure `dev/svgkit.lua`'s
stand-in palette.

### F1.6 Files, risk, acceptance

| | |
|---|---|
| **Files** | `renderer.lua` (`applyColors`, + a shared helper), `bar.lua` (call the helper), `theme.lua` (F1-4 only), `tests/smoke_test.lua` |
| **Perf** | one `string.sub` on a colour change only — colour changes are already gated by `key ~= frame.colorKey` |
| **Renders changed** | `color-gradient-ok`, `color-gradient-crit`, both themes |
| **Risk** | F1-3: none — strictly increases contrast. F1-4: changes the dark-theme look of an arc some users chose *for* its vividness |
| **Rollback** | two independent commits; `GRAD_GREEN` is one constant |
| **Acceptance** | gradient value text equals `T.stateColor(state)` at every sampled value, dial and bar agree, suites green, renders eyeballed in **both** palettes |

---

## 3. F2 — "No data" muting is incomplete

### F2.1 Evidence

Driven to `availability = "disconnected"` (NO LINK) and read off the object
tree:

| element | Rail mode | Sections mode |
|---|---|---|
| value arc | **120** (muted) | **120** (muted) |
| value text | muted role | muted role |
| reference bands | **200** | **255** |
| track | 90 | 90 |
| ticks | 255 | 255 |

Tokens: `muted = 120`, `railBand = 200`, `railBandCrit = 160`, `full = 255`.

So on a gauge that is announcing it knows nothing, the passive threshold
bands are the **brightest coloured elements on screen** — nearly 70 % more
opaque than the live arc in Rail mode, and fully opaque in Sections. One of
those bands is red. At a glance it reads as a critical reading.

`applyColors` lowers band opacity only for `key == "critical"`
(`railBandCrit`); the `muted` key is not handled, and `ui.sections` opacity is
never touched after build.

Visible in `dev/shots/light/st-nolink.png`, where the effect is strongest: the
value is grey, the arc is grey, and the red band is the first thing the eye
lands on.

### F2.2 Options

| # | Option | Result | Verdict |
|---|---|---|---|
| F2-0 | Status quo | bands outrank the live gauge | rejected |
| **F2-1** | **Bands drop to `muted` (120) when the key is `muted`** | nothing outranks anything | **recommended** |
| F2-2 | Bands drop to the track's 90 | bands recede *below* the arc | good too; slightly more emphatic |
| F2-3 | Hide the bands entirely | loses the scale reference exactly when the user is diagnosing | rejected |
| F2-4 | Dim *everything* including ticks and track | the track is already at 90; ticks are neutral grey and carry the scale | rejected: no benefit, more code |

F2-1 keeps the hierarchy flat and needs one expression. F2-2 is defensible if
the owner wants the no-data state to read as more obviously inert.

### F2.3 Pseudocode

```lua
  -- Reference bands follow the gauge into the muted state (Tanda 8 F2).
  -- They are the SCALE, not a reading: while the widget has no data they must
  -- not be the brightest thing on it. Measured before this: Rail bands sat at
  -- 200 and Sections bands at 255 against a value arc muted to 120, so a red
  -- threshold band was the most prominent element on a gauge showing NO LINK.
  local bandOpa = T.opacity.railBand
  if key == "critical" then
    -- P1-3 (Tanda 5 3.6): one step dimmer so the full-red arc stays foreground
    bandOpa = T.opacity.railBandCrit
  elseif key == "muted" then
    bandOpa = T.opacity.muted
  end
  if ui.rails then
    for _, rail in ipairs(ui.rails) do
      setProp(widget, rail, "bgOpacity", bandOpa)
    end
  end
  if ui.sections then
    for _, sec in ipairs(ui.sections) do
      setProp(widget, sec, "color", T.stateColor(sec.role, widget.accent))
      -- Sections bands were painted at build time at full opacity and never
      -- touched again; they need the same muted treatment.
      setProp(widget, sec, "bgOpacity",
              (key == "muted") and T.opacity.muted or T.opacity.full)
    end
  end
```

Note the asymmetry: Rail bands live at `railBand` (200) normally, Sections
bands at `full` (255), because Sections *is* the scale display. Only the
muted case unifies them.

### F2.4 Tests

```lua
test("F2: the reference bands recede when the data does", function()
  for _, mode in ipairs({ "Rail", "Sections" }) do
    local w = newWidget({ x = 0, y = 0, w = 220, h = 170 },
      { Source = ID_RSSI, ColorMode = mode })
    refresh(w, 2)
    mock.sim.rssi = 0
    mock.setValue(ID_RSSI, nil)
    refresh(w, 2)
    assertEq(w.data.availability, "disconnected", mode .. ": link down")
    local bands = w.ui.rails or w.ui.sections
    local T = w.mods.theme
    for i, band in ipairs(bands) do
      assertTrue(band.props.bgOpacity <= w.ui.valueArc.props.opacity,
        string.format("%s band %d (%s) must not outshine the muted arc (%s)",
          mode, i, tostring(band.props.bgOpacity),
          tostring(w.ui.valueArc.props.opacity)))
    end
  end
end)
```

### F2.5 Files, risk, acceptance

| | |
|---|---|
| **Files** | `renderer.lua` (`applyColors`), `tests/smoke_test.lua` |
| **Perf** | none — `setProp` filters no-ops, and this only runs on a colour-key change |
| **Renders changed** | `st-stale`, `st-nolink`, `st-nodata`, `st-nosource`, both themes |
| **Risk** | very low; the only judgement is 120 vs 90 |
| **Acceptance** | no band's opacity exceeds the value arc's in any non-valid state, in either colour mode; suites green |

---

## 4. F3 — 360° sweep: value and name 2 px apart

### F3.1 Evidence

Zone 200×200, `Sweep = 360`:

```
valueBox 101..125      nameBox 127..138      gap = 2 px
cy = 93   clearR = 63  ring inner bottom = 156
room below the name = 18 px
```

The boxes do **not** overlap — `dev/svgkit.lua` clips text to its box, so the
render is honest — but 2 px is `T.space.xs`, hard-coded, while 18 px of clear
ring interior sits unused underneath. At a glance it reads as a collision.

Identical on `git HEAD`: **pre-existing**, not a Tanda 7 regression.

The 360° branch is the one place `stackTextRows` is deliberately bypassed,
because letting the band run to the ring's *bottom edge* pushes the name onto
the ring and breaks G-10.

### F3.2 Options

| # | Option | Verdict |
|---|---|---|
| F3-0 | Status quo | rejected |
| F3-1 | Bump the gap `xs → sm` | uses 2 of 18 px; arbitrary |
| **F3-2** | **Give the 360° name to `stackTextRows` with the band bottom at the ring's INNER edge (`cy + clearR`)** | **recommended** — reuses the machinery and keeps G-10 true by construction |
| F3-3 | Centre the name in the room by hand | same result, second implementation of the same idea |

F3-2 is the right shape: the reason the branch was bypassed was an incorrect
*bottom*, not an unwanted mechanism. Give it the correct bottom and the
general path applies.

### F3.3 Pseudocode

```lua
    if L.sweep >= 360 then
      -- A CLOSED ring has no open wedge to hang the name in, so it goes
      -- INSIDE, under the value. It still gets the shared rhythm - what the
      -- 360 case cannot use is the ring's bottom EDGE as the band bottom,
      -- which is what pushes the name onto the arc (G-10). The band ends at
      -- the ring's clear INNER edge instead, so the name is distributed into
      -- the room that is actually there (measured: 18 px) and G-10 holds by
      -- construction rather than by a hard-coded 2 px gap.
      L.nameBox = box(dial.x, 0, dial.w, nameH)
      L.showMinMaxText = false
      stackRows = {}
      if L.showName then stackRows[#stackRows + 1] = L.nameBox end
      stackBottom = L.cy + (L.radius - floor(L.trackThickness / 2))
    else
      ...
```

`stackTop` is already `L.valueBox.y + L.valueBox.h`. `stackTextRows` clamps
the gap to `[xs, md]`, so the name lands ~6 px below the value with the
remainder split above and below — never tighter than today.

### F3.4 Acceptance

`G-10` stays green (it is the guarantee); gap ≥ `T.px(T.space.sm)`; name
bottom ≤ `cy + clearR`; `dev/collide.lua` 18/18; renders eyeballed.

---

## 5. F4 — 480×272 min/max reads as three unrelated labels

### F4.1 Evidence

Zone 480×272, `Min / max = Markers + text`:

```
minTextBox x=272 w=101 align LEFT      maxTextBox x=373 w=101 align RIGHT
'min' ink starts x=272 ; 'max' ink ends x=474  -> up to 202 px apart
nameBox   x=272 w=202 align LEFT       -> 'RSSI' sits directly under 'min'
```

In a balanced dial the min/max row is chord-clipped and narrow, so LEFT/RIGHT
halves read as a pair. In a **horizontal** zone the row is the full text
column, so the same rule throws the two labels to opposite ends of a 202 px
span, and the LEFT-aligned name stacks under `min`. Three labels, no grouping.

### F4.2 Options

| # | Option | Verdict |
|---|---|---|
| F4-0 | Status quo | rejected |
| **F4-1** | **Cap the min/max row width to the value group's width and centre it on the column** | **recommended** — preserves left/right reading order, groups the pair |
| F4-2 | Swap alignments (min RIGHT, max LEFT) so they converge on the centre | works, but inverts a convention held everywhere else |
| F4-3 | One centred label `"min 31   max 92"` | rejected: they update independently; would re-introduce a measured-text layout |
| F4-4 | Also centre the name in horizontal zones | **optional companion** — stops `RSSI` reading as a caption of `min` |

### F4.3 Pseudocode

```lua
  -- Horizontal zones only: the min/max row is the full text column here,
  -- not a chord-clipped strip, so LEFT/RIGHT halves throw the pair 202 px
  -- apart at 480x272 and it stops reading as a pair. Cap the row to the
  -- width of the value group it annotates and centre it on the column.
  if orientation == "horizontal" and L.showMinMaxText then
    local groupW = L.valueBox.w + (L.unitBox and L.unitBox.w or 0)
    local rowW = clamp(groupW, T.px(60), L.minMaxBox.w)
    L.minMaxBox.x = textRegion.x + floor((textRegion.w - rowW) / 2)
    L.minMaxBox.w = rowW
  end
  -- ... the minTextBox / maxTextBox split below inherits this, as it already
  -- inherits clipToChord's result in the balanced branch.
```

**Ordering trap** — the same one Tanda 7 B hit: this must run **before** the
`minTextBox` / `maxTextBox` split, or the halves keep the uncapped width.

### F4.4 Acceptance

`min`/`max` ink separation at 480×272 ≤ the value group width + one gap;
suites green; the balanced and vertical branches measurably unchanged.

---

## 6. F5 — Needle crosses the value text (no action)

At `ne-pos0`, `ne-pos100` and `tx-timer` the blade passes through the value's
glyphs. Labels are created after the needle so the digits paint on top and
stay legible; the blade fills the counters.

**Checked against `git HEAD`: identical before and after Tanda 7.** This is
the owner-accepted trade-off from Tanda 5 review 3.13 / P2-5 — the same
decision that let the value grow in Tanda 7 B.

Recorded, not actioned. It is more visible on the light theme, where the
needle is black. If it is ever revisited, the only real levers are shrinking
the value again (undoing P1-5) or hiding the blade under the text with a
halo — both worse than the current trade.

---

## 7. F6 — Renders capture the pulse at inconsistent phases (tooling)

The critical pulse toggles `opacity` between `T.opacity.pulse` (150) and
`full` (255) every ~500 ms. Scenes advance different numbers of frames, so
`color-threshold-crit` renders in the trough (dim brick red) and
`color-gradient-crit` at full (vivid). Deterministic and reproducible, but a
reviewer comparing the two reads a colour inconsistency that does not exist —
and this review very nearly did.

### F6.1 Options

| # | Option | Verdict |
|---|---|---|
| F6-0 | Status quo | rejected: the tool misleads its reader |
| **F6-1** | **Land every scene on a known pulse phase** (advance to `frame.pulse == false` before emitting) | **recommended** — one helper in `dev/scenes.lua`, every crit scene comparable |
| F6-2 | Add one dedicated `st-crit-pulse` scene at the trough and force full elsewhere | F6-1 plus a scene; do this only if the pulse needs its own picture |
| F6-3 | Annotate the phase in the caption | documents the confusion instead of removing it |

### F6.2 Sketch

```lua
-- dev/scenes.lua, after the frames are driven:
-- The critical pulse is a ~1 Hz opacity toggle, so which phase a scene lands
-- on is an artifact of how many frames it advanced. Two crit scenes caught in
-- opposite phases render visibly different reds and invite a bug report about
-- colour consistency. Settle every scene on the SAME phase; the pulse gets
-- its own scene if it needs a picture.
local function settlePulse(widget)
  for _ = 1, 4 do
    if widget.frame.pulse == false then break end
    mock.advance(500)
    widget.mod.refresh(widget)
  end
end
```

---

## 8. Sequencing

```
F1-3 (text -> role)  ──→  F1-4 (cap the ramp)   [eye check between them]
F2  (band muting)    ──→  regenerate st-* scenes
F3, F4  (layout)     ──→  regenerate + collide
F6  (tooling)        ──→  regenerate everything, re-review
```

1. **F1-3** alone, own commit — pure contrast gain, no visual change to the
   arc, nothing to argue about.
2. **F1-4** next, own commit, so the dark-theme arc change is bisectable and
   revertible on its own.
3. **F2**, own commit.
4. **F3** and **F4** — cheap, independent, one commit each.
5. **F6** last, so the final regeneration is the one that gets reviewed.

Do **F6 before the final eye check** either way: comparing reds across modes
is impossible until it lands.

---

## 9. Risk register

| Risk | Finding | Likelihood | Mitigation |
|---|---|---|---|
| Owner wants Gradient's vivid dark-theme green | F1-4 | medium | separate commit; `GRAD_GREEN` is one constant |
| Bar and dial drift on gradient text colour | F1-3 | medium | shared helper + the cross-renderer test, per Tanda 6 F-15 |
| Muting the bands makes no-data feel *too* dead | F2 | low | 120 vs 90 is a one-token decision |
| 360° name pushed onto the ring | F3 | medium | band bottom is the ring's inner edge; **G-10 is the gate** |
| min/max split leaves the halves on a stale width | F4 | medium | cap **before** the split — noted inline |

---

## 10. Decisions needed from the owner

| # | Question | My recommendation |
|---|---|---|
| 1 | **F1-3**: value text stops following the gradient ramp and uses the semantic role? | **Yes.** It is the fix; the arc keeps the feature |
| 2 | **F1-4**: cap the ramp's green so the arc clears 3 : 1 on both themes, accepting a less vivid green on dark? | **Yes**, but look at it first — it is the only subjective call here |
| 3 | **F2**: bands to `muted` (120) or all the way to the track's 90? | **120** — flat hierarchy, nothing outranks anything |
| 4 | **F3 / F4**: proceed? | Yes — cheap, contained, both measured |
| 5 | **F5**: leave the needle crossing the value? | **Yes** — settled in Tanda 5, and Tanda 7 B depends on it |
| 6 | **F6**: fix the shot tooling's pulse phase? | Yes, and land it before the final review pass |

---

*Nothing here is implemented. On a "go" I will work §8 in order, one commit
per concern, and report measured before/after for each — including the
contrast table re-measured after F1.*
