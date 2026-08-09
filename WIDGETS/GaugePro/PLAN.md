# EdgeTX Gauge Pro — Reality-Adjusted Development Plan

**Document version:** 0.3 (supersedes design draft 0.2)
**Status:** Senior-dev plan validated against the local repo (`bultodepapas/edgetx-GR`)
**Target:** Gauge Pro prototype 0.1 — Lua LVGL widget
**Branch:** `feat/gauge-v2` (based on `origin/main`, fork clean main)
**Date:** August 4, 2026

---

# 1. Purpose

Design draft 0.2 defined the product vision, visual system, data model, and architecture for a
GaugeRotary successor. This document verifies every technical assumption of that draft against
the actual source tree of this fork, corrects what reality contradicts, and turns the result into
an executable delivery plan. It is the **planning deliverable**; no widget code is written yet.

Verified against:

| File | Role |
|---|---|
| `radio/src/lua/api_colorlcd_lvgl.cpp` | LVGL Lua object API (build/set/show/hide, object types, constants) |
| `radio/src/lua/lua_lvgl_widget.cpp` | Per-object property support (arc, line, label, box) |
| `radio/src/lua/lua_widget.cpp` / `.h` | Lua widget lifecycle (create/update/refresh/background, fullscreen) |
| `radio/src/lua/lua_widget_factory.cpp` | Widget option parsing and `MAX_WIDGET_OPTIONS` |
| `radio/src/lua/widgets.cpp` | Widget registration table fields (incl. `useLvgl`) |
| `radio/src/lua/api_general.cpp` | `getFieldInfo`, `getValue` |
| `radio/src/gui/colorlcd/libui/etx_lv_theme.h` | `lvgl.LCD_SCALE` values |
| `radio/src/gui/colorlcd/widgets/gauge.cpp` | Existing built-in C++ gauge (reference only) |
| `CMakeLists.txt` | Firmware version: **3.0** |

---

# 2. Repository reality (verified facts)

1. **This is the EdgeTX firmware fork, version 3.0** (`CMakeLists.txt`: `VERSION_MAJOR "3"`).
2. **The firmware repo contains no Lua widgets.** The only tracked `.lua` files are developer
   tools. Lua widgets are **SD-card content**: the radio scans `/WIDGETS/<Name>/main.lua`
   (`radio/src/lua/widgets.cpp:101` `luaLoadWidgetCallback`).
3. **GaugeRotary does not exist in this repo** — it is a community SD-card widget distributed
   outside EdgeTX repositories. It cannot be referenced, diffed, or tested from here; V2 must
   carry its own spec.
4. **The built-in "Gauge" widget is C++ and trivial** (108 lines, horizontal bar:
   `radio/src/gui/colorlcd/widgets/gauge.cpp`). It is not a rotary gauge and is not a basis for V2.
5. **The LVGL Lua binding is real and rich** but smaller than the draft assumed. Verified object
   types: `label`, `rectangle`, `circle`, `arc`, `hline`, `vline`, `line`, `triangle`, `image`,
   `qrcode`, `box` — plus interactive controls (button, toggle, numberEdit, choice, slider,
   source picker, …) that are **only created when the widget is fullscreen**
   (`api_colorlcd_lvgl.cpp:194` skips `ETX_FIRST_CONTROL..` when `!isFullscreen()`).
6. **There is NO LVGL `scale` widget, NO object rotation, and NO arc "value" property** in the
   binding. Arc updates use absolute angles; lines use absolute point coordinates.
7. **Widget options are capped at 50** (`datastructs_screen.h:92` `MAX_WIDGET_OPTIONS 50`).
   Draft's 10 options are safe. Option type indices: `Integer=0, Source=1, Bool=2, String=3,
   TextSize=4, Timer=5, Switch=6, Slider=8, Choice=9, File=10` (`widget.h:42`).
8. **Lua callbacks run under a 200-instruction budget** (`lua_widget_factory.cpp:29`
   `MAX_INSTRUCTIONS (20000/100)`). Per-frame work must be tiny; object creation and string
   formatting must be cached.
9. **`lvgl.LCD_SCALE` is a float**: 0.8 (320-wide), 1.0 (480-wide), 1.375 (800-wide)
   (`etx_lv_theme.h:58-70`). Draft's `px()` helper is valid.
10. **Theme colors exposed to Lua**: `COLOR_THEME_PRIMARY1..3`, `SECONDARY1..3`, `FOCUS`, `EDIT`,
    `ACTIVE`, `WARNING`, `DISABLED` (`api_colorlcd.cpp:1419+`). **There is no `CRITICAL` theme
    color** — the critical state must be derived.
11. **Fullscreen is supported for Lua widgets** (`lua_widget.cpp:446` `onFullscreen`), and
    interactive controls are legal there — the draft's optional reset control is feasible.
12. **`getFieldInfo` / `getValue` are available** (`api_general.cpp:634,707`) for metadata
    caching and table (`CELLS`) aggregation.
13. **Widget registration** is `{ name, options, create, update, refresh, background, translate,
    useLvgl=true }` (`widgets.cpp:112-144`). `useLvgl=true` switches the widget to the LVGL
    rendering path (`lua_widget.cpp:260`).

---

# 3. Corrections to design draft 0.2

## 3.1 PR target — CORRECTED (critical)

Draft §36 proposed "PR to the EdgeTX repo". **A Lua widget cannot be merged into the firmware
repo** (fact 2). The corrected delivery paths:

| Path | Target | Verdict |
|---|---|---|
| **A. Standalone distribution** (like GaugeRotary) | Forum/RCGroups + own GitHub release | Primary; zero review friction; matches the ecosystem GaugeRotary lives in |
| **B. Dev showcase PR** | `EdgeTX/edgetx-sdcard` → `dev/WIDGETS/GaugePro/` | The only EdgeTX-org repo that accepts Lua widgets (precedent: `dev/WIDGETS/Counter`). Optional, maintainer acceptance not guaranteed |
| **C. C++ firmware widget** | firmware `radio/src/gui/colorlcd/widgets/` | Real firmware PR, but a different engineering stack (C++/LVGL) and much larger scope; keep as a documented future path, **not** prototype 0.1 |

Recommendation: develop on this branch as **A**, and prepare a clean patch for **B** from the
same code so the "EdgeTX PR" intent is honored where the ecosystem actually accepts Lua widgets.

## 3.2 Version target — CORRECTED

Draft §7.2 proposed minimum EdgeTX 2.11. This fork is **3.0**; `lvgl` exists and is stable here.
Decisions:

- Development and testing: **EdgeTX 3.0** (this fork, Companion Simulator).
- Runtime guard: `if not lvgl then` → show a compatibility label and return. This keeps 2.10 and
  earlier from failing silently, without maintaining a legacy `lcd` renderer.

## 3.3 Renderer API — CORRECTED (binding facts)

- **Arc**: range is fixed 0–360. Track = `bgStartAngle`/`bgEndAngle` (MAIN part), active arc =
  `startAngle`/`endAngle` (INDICATOR part); `thickness`, `rounded`, `color`, `bgColor`,
  `opacity` supported (`lua_lvgl_widget.cpp:1849-1978`). The draft's "one numeric property per
  frame" becomes **one `endAngle` per frame** — same cost, computed in Lua:
  `endAngle = start + normalize(value) * sweep` (draft §12 math stands).
- **Line**: `pts` accepts a table **or a function** that is re-evaluated on every `lvgl.set()`
  and applied only when the point hash changes (`lua_lvgl_widget.cpp:1031-1071`). The needle is
  a 2-point line with a `pts` function; ticks are static lines with precomputed absolute points.
- **No rotation**: ticks, threshold markers, and needle are positioned via geometry-computed
  absolute coordinates. `geometry.lua` is mandatory, not optional.
- **Sections mode** falls back to separate arc segments (`bgStartAngle`..`bgEndAngle`) exactly
  as the draft anticipated (§7 finding 7 fallback) — confirmed as the *only* available
  mechanism. Fine for 3 sections.
- **Labels**: `text` (string or function — re-evaluated per `set`), `color`, `font`, `align`,
  `pos`, `opacity` (label class at `lua_lvgl_widget.cpp:813-891`).
- **`lvgl.build(parent, def)`** returns named refs; `lvgl.set(obj, {…})` updates properties
  without recreating objects; `lvgl.clear`/`show`/`hide` available
  (`api_colorlcd_lvgl.cpp:186-390`). Draft's object-caching architecture is fully supported.

## 3.4 Options — CONFIRMED with concrete types

Draft §24 table mapped to real type indices (fact 7):

| Option | Lua type | Index | Notes |
|---|---|---|---|
| Source | Source | 1 | |
| Min / Max / Warn / Critical | Integer | 0 | `{name, 0, default, min, max}` |
| HighGood | Bool | 2 | |
| Style | Choice | 9 | `{name, 9, default, {"Auto","Needle","Arc"}}` |
| ColorMode | Choice | 9 | `{name, 9, 1, {"Static","Threshold","Sections"}}` |
| Precision | Choice | 9 | |
| ShowMinMax | Bool | 2 | |

10 options ≤ 50 limit. No change to priorities.

## 3.5 Performance budget — CORRECTED

Per-callback instruction limit is 200 (`lua_widget_factory.cpp:29`). Draft §31's targets are
now hard constraints:

- Build phase (`update`): allowed heavy work (object creation) — but keep the total object count
  moderate (target: < 60 LVGL objects for a large gauge; ticks capped at 9 major + 18 minor).
- Refresh phase: **only** `lvgl.set` on changed properties; never rebuild; never allocate tables
  per frame; cache formatted strings; skip `set` when the value string is unchanged.
- `background`: data only (source read, min/max, staleness) — draft §26.4 confirmed by design
  (`lua_widget.cpp` calls it on the telemetry tick).

## 3.6 Colors — CORRECTED

Draft §15's state colors must map to what Lua can see:

- Normal → `COLOR_THEME_PRIMARY1` (or `COLOR_THEME_ACTIVE`)
- Warning → `COLOR_THEME_WARNING` (verified constant)
- Critical → **derived**: fixed high-contrast red (`lcd.RGB`/`COLOR2FLAGS` equivalent from the
  `lcd` constants — colorlcd Lua exposes `lcd.RGB(r,g,b)`); optionally blend with theme
  `DISABLED` fallback. Contrast targets from draft §32 kept.

## 3.7 No-data / availability — CONFIRMED

`getValue` per-source + `getFieldInfo` metadata caching (draft §20-21) are supported. The
draft's distinction between source-invalid and telemetry-disconnected stands; the widget must
read the source directly per refresh and track last-valid timestamps itself — EdgeTX does not
expose a per-source "valid" flag in Lua beyond the returned value.

---

# 4. Delivery plan

## 4.1 Git

- Branch `feat/gauge-v2` created from `origin/main` (7c07b6df7) — deliberately **not** from the
  unrelated `fix/lua-float-integer-equality` HEAD, so the future PR contains only Gauge Pro work.
- Untracked `.deb` files in the working tree are build artifacts of other work; they will not be
  committed.
- Commits: one logical commit per phase (below), conventional style matching the repo
  (`feat(widget): …`).

## 4.2 Repository layout (mirrors SD-card layout)

```
WIDGETS/GaugePro/
├── PLAN.md          ← this document
├── README.md        ← usage + compatibility statement (PR-ready)
├── main.lua         ← registration, options, lifecycle, compatibility guard
├── geometry.lua     ← clamp/normalize/angle→point/needle+tick point builders
├── layout.lua       ← responsive mode, aspect, geometry, typography, visibility
├── telemetry.lua    ← source resolution, metadata cache, value/table read, staleness, min/max
├── ranges.lua       ← threshold ordering, state detection
├── renderer.lua     ← lvgl.build tree, named refs, per-frame lvgl.set updates
└── presets.lua      ← (V2.0 phase) known-sensor profiles
```

Placement rationale: identical to the on-radio path (`/WIDGETS/GaugePro/main.lua`), so the
folder can be copied straight to the SD card or into the Companion simulator SD content; the
same tree is the PR payload for `edgetx-sdcard` (path B).

## 4.3 Widget contract (verified, this branch's firmware)

```lua
return {
  name = "GaugePro",
  options = { … },          -- §3.4 table
  create = create,          -- state init (zone, options, cache)
  update = update,          -- rebuild UI on config/size change (lvgl.build)
  refresh = refresh,        -- per-frame: lvgl.set only
  background = background,  -- telemetry data maintenance
  useLvgl = true,
}
```

---

# 5. Phases

Each phase ends with a verification gate (Companion Simulator on this fork; screenshots; manual
test on the target radio when available).

| # | Phase | Scope | Gate |
|---|---|---|---|
| 0 | Plan + branch | This document, branch `feat/gauge-v2` | — |
| 1 | API feasibility spike | Throwaway script on the simulator: arc endAngle updates, line pts function, label text function, build/set refs, LCD_SCALE values, theme colors, fullscreen control availability | Feasibility notes in README; risk list updated |
| 2 | Geometry library | `geometry.lua` + `ranges.lua` (pure Lua, testable off-radio) | Unit-style assertions with stock Lua 5.3 (available in repo toolchain) |
| 3 | Prototype 0.1 | `main.lua` + `layout.lua` + `renderer.lua`; scope exactly per draft §27 (manual range, thresholds, HIG/LIG, 270° gauge, track+active arc, line needle, pivot, value/unit/name, NORMAL/WARN/CRIT, square + horizontal, no-data, basic smoothing) | Draft §34 acceptance criteria on 480×272 and 800×480 simulator |
| 4 | Data engine | `telemetry.lua`: metadata cache, table aggregation, staleness, min/max history | Local source without telemetry; disconnected-source cases |
| 5 | Responsive system | micro/compact/normal/large, vertical, full-screen | Draft §33.2 layout matrix screenshots |
| 6 | History + presets | min/max markers; `presets.lua` | Draft §33.4 boundary values |
| 7 | PR preparation | README, screenshots, comparison notes vs GaugeRotary, test matrix, compatibility statement | Code frozen; branch pushed; PR drafted to `edgetx-sdcard` (path B) |

Prototype 0.1 (phases 1–3) is the PR-1-sized slice. Phases 4–6 are PR-2-sized.

---

# 6. Test matrix (adjusted for this repo)

- Resolutions (Companion targets available for this fork): 320×240, 320×480, 480×272,
  480×320, 800×480.
- Layout sizes: smallest widget cell, micro, compact, balanced, wide, narrow, half screen,
  full screen.
- Sources: stick, channel, timer, TX battery, RSSI, RQly, voltage, temp, RPM, `CELLS` table,
  invalid source, disconnected telemetry source, local source with telemetry off.
- Values: below/at/above min and max, boundaries of warn and critical, min==max, inverted
  config, negatives, decimals.
- Dynamic: slow, rapid, noisy, step, source change, range change, telemetry loss/recovery,
  resize, theme switch (dark/light/high-contrast).
- Performance: 4 simultaneous Gauge Pro widgets, no perceptible slowdown (draft §31).

---

# 7. Acceptance criteria (prototype 0.1 — updated)

1. Loads without errors on this fork (EdgeTX 3.0); pre-2.11 guard shows a compatibility label.
2. Arc responds to min/max with correct angle mapping; no integer stepping of the needle.
3. High-is-good and low-is-good both correct.
4. Normal/Warning/Critical colors correct and contrast-adequate in dark and light themes;
   critical color derived per §3.6.
5. Local sources render while telemetry is off; no-data state never blinks.
6. Square and horizontal layouts correct; resizing rebuilds only on structural change.
7. Per-frame refresh touches only changed `lvgl.set` properties; no object churn.
8. Option set fits the verified type indices (§3.4) and 50-option cap.

---

# 8. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| 200-instruction refresh budget exceeded | High | Object-count caps, string caching, set-only-on-change discipline (phase 1 measures real cost) |
| `pts` function overhead on many tick lines | Medium | Ticks are static: points precomputed at build; only the needle uses a pts function |
| Fullscreen interactive controls differ across radios | Low | Controls are prototype-excluded; full-screen is display-only in 0.1 |
| Arc rounded ends render inconsistently | Low | `rounded` is binding-supported; verify visually in phase 1 |
| Community gauge expectations (GaugeRotary parity) | Medium | Feature checklist in README documenting V2.0 parity vs GaugeRotary capabilities (draft §5) |

---

# 9. Open questions (updated)

1. Does Companion's Lua debug console report LVGL widget errors usefully? (drives phase 1 workflow)
2. Actual per-frame `refresh()` rate on hardware (drives smoothing constants).
3. Which of `COLOR_THEME_*` constants give ≥ 4.5:1 on default and light themes (measure in phase 1).
4. Maintainer appetite in `edgetx-sdcard` for a full widget under `dev/WIDGETS` (path B viability).
5. Reset-control interaction for full-screen min/max — deferred, needs hardware touch verification.
6. Should preset defaults initialize once or track sensor metadata (draft §37.10) — decision deferred to phase 6.

---

# 10. Immediate next step

Phase 1: API feasibility spike on the Companion Simulator, then geometry library with stock
Lua tests. Prototype 0.1 code follows in the branch per §5.
