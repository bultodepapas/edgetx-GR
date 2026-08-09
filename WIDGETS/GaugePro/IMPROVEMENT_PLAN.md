 # Gauge Pro — Senior Improvement Plan (v2.0)

**Author role:** senior Lua + front-end review
**Baseline:** `feat/gauge-v2` @ `c6adbd3d4` (DOCS.md 1.0)
**Verified against:** `radio/src/lua/*`, `radio/src/gui/colorlcd/mainview/*`,
`radio/src/gui/colorlcd/widgets/*`, `companion/src/firmwares/*` of this fork,
version-checked against tags `v2.11.6` / `v2.12.x`, plus a source-level review
of the EdgeTX SD-card widgets and seven third-party collections (§2)
**Status:** phases A–D **implemented** on this branch (see §12 for what
shipped, what changed during implementation, and what remains)

---

## 0. Verdict

The architecture is right: pure-Lua math modules, retained LVGL objects,
change-only property writes, a real availability model, headless tests.

A GitHub-wide code search for `lvgl.arc` and `lvgl.triangle` in Lua returns
**zero EdgeTX widgets** — every other hit is an unrelated LuatOS/ESP project.
Every EdgeTX gauge in existence (GaugeRotary, yaapu, FlightDash, ePowerbar)
paints with the legacy `lcd` API. **GaugePro would be the first vector
instrument on the LVGL retained-object path in the ecosystem.** There is no
prior art to copy — only design references and a firmware binding to master.

Four things hold it back:

1. **The widget's headline features do not work on a radio.** All three
   `CHOICE` options (Style, Colors, Precision) are parsed as strings; the
   firmware delivers integers. On hardware the gauge is permanently
   `Colors = Static`, `Style = Auto`, and `Precision` is a raw menu index.
   Threshold coloring — the reason the widget exists — never fires. The tests
   pass because the mock feeds strings the firmware never sends. Third-party
   confirmation: ePowerbar declares `{ "Mute", CHOICE, 1, {…} }` and reads it
   as `options.Mute > 2`.
2. **The design is a wireframe, not an instrument.** Flat line needle, solid
   grey track, manually centered labels, uncalibrated font metrics, no
   threshold rail, no scale numbers. Both the predecessor (GaugeRotary) and
   the most respected script in the ecosystem (yaapu) draw a **tapered
   triangle needle**; GaugePro currently looks *less* finished than either.
3. **The option budget is real, but not where DOCS.md thinks.** 10 options is
   the true limit on **2.11** (`widgets_container.h:28`), raised to 50 only in
   **2.12.0** (commit `5c96b1e15`, Nov 2025). Companion carries its own copy of
   the same constant. So the cap is a *compatibility decision*, not a UI fact —
   and it is the one open question this plan needs answered (§5.0).
4. **`main.lua` is loaded for every widget at radio boot**, used or not
   (rotorflight's RfStats states this explicitly). GaugePro's 7 KB `main.lua`
   with option tables, translate tables and parsing logic is boot-time cost
   paid by every model on the radio.

This plan fixes correctness first, then rebuilds the visual language, then
spends the option budget the target version actually allows, then hardens the
code, tests and tooling.

---

## 1. P0 — correctness defects (must fix before anything else)

| # | Defect | Evidence | Impact |
|---|---|---|---|
| 1 | CHOICE options arrive as **integers**, code compares **strings** | `lua_widget.cpp:344-356` `default: lua_pushinteger(getUnsignedValue(i))`; ePowerbar reads choices numerically | Colors always Static, Style always Auto, Precision wrong. Core feature dead |
| 2 | CHOICE storage is **1-based** | `widget_settings.cpp:193-199` get = `stored-1`, set = `new+1`; ePowerbar declares default `1` for its first choice | Declared defaults (`0`) are out of range until first edit |
| 3 | Test mock encodes the wrong wire format | `tests/smoke_test.lua:112` `Style="Auto"` | 29 green tests validate a contract that does not exist |
| 4 | `T1`/`T2`/`T3` treated as timers | `telemetry.lua:41` vs `presets.lua:53` | A temperature sensor named `T1` renders as `00:01:07`. Real timer sources are `timer1…timerN` (`api_general.cpp:415`) |
| 5 | CELLS table is **summed**, docs say averaged, preset is **per-cell** | `telemetry.lua:148`; `presets.lua:47-51` 3.5–4.2 V | A 4S pack reads 15.2 V on a 4.2 V scale — pegged, permanently "normal" |
| 6 | Sensor scan stops at 32 | `telemetry.lua:88` `for i = 0, 31` | `MAX_TELEMETRY_SENSORS` is 40/60/99 (`dataconstants.h:57-89`). Sensor 33+ gets precision 0. `MAX_SENSORS` is exposed to Lua |
| 7 | Smoothing mixes time units | `renderer.lua:89` `getTime()` (10 ms ticks) vs `:94` `getTime()*10` (ms) | Nonsense `dt` on the first step → the needle snaps on every re-acquire |
| 8 | **Font metrics are uncalibrated** | `layout.lua:38` trusts `lcd.sizeText`; offer-shmuely's `lcdSizeTextFixed` corrects every font (`FONT_38` → real height 47, offset −7 **under LVGL**, −14 legacy) | Auto-fit picks the wrong font and every vertical centering is off by 3–14 px |
| 9 | History markers drawn before history exists | `renderer.lua:204-211` built at angle 135, never hidden | Two markers sit at the scale minimum until the first sample |
| 10 | Unit label re-positions from value width every change | `renderer.lua:296-300` | `100 → 99` shifts the unit horizontally — visible jitter |
| 11 | `error()` on missing `lvgl` | `main.lua:76` | Firmware error box. RfStats returns a **degenerate widget** that draws "LVGL support required" — strictly better UX |
| 12 | Dead branch in state text | `renderer.lua:310-314` | `stale` and `disconnected` are never distinguished on screen |

### 1.1 The option-marshalling fix

```lua
-- Wire format (verified in lua_widget.cpp / lua_widget_factory.cpp):
--   VALUE / SWITCH  -> signed integer
--   SOURCE / BOOL / COLOR / CHOICE / TEXT_SIZE / ALIGNMENT / SLIDER / TIMER
--                   -> unsigned integer
--   STRING / FILE   -> string
-- CHOICE is stored 1-based (widget_settings.cpp: get=stored-1, set=new+1).
-- A stored 0 means "never edited" -> use the declared default.

local function choiceOf(raw, count, default)   -- returns 1..count
  local v = tonumber(raw)
  if not v or v < 1 or v > count then return default end
  return v
end
```

Declare choice defaults **1-based** (`{ "Style", CHOICE, 1, {…} }`); the
`STYLE_CHOICES` / `COLOR_CHOICES` duplicate tables in `main.lua` disappear —
the index *is* the value.

### 1.2 The timer fix

```lua
-- Timer sources are the 'timer' family (api_general.cpp:415), contiguous ids.
-- Never treat a telemetry sensor as a timer: T1/T2 are temperature labels.
local timerBase = getSourceIndex("timer1")
s.isTimer = (not s.isTelemetry)
            and ((timerBase and s.id >= timerBase and s.id <= timerBase + 2)
                 or s.name == "tx-time")
```

### 1.3 The cells fix

`getSourceValue` returns a per-cell array (`api_general.cpp:295-307`).
Add a `Cells` choice — **Lowest / Total / Average**, default Lowest (the cell
that sags first is the one that matters). Keep the per-cell preset for
Lowest/Average; for Total, scale by the detected cell count (§2.4).

### 1.4 Calibrated font metrics

Build the metrics table once at load, not per call, and correct for the LVGL
path the way the ecosystem's most-used helper does:

```lua
-- lcd.sizeText() reports the font cell, not the ink box, and the correction
-- differs between the LVGL and legacy paths (offer-shmuely lib_widget_tools:
-- FONT_38 -> w-3, h 47, v_offset -7 under lvgl; -14 without).
local METRICS = {}      -- [font] = { w1, h, vOffset }
local function metrics(font) ... end   -- memoized; measured once
```

Everything that positions text (auto-fit candidates, value baseline, unit
baseline, chip height) reads from this table. This single fix is worth more
visually than any new element.

---

## 2. Ecosystem review — what the field does, and what to take

Reviewed at source level, not from READMEs:

| Project | Stack | What it does better | Take |
|---|---|---|---|
| **EdgeTX SD card** — `Value2`, `Timer2`, `Mixers`, `MicroValues`, `BattAnalog`, `Flights` (shipped per resolution: `c480x272`, `c480x320`, `c800x480`) | LVGL Lua | The official reference. `Value2` options are `SOURCE` + **`COLOR TextColor`** + **`STRING Suffix`** + **`BOOL Show_MinMax`**; thin `main.lua` + `app.lua` via `loadScript`; reads the sensor's own min/max sources; detects end-of-flight to keep min/max meaningful; blink+grey on telemetry loss | §3, §5, §6.2 |
| [`rotorflight-lua-scripts`](https://github.com/rotorflight/rotorflight-lua-scripts) — RfStats, RfTool | LVGL Lua | *"Keep main.lua as lightweight as possible, since main.lua gets loaded for **all** widgets at boot time"*; graceful `if lvgl == nil then return <stub widget>`; declarative `lvgl.build{ type="box", flexFlow=lvgl.FLOW_COLUMN, children={…} }`; function-valued `text` properties | §1 (#11), §7 |
| [`offer-shmuely/edgetx-x10-widgets`](https://github.com/offer-shmuely/edgetx-x10-widgets) — **GaugeRotary**, BattAnalog, Value2, MicroValues, Flights | legacy `lcd` | **Tapered filled-triangle needle**; continuous red→green gradient; **reads `<sensor>-` / `<sensor>+` min/max sources**; `-1` = auto-scale sentinel; fullscreen "app mode" with three dials; cell-count detection; **`lcdSizeTextFixed` font calibration**; `getUsage()` load overlay | §1.4, §4.4, §5, §6.2 |
| [`bob01/etx-widgets`](https://github.com/bob01/etx-widgets) — ePowerbar, eStatus, eValue | legacy `lcd` | 14 options incl. `COLOR`, `CHOICE`, alert switch, **mute levels + vibrate**, **startup delay**, reserve %; `translate` indentation to group options; throttled 200-tick telemetry heartbeat | §2.5, §5, §6.3 |
| [`dbarrios83/edgetx-widgets`](https://github.com/dbarrios83/edgetx-widgets) — Dashboard, TeleView, BattWidget, GPS, RX | legacy `lcd` | Shared `/WIDGETS/common/` lib + icons; **typography token table**; connect/disconnect edge tracking; **telemetry simulator with named flight profiles**; 63 tests with `.sh` + `.bat` runners | §2.4, §8 |
| [`yaapu/FrskyTelemetryScript`](https://github.com/yaapu/FrskyTelemetryScript) | legacy `lcd` | The ecosystem benchmark. `drawLib.drawGauge` = **bitmap dial face + triangle needle** (±20° base half-angle); per-resolution asset folders; blink bitmaps for failsafe | §4.4, §4.9 |
| [`JeffreyChix/edgetx-dev-kit`](https://github.com/JeffreyChix/edgetx-dev-kit) | VS Code ext | **LuaLS type stubs for 2.3–2.12** generated from `edgetx-lua-gen`; two-layer diagnostics on save; **WASM EdgeTX simulator with telemetry injection + live reload**; SD deploy; widget scaffolding | §8 |
| EdgeTX built-ins (`value.cpp`, `gauge.cpp`, `outputs.cpp`, `text.cpp`) | C++/LVGL | `COLOR`/`ALIGN`/`TextSize` as standard option vocabulary; shadow = a second black label at (+1,+1) | §3, §5 |

### 2.1 GaugePro is the first LVGL vector instrument — plan accordingly

No EdgeTX widget uses `lvgl.arc`, `lvgl.triangle`, or the retained-object
update model. Consequences for this plan:

- There is nobody to copy from at the rendering layer; the binding facts in
  `dev/RESEARCH.md` and §3 are the only reference, and they must stay verified
  against `radio/src/lua`.
- Conversely, the *visual* references (yaapu, GaugeRotary, FlightDash) are all
  bitmap-and-primitive designs. Their look is achievable with vectors and
  scales to any resolution without shipping per-resolution assets — that is
  the actual competitive advantage, and §4 is where it gets cashed in.
- The official examples use `lvgl.build` trees with **function-valued
  properties** (`text = function() … end`), re-evaluated every frame by
  `callRefs`. GaugePro's explicit `lvgl.set`-on-change is cheaper. Keep it, and
  document the trade-off so it is not "fixed" later by someone copying the
  official style.

### 2.2 Use the radio's own min/max sensors

EdgeTX maintains per-sensor min/max as sibling sources. Both GaugeRotary and
the official Value2 read them:

```lua
local lo = getFieldInfo(sourceName .. "-")
local hi = getFieldInfo(sourceName .. "+")
```

Strictly better than in-Lua history for telemetry sources: survives widget
recreation, matches what the rest of the radio shows, and is cleared by the
standard *Reset telemetry* / flight-reset functions. **Adopt as primary, keep
the current tracker as the fallback** for sticks/channels/gvars. Value2 goes
further and freezes min/max at end-of-flight so post-landing idling does not
overwrite the flight's real extremes — worth copying.

### 2.3 Keep `main.lua` boot-cheap

Every `main.lua` under `/WIDGETS/` is loaded at radio startup for every model,
whether the widget is used or not. Target: registration table, version guard,
and a `loadScript` of `app.lua` — nothing else. This is an independent
argument for the `options.lua` refactor in §7.

### 2.4 Cell-count auto-detection

```lua
local cells = math.floor(total / 4.35) + 1          -- 16.4 V -> 4S
local perCell = total / cells
```

Turns a guessed 0–8.4 V scale into a correct `cells × [3.0 … 4.35]` scale.
Add a `Li-Po / Li-Ion` choice (Li-Ion floor 2.8 V) — a long-standing community
request against BattAnalog.

### 2.5 Alerts done properly (ePowerbar's model)

- **Startup delay** in seconds — no alerts until telemetry settles. Without it
  every power-up screams *CRITICAL*.
- **Mute levels** as a choice (None / Critical / All), not a bool.
- **Vibrate** separate from sound (`playHaptic`).
- An **alert switch source** to gate alerts on "armed".
- Spoken values via `playNumber`/`playFile` from `/SOUNDS/<lang>/`.

### 2.6 Test tooling: scenario profiles

`dbarrios83/tests/utils/telemetry_simulator.lua` drives widgets through named
profiles (`idle`, `takeoff`, `cruising`, `landing`, `lowbattery`,
`disconnected`). GaugePro's mock serves static values only, which is why
smoothing, hysteresis, staleness and reconnection are effectively untested.

### 2.7 Known failure modes to design against

- *"Rotary Gauge stays at -1 regardless of source"* — the auto-scale sentinel
  colliding with a real value. GaugePro's equivalent trap is "presets apply only
  while ranges are at defaults"; replace with an explicit `Scale: Auto/Manual`.
- *"GaugeRotary disappears after a Companion read/write"*
  ([EdgeTX#4528](https://github.com/EdgeTX/edgetx/issues/4528)) — widget option
  data is **positional, typed, and version-capped on both sides** (§5.0). This
  makes append-only ordering a hard rule and a Companion round-trip an
  acceptance test.

### 2.8 What *not* to copy

- A shared `/WIDGETS/common/` folder (dbarrios83) makes every widget depend on
  a sibling directory users can fail to copy. Stay self-contained.
- `destroy()` in the return table is **never called** — the registration keys
  are exactly `name, options, create, update, refresh, background, translate,
  useLvgl` (`widgets.cpp:114-141`), confirmed by the dev-kit's generated widget
  contract. Do not rely on it.
- Per-resolution copies of the whole widget (yaapu, official SD card). Vector
  rendering plus `LCD_SCALE` is the whole point; one folder must serve all.
- Hard-coded `lcd.RGB` palettes (ePowerbar). Theme roles everywhere; raw RGB
  only inside the opt-in Gradient mode (§4.3).

---

## 3. Firmware capability the current design leaves unused

| Capability | Where | Use for Gauge Pro |
|---|---|---|
| `WidgetOption::Color` (7) | `widget_settings.cpp:169`; precedent: official `Value2` `{ "TextColor", COLOR, YELLOW }`, `value.cpp:287`, eStatus | User accent colour, background colour |
| `Align` (8), `TextSize` (4), `Slider` (9), `Switch` (6), `String` (3) | `widget_settings.cpp:114-190`; `Value2` ships a `STRING Suffix` | Alignment, font override, damping slider, reset/alert switch, custom label and unit |
| `lvgl.label{ align, w }` | `lua_lvgl_widget.cpp:858-874` | Delete every `lcd.sizeText` centering computation |
| `lvgl.triangle{ pts }` | `lua_lvgl_widget.cpp:1179`; stub: "There must be three points" | Tapered needle (what GaugeRotary and yaapu both draw) |
| `line{ dashGap, dashWidth }` | `lua_lvgl_widget.cpp:897-901` | Minor ticks, "no data" dashed arc |
| `lvgl.rectangle{ rounded, filled }` | `lua_lvgl_widget.cpp:1766-1830` | State chip, optional widget background |
| `visible = function` | stub `@field visible? fun(...): boolean` | Declarative hide/show without `lvgl.show/hide` bookkeeping |
| `circle{ filled, thickness, radius }` | `lua_lvgl_widget.cpp:1690-1790` | Pivot ring (outer ring + inner dot) |
| Fullscreen-only controls | `api_colorlcd_lvgl.cpp:194` | Detail view with a real **Reset min/max** button |
| Third return of `getSourceValue` (`fresh`) | `api_general.cpp:837` | "New frame arrived" vs "sensor alive but unchanged" |
| `lcd.RGB(r,g,b)` | `api_colorlcd.cpp:1000` | Gradient colour mode (§4.3) |
| `playTone` / `playHaptic` / `playNumber` / `playFile` | `api_general.cpp:3135-3139` | Alerts, spoken values |
| `getUsage()` | `api_general.cpp:3151` | Dev overlay showing Lua load %, as GaugeRotary does |
| Second offset label = shadow | `value.cpp:49-72` | DOCS §9 says shadows are impossible; they are not |

Constraints that stay: arc `thickness`/`rounded` are **build-time only** (no
setter in `LvglWidgetArc::callRefs`) — options touching them force a rebuild.
Portability note: the official stub documents arc angles as **0–360**; this
fork's binding normalises 405→45, so the absolute form GaugePro uses is a
fork-verified behaviour, not a documented one — keep the normalisation in
`geometry.lua` so a stricter firmware cannot break the dial.

---

## 4. Visual redesign — from wireframe to instrument

### 4.1 Current vs proposed anatomy

```
   CURRENT (normal, balanced)          PROPOSED (normal, balanced)
   ─────────────────────────           ──────────────────────────
      |  '   |   '  |                     ╷  ·   ╷   ·  ╷        ← major + dashed minor ticks
    '                   '              ·  ┌──────────────┐  ·
   |    ▁▁▁▁▁▁▁▁▁▁▁▁    |             ╷   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔   ╷    ← threshold rail (thin, always)
   |  ▁▁            ▁▁  |             │ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ │    ← value arc (thick, rounded)
   |                    |             │        ◆           │    ← tapered needle + pivot ring
   '       78 %        '              ╵      78.4          ╵
      \        /                          ┌───┐  %              ← value + baseline-aligned unit
        RSSI                              │WARN│ RSSI           ← state chip + source name
        WARN                              └───┘
      0            100                  0 ·············· 100    ← scale end labels (large)
```

### 4.2 Design tokens (`theme.lua`, new module)

The `utils.S` idea from dbarrios83, done with LVGL theme roles instead of
baked-in flags:

```lua
return {
  color = {
    accent   = COLOR_THEME_PRIMARY1,     -- overridable by the Color option
    warn     = COLOR_THEME_WARNING,
    crit     = RED,
    rail     = COLOR_THEME_SECONDARY1,   -- @ 25% opacity, not solid SECONDARY3
    tick     = COLOR_THEME_SECONDARY2,
    label    = COLOR_THEME_SECONDARY1,
    muted    = COLOR_THEME_DISABLED,
  },
  opacity = { full = 255, rail = 64, ghost = 96, muted = 110 },
  space   = { xs = 2, sm = 4, md = 6, lg = 10 },   -- all through px()
  ratio   = { unitToValue = 0.55, trackToRadius = 0.14, railToTrack = 0.30 },
}
```

Never paint a raw constant in `renderer.lua` again. Track and rail differ by
*opacity*, not by colour role — that is what keeps the gauge legible on light,
dark, high-contrast **and** over a model bitmap.

### 4.3 Colour modes

| Mode | Behaviour | Notes |
|---|---|---|
| Static | accent only | as today |
| Threshold | arc + needle + value take the state colour | as documented today, once §1.1 is fixed |
| **Rail** *(new default)* | thin outer rail permanently marks warn/crit zones; value arc stays semantic | Grafana/automotive idiom; keeps figure/ground intact |
| **Gradient** *(new)* | continuous green→amber→red via `lcd.RGB` | GaugeRotary's `getRangeColor`; opt-in because raw RGB ignores the theme |
| Sections | three coloured track segments | kept for compatibility, no longer recommended |

Rail geometry: 2–3 px arc at `radius + trackThickness/2 + 2`; warn/crit
segments only; track at `rail` colour, 64 opacity; value arc thick, rounded.

### 4.4 Needle

Replace the `lvgl.line` needle with `lvgl.triangle` — GaugeRotary draws
`lcd.drawFilledTriangle`, yaapu draws a three-line triangle with a ±20° base
half-angle. Both look like instruments; a 1 px line does not.

```
        ▲  tip at tickInner - 2
       ╱ ╲
      ╱   ╲     3 points: (tip), (base ± halfWidth ⟂ to the angle)
     ╱_ _ _╲    plus a short counterweight triangle on the opposite side
        ●      pivot: outer circle (rail colour) + inner circle (state colour)
```

Two extra objects; `trianglePoints(cx, cy, r1, r2, halfW, angle)` is six lines
of pure Lua in `geometry.lua` — unit-testable off-radio.

### 4.5 Typography

- **Delete all manual centering.** `lvgl.label` supports `align` + `w`; give
  each text a region and an alignment. Removes `positionNameLabel`, the
  `lcd.sizeText` calls in three update functions, and the unit jitter (#10).
- **Calibrated metrics** (§1.4) drive auto-fit and baselines.
- **Baseline-align the unit**: `round(valueFont * 0.55)`, on the value
  baseline, muted. Biggest "looks designed" win available.
- **Name** muted `XS`, ellipsized by LVGL (`w` set), never wraps.
- **State chip** (`rectangle{ rounded, filled }` + label) only for
  WARN/CRIT/NO DATA — today an empty state label reserves the row and
  unbalances the normal state.
- **Scale end labels** near 135°/405° in large mode, `XXS`, muted.

### 4.6 Layout grid

Replace per-orientation magic numbers (`w * 0.42`, `h * 0.34`,
`radius * 0.45`) with explicit regions:

```lua
L.regions = {
  dial  = { x, y, w, h },
  value = { x, y, w, h },   -- value + unit, baseline row
  meta  = { x, y, w, h },   -- name + state chip
  foot  = { x, y, w, h },   -- min/max row (large only)
}
```

One place to test (golden snapshots), no overlap bugs, alignment options become
trivial.

### 4.7 A `Bar` style for wide/short zones

GaugeRotary prints *"too small for GaugeRotary"* below 60 px and drops to a
"low profile" layout below 90 px. Do better: below an aspect threshold
(w/h > 2.6) or in `micro`, render a **linear bar** with the same state model —
rail with threshold marks, rounded fill, value+unit right-aligned, history
ticks. Never render an error message where a usable instrument fits.

### 4.8 Motion and state feedback

- Needle smoothing (after fixing #7), exposed as a damping slider.
- **Critical pulse**: value-arc opacity 255 ↔ 160 at ~1 Hz; survives greyscale
  and colour-blind viewing. Throttle with ePowerbar's heartbeat pattern
  (`if next < getTime() then … next = getTime() + 100 end`).
- **Stale age**: dim to muted and show the age (`12s`) in the chip rather than
  a generic `NO DATA`.
- **Ghost peak**: peak drawn as a short reduced-opacity arc segment.

### 4.9 Considered and rejected: bitmap dial faces

yaapu and FlightDash render a pre-drawn dial-face PNG and paint only the
dynamic parts on top — crisp ticks and labels for free. `lvgl.image` supports
it. Rejected because it forces per-resolution asset sets (exactly the
`c480x272` / `c480x320` / `c800x480` triplication those projects carry), breaks
theme adaptation, and cannot recolour for warn/crit. Vector + `LCD_SCALE` is
the differentiator; keep the asset folder empty.

---

## 5. Option set v2

### 5.0 The compatibility decision (needs an answer before Phase D)

| Firmware | `MAX_WIDGET_OPTIONS` | Source |
|---|---|---|
| 2.11.x radio | **10** | `v2.11.6:radio/src/gui/colorlcd/mainview/widgets_container.h:28` |
| 2.11.x Companion | **10** | `v2.11.6:companion/src/firmwares/customisation_data.h:40` |
| 2.12.0+ radio & Companion (and this fork) | **50** | `datastructs_screen.h:92`, `companion/.../customisation_data.h:38`, commit `5c96b1e15` (2025-11-19) |

DOCS.md's "ten options" is therefore **correct for the stated 2.11 target** and
wrong only for 2.12+. Excess options are silently truncated
(`lua_widget_factory.cpp:291`), and a model touched by an older Companion loses
them — the same class of failure as EdgeTX#4528.

**Recommendation: keep the current ten options in their current positions as
the "core", and append the extras only when the firmware supports them**,
building the table at load time:

```lua
local _, _, maj, minor = getVersion()
local canExtend = (maj > 2) or (maj == 2 and minor >= 12)
local options = core10
if canExtend then for _, o in ipairs(extra) do options[#options+1] = o end end
```

Order the extras by descending value so truncation always degrades gracefully.
Conventions confirmed by the generated widget contract: **widget name ≤ 10
chars** (`GaugePro` ✓), **option names ≤ 10 chars, no spaces** — long labels
come from `translate`, which is also where ePowerbar's indentation trick
(`"  …or cell count"`) groups related options visually.

> **Migration rule: options are appended. Never insert or reorder.**

### 5.1 Core ten (2.11-compatible, positions unchanged)

| # | Option | Type | Default | Change |
|---|---|---|---|---|
| 1 | Source | SOURCE | auto | — |
| 2–5 | Min / Max / Warn / Crit | VALUE | 0/100/55/35 | — |
| 6 | HighGood | BOOL | on | — |
| 7 | Style | CHOICE | Auto | **+ Bar** (§4.7) |
| 8 | ColorMode | CHOICE | Rail | **+ Rail, + Gradient** (§4.3) |
| 9 | Precision | CHOICE | Auto | — |
| 10 | ShowMinMax | CHOICE | Markers | was BOOL; Off / Markers / Markers+text |

### 5.2 Extras (2.12+, appended in this priority order)

| # | Option | Type | Default | Why it earns a slot |
|---|---|---|---|---|
| 11 | Accent | **COLOR** | theme primary | native picker; official precedent in `Value2`, `value.cpp`, eStatus, BattAnalog. Colour-code four gauges on one screen |
| 12 | Label | **STRING** | "" | custom name ("PACK", "MOTOR"); empty = sensor name |
| 13 | Suffix | **STRING** | "" | custom unit — *the exact option the official `Value2` ships* |
| 14 | Scale | CHOICE | Auto | Auto / Manual — replaces the fragile "presets only while at defaults" heuristic (§2.7) |
| 15 | Cells | CHOICE | Lowest | Lowest / Total / Average (§1.3) |
| 16 | Battery | CHOICE | Off | Off / Li-Po / Li-Ion — auto cell count + discharge-curve percentage (§2.4) |
| 17 | Damping | **SLIDER** | 4 | 0 = raw … 9 = heavy; noisy RPM/current needs it, RSSI does not |
| 18 | Alerts | CHOICE | Off | Off / Critical / Warning+Critical (§2.5) |
| 19 | AlertSw | **SWITCH** | none | gate alerts on "armed" |
| 20 | Delay | VALUE | 4 s | startup delay before any alert |
| 21 | Vibrate | BOOL | off | `playHaptic` on critical |
| 22 | ResetSw | **SWITCH** | none | reset min/max in flight, not through a menu |
| 23 | Sweep | CHOICE | 270° | 270 / 180 / 360 — 180° fits zones a bar cannot |
| 24 | BgColor | **COLOR** | none | readability over model bitmaps (`outputs.cpp:259`) |

Rejected: per-element font options (auto-fit is better), tick count (derived),
needle length, multi-source gauges (a different widget), LVGL gradients (not in
the binding).

---

## 6. Functionality roadmap

### 6.1 Threshold hysteresis

First-match-wins on exact boundaries means a value sitting on 55.0 flickers —
and with alerts enabled that becomes an audible machine gun.

```lua
-- enter a worse state immediately; leave it only after a deadband
local band = (max - min) * 0.02
if newRank > curRank then state = new
elseif value crossed back past (threshold ± band) then state = new end
```

### 6.2 History from the radio, not from Lua

Primary: `<name>-` / `<name>+` sibling sources (§2.2), with Value2's
end-of-flight freeze. Fallback: the current tracker for non-telemetry sources.
Reset on source change, range change, model change, and the reset switch.
Persisting across a power cycle is impossible from a widget — document it.

### 6.3 Fullscreen detail view

Fullscreen already works (zone resize → layout signature → rebuild) but is only
a bigger dial. GaugeRotary's app mode shows value + min + max dials and exits
on double-tap. Go further: **min / avg / max / now** stat row, a **history
sparkline** (ring buffer of ~60 samples at 1 Hz as one `lvgl.line`, updated
once per second), and **Reset min/max** + **Exit** buttons — controls are legal
only in fullscreen (`api_colorlcd_lvgl.cpp:194`), so guard with
`lvgl.isFullScreen()`.

### 6.4 Inverted-range mirroring

Keep `min > max` as authored and invert the normalisation rather than swapping;
the official gauge's `value - min - max` transform is degenerate for asymmetric
ranges. Descending scales (rate of climb, temperature margin) then work.

---

## 7. Code architecture

| File | Change |
|---|---|
| `main.lua` | **Shrink to boot weight** (§2.3): registration table, `lvgl == nil` stub widget (#11), version-gated option assembly (§5.0), `loadScript("app.lua")`. Nothing else |
| `app.lua` | **new** — lifecycle, signatures, module wiring (today's `main.lua` body) |
| `options.lua` | **new** — one declarative option table generating the firmware array, `translate`, and the typed parse. Kills the current triplication and structurally prevents defect #1 |
| `theme.lua` | **new** — design tokens (§4.2) + calibrated font metrics (§1.4) |
| `geometry.lua` | + `trianglePoints`, `barRect`; drop the `tickPoints` alias |
| `ranges.lua` | + hysteresis-aware `determineState(value, bands, previous)` |
| `presets.lua` | + cell detection, Li-Po/Li-Ion curves, and the missing common sensors (Curr, Capa, Alt, VSpd, GSpd, Dist, Sats, TPWR, ANT) |
| `telemetry.lua` | collapse four duplicated "no value" blocks into `setNoData()`; scan to `MAX_SENSORS`; timer detection by id; cells modes; `fresh` flag; sibling min/max |
| `layout.lua` | region model (§4.6); metrics from `theme.lua`; classification table instead of if-chains |
| `renderer.lua` | `build_*`/`update_*` per element; one `setIfChanged(obj, key, value)` replacing ten hand-written compares; no `lcd.sizeText` |
| `bar.lua`, `alerts.lua`, `fullscreen.lua` | **new** — linear style; alert state machine with startup delay, mute levels, rate limiting; detail view loaded only when fullscreen |

### 7.1 The declarative option module

```lua
local DEFS = {
  { key = "Source", label = "Source", type = SOURCE, since = "2.11",
    default = { "RSSI", "RQly", "RxBt", "Cels", "TxBt" } },
  { key = "Style",  label = "Style",  type = CHOICE, default = 1, since = "2.11",
    choices = { "Auto", "Needle", "Arc", "Bar" }, field = "style" },
  { key = "Accent", label = "Accent colour", type = COLOR, since = "2.12",
    default = COLOR_THEME_PRIMARY1, field = "accent" },
}
```

`since` drives §5.0's version gate; `parse` is pure Lua, so the wire contract
becomes directly unit-testable with integers — exactly the missing test.

### 7.2 Renderer hygiene

```lua
local function setIfChanged(cache, obj, key, value)
  if obj and cache[obj] ~= value then
    cache[obj] = value
    lvgl.set(obj, { [key] = value })
  end
end
```

Preallocate the property table per object so `refresh()` stays
allocation-free — dbarrios83's guide states the same rule: no table literals,
no `string.format`, no layout math inside `refresh()`.

### 7.3 Performance guardrails

- `refresh()`: no object creation, no `lcd.sizeText`, no string building unless
  the displayed string changed.
- Font metrics measured once at load, never per layout pass.
- Object budget: today ≈ 20; proposed adds rail (3), triangle needle (2), chip
  (2), scale labels (2), ghost peak (1) ≈ 30. Cap at 40 and assert it.
- Optional `getUsage()` dev overlay behind a debug flag.

---

## 8. Test and tooling strategy

| Item | Change |
|---|---|
| `mock_env.lua` | **Fix the wire format**: integers, 1-based choices; add `makeOptions(decl, {Style="Needle"})` so tests stay readable *and* honest |
| contract tests | Every option: type constant, 1-based default in range, choice count, **name ≤ 10 chars, no spaces**, and a golden positional list (catches the reordering that breaks saved models) |
| version-gate tests | `getVersion()` mocked as 2.11 → exactly 10 options; as 2.12 → the full list, core ten unchanged in position |
| `scenarios.lua` | **new**, after dbarrios83's simulator: `idle`, `takeoff`, `cruising`, `noisy`, `dropout`, `reconnect`, `lowbattery`, `sensor-lost`; drives `refresh()` over N frames with a synthetic clock — the only way to test smoothing, hysteresis, staleness and alert rate-limiting |
| golden layout | 5 resolutions × 8 sizes × 3 orientations: objects inside the zone, no region overlap, value font ≥ minimum, ≤ 40 objects |
| property tests | `ranges`: random min/max/warn/crit → ordered, contiguous, cover `[min,max]`, no oscillation on a monotone ramp |
| `dev/preview.lua` | **new** — render the mock object tree to **SVG**; review design iterations in a browser. Highest-leverage tool here for the "make it beautiful" goal |
| **LuaLS type stubs** | Vendor `edgetx.*.d.lua` (2.12) from [`edgetx-dev-kit`](https://github.com/JeffreyChix/edgetx-dev-kit) into `dev/stubs/` + a `.luarc.json`. Editor autocomplete, `---@` annotations, and static detection of version-gated APIs — this is the class of tooling that would have caught defect #1 at author time |
| dev-kit simulator | Its WASM EdgeTX simulator with **telemetry injection + live reload** replaces most of the manual Companion loop; use it for the §4 design passes |
| runners + CI | `run_tests.sh` **and** `.bat` (this repo is developed on Windows) + a GitHub Action with `lua5.3` and `luacheck` |
| Companion round-trip | Manual gate: add widget → write model from Companion → read back; widget and every option value must survive (§2.7) |

---

## 9. DOCS.md corrections

| DOCS location | Says | Reality |
|---|---|---|
| §4.1 | "ten options (the maximum the 2.11+ widget settings UI is designed for)" | 10 is the **2.11** limit (radio *and* Companion); 2.12+ allows 50. Reword as a version constraint, not a UI limit (§5.0) |
| §4.7 | tables "aggregated by averaging" | code sums (`telemetry.lua:148`) |
| §4.7 | timers "`timer1`…`timer3`, `T1`–`T3`" | timer sources are `timer1…timerN`; `T1`/`T2` are temperature labels |
| §5.2 | "choice strings are mapped to indices via the official `etxcst` constants" | choices are never strings on the wire |
| §5.5 | font heights from `lcd.sizeText` | needs per-font calibration, and the correction differs on the LVGL path (§1.4) |
| §5.7 | "sensors 0–31" | `MAX_TELEMETRY_SENSORS` = 40/60/99; `MAX_SENSORS` is exposed to Lua |
| §5.7 | `getSourceValue` → value, current | returns **three** values: value, `current`, `fresh` |
| §5.8 | "20,000 instructions" | ~~wrong~~ — **DOCS.md was right and this row was not.** `MAX_INSTRUCTIONS` (200) is the count-hook *interval*: `luaHook` increments `instructionsPercent` once per hook and errors past 100 (`widgets.cpp:52-72`), so the budget is 200 × 100 = **20,000 instructions per callback**. PLAN.md §2.8 carries the same misreading and should be corrected |
| §5.9 | arc property list | `thickness`/`rounded` have no setter → build-time only; angles are documented 0–360, the 405 normalisation is fork-verified behaviour |
| §5.9 / §9 | "shadows are not exposed by the Lua binding" | `value.cpp:49-72` draws a black label at (+1,+1); reproducible with a second `lvgl.label` |
| §1 | "successor to GaugeRotary" | GaugeRotary was never read at source level; §2 lists five features it has that GaugePro does not |

---

## 10. Phased delivery

| Phase | Scope | Gate | Risk |
|---|---|---|---|
| **A — Correctness** (1 d) | §1 defects 1–12 incl. font calibration and the `lvgl == nil` stub, mock wire format, contract tests, DOCS corrections | Tests green against the *real* contract; Colors/Style/Precision verified in the simulator | Low. Must ship before any release |
| **B — Architecture** (1.5 d) | `main.lua` boot diet + `app.lua`, `options.lua`, `theme.lua`, `setIfChanged`, telemetry dedup, layout regions, `scenarios.lua`, LuaLS stubs | Zero visual diff vs A (golden snapshots identical) | Low, mechanical |
| **C — Visual** (2 d) | Rail + Gradient, triangle needle + pivot ring, alignment-based text, baseline unit, state chip, scale labels, ghost peak, critical pulse, `bar.lua` | SVG previews at 5 resolutions × dark/light; contrast ≥ 4.5:1; ≤ 40 objects | Medium — taste decisions; the SVG tool and the WASM simulator de-risk it |
| **D — Options & data** (1.5 d) | §5.0 version gate, extras 11–24, hysteresis, alerts, sibling min/max, cell detection, battery % | Version-gate tests; settings dialog verified on device; **Companion round-trip passes** | Medium — the option cap and positional storage are the traps |
| **E — Fullscreen** (1 d) | Detail view, sparkline, reset button, stat row | Touch + rotary on hardware; no controls created outside fullscreen | Medium — hardware-dependent |
| **F — Release** (0.5 d) | Screenshots (the gallery requires them), README/DOCS rewrite, CI, gallery issue, `edgetx-sdcard` patch | Fresh SD-card install on a clean model | Low |

Ship A+B as **v1.0.1** (bugfix), C+D as **v1.1** (the redesign), E as **v1.2**.

---

## 11. Definition of done (v1.1)

1. Every declared option is observably effective on hardware — verified one by
   one, not inferred from tests.
2. On 2.11 the widget exposes exactly ten options and behaves identically to
   today's configuration; on 2.12+ the extras appear without disturbing the
   core ten.
3. No `lcd.sizeText` and no object creation in `refresh()`; ≤ 40 objects in the
   largest configuration; `main.lua` carries declarations only — no parsing,
   no translate table, no module wiring. (It is still ~7 KB, because 24 option
   declarations are 24 option declarations; what left the boot path is the
   *logic*, not the data.)
4. Dark, light and high-contrast themes audited at 320/480/800 px; critical
   state distinguishable without colour.
5. `micro`, wide-short and full-screen zones all produce a readable instrument
   — no "too small" message anywhere.
6. Threshold crossings do not chatter on a noisy ramp; alerts respect the
   startup delay and mute level.
7. A temperature sensor named `T1`, a 4S `Cels` pack, a timer, a stick and a
   disconnected sensor each render correctly — as regression tests.
8. The widget and its settings survive a Companion model read/write cycle.
9. DOCS.md contains no claim contradicted by `radio/src`.

---

## 12. Implementation record (phases A–D)

Delivered on this branch. Test counts are the headless suites; run them with
`lua5.3 tests/run_tests.lua ./` and `lua5.3 tests/smoke_test.lua ./`.

### 12.1 What shipped

| Area | Result |
|---|---|
| Option contract | `options.lua` + a declarative `DEFS` table in `main.lua`. Choices are 1-based integers; the core ten hold fixed positions and the 2.12-only extras are appended behind a `getVersion()` gate |
| P0 defects 1–12 | All fixed. Timer detection by source id, cell aggregation modes, `MAX_SENSORS` scan, sibling `<name>-`/`<name>+` history, millisecond smoothing, markers hidden until data, no-data dedup, `lvgl == nil` stub widget instead of `error()` |
| Architecture | `main.lua` reduced to declarations + guard (boot weight); `app.lua`, `options.lua`, `theme.lua`, `format.lua`, `smoothing.lua`, `bar.lua`, `alerts.lua` added; `setProp` writes through one reused table so `refresh()` allocates nothing |
| Visual | Threshold rail (new default), triangle needle + counterweight + pivot ring, peak-hold ghost, state chip that hugs its text, critical pulse, scale end labels, minor ticks, alignment-based text with a fixed value box, linear bar style |
| Options | 23 declared (10 core + 13 appended): accent colour, name/unit override, scale mode, sweep, damping slider, cell reading, battery percent, alerts + switch + delay + vibrate, reset switch |
| Data | Hysteresis, cell-count latching with pack rescale, Li-Po/Li-Ion discharge curves, expanded preset table (Curr, Capa, Alt, GSpd, Dist, Sats, Thr, SNR, TQly …) |
| Tests | 36 unit + 46 lifecycle, including the option-contract golden list, the 2.11/2.12 capacity split, a golden layout matrix over eight zone shapes, alert and hysteresis scenarios, and a 200-frame flight asserting zero object churn |
| Tooling | `dev/preview.lua` renders the real object tree to SVG (dark + light) → `dev/preview.html` |

### 12.2 Decisions that changed during implementation

- **Font metrics.** The plan proposed porting a per-font correction table.
  Rejected: those numbers are resolution-specific and would break on 320 and
  800 px screens. Instead every label gets a region plus an `align`, and LVGL
  does the centring; measurement is used only for fitting (where the reported
  height is a safe upper bound) and for the state chip. This removes all
  runtime text measurement from `refresh()` and fixes the unit jitter at the
  same time.
- **Gradient mode** interpolates across the *thresholds*, not min…max. A ramp
  over the whole scale shows green while the value sits just above the warning
  line.
- **Scale = Auto** on 2.11 keeps the original "presets only while the ranges
  are untouched" heuristic, because there is no slot for the Scale option
  there; 2.12+ gets the explicit Auto/Manual semantics.
- **`ShowMinMax`** changed type from BOOL to CHOICE (Off / Markers / Markers +
  text). The stored type differs, so the firmware resets that one slot to its
  default on upgrade — a deliberate, contained migration.

### 12.3 Firmware facts discovered while implementing

Both were caught by the mock's property allow-lists before reaching a radio:

- `lvgl.triangle` accepts **only `pts`** plus base object properties
  (`LvglWidgetTriangle : LvglSimpleWidgetObject`) — no `filled`, `thickness`
  or `rounded`. It always fills.
- `dashGap` / `dashWidth` belong to `LvglWidgetLineBase` (`hline`, `vline`)
  and are **not** accepted by the free-angle `lvgl.line`. Minor ticks use
  reduced opacity instead.

And one caught by the golden layout matrix: deriving the dial radius from the
dial box and *then* adding the rail and ticks pushes those ticks outside the
zone. The radius is now what remains after reserving the outer decorations.

### 12.4 Not done

- **Phase E — fullscreen detail view** (stat row, history sparkline, reset
  button). Interactive controls only exist in fullscreen and need hardware
  verification; nothing else depends on it.
- **Phase F — release**: screenshots, CI workflow, gallery submission,
  `edgetx-sdcard` patch.
- Vendored LuaLS stubs from `edgetx-dev-kit` (§8) — editor tooling, no
  runtime effect.
- Background fill colour, label shadows, spoken alert values.
- Hardware verification of every option one by one (§11.1) and the Companion
  round-trip (§11.8): both require a radio or Companion.
