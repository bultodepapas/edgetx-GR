# Gauge Pro Bar v2 — Phase 0 execution report

**Status:** Complete  
**Executed:** 2026-08-09  
**Code baseline:** `d46102e26634cadd069e7d44d8a887e421957ee0`  
**Scope:** Product contracts, truthful evidence, EdgeTX zone coverage, risky-primitive feasibility, and pre-architecture hygiene. No Phase 1 settings and no production face redesign were introduced.

Related artifacts:

- [Ambitious implementation plan](BAR_STYLE_IMPROVEMENT_PLAN.md)
- [Generated EdgeTX zone atlas](PHASE0_ZONE_ATLAS.md)
- [Stock-theme bar baseline](docs/phase0/gallery-stock-only-barra.svg)
- [Dark-theme bar baseline](docs/phase0/gallery-dark-only-barra.svg)
- [Machine-readable baseline manifest](docs/phase0/manifest-only-barra.lua)
- [Feasibility probe](dev/phase0_probe.lua)
- [Zone-atlas generator](dev/zone_atlas.lua)
- [Intensive visual and test validation](PHASE0_VALIDATION_REPORT.md)

## 1. Frozen product contract

The bar work is governed by three coequal acceptance criteria:

1. **Useful:** the value, direction, thresholds, availability, stale state, warning/critical state, and history remain operational information—not decoration.
2. **Beautiful:** the default should feel deliberately composed, modern, and at the quality level of the current dial; gradients, depth, and motion are used only when they clarify state or hierarchy.
3. **Customizable:** presets provide coherent starting points, then users may override face, thickness, direction, density, palette, surface, marks, labels, and motion without losing telemetry truth.

The default remains the universally understood classic semantic scale: green normal, yellow/amber warning, red critical. Theme integration and semantic severity are separate layers:

- the active EdgeTX theme owns surrounding surfaces, neutral track/panel roles, ordinary text, and chrome;
- the bar palette owns semantic normal/warning/critical colors;
- Theme Adaptive and user-defined palettes are explicit alternatives, never silent replacements for Classic;
- warning and critical always retain a non-color cue;
- transparent rendering may be offered, but Auto must establish a controlled surface wherever wallpaper contrast is unknowable.

The configuration model is **preset plus overrides**. A preset is resolved data, not a locked theme and not a second settings system.

## 2. What the current code taught us

The existing bar is small but not disposable. It already has several contracts worth preserving:

- `app.lua` owns telemetry/configuration and dispatches one painter; alert logic is shared.
- `layout.lua` has a five-stage short-bar degradation ladder, LCD-scale-aware padding, marker-overhang containment, value fitting, and value-first information priority.
- `bar.lua` uses retained objects, persistent history point buffers, threshold marks above the fill, shared state badges, shared pulse behavior, and no object creation during refresh.
- `theme.lua` already separates status geometry from data text and provides self-grounded badge ink.
- the current body is only one track rectangle plus one fill rectangle; Rail, Threshold, Sections, and Gradient mainly change color/reference behavior rather than offering genuinely distinct spatial faces.
- descending history is incomplete: the sweep ghost and the only explicit min marker both resolve to `history.min`; there is no independent max marker.

The implementation strategy therefore keeps telemetry, alerts, formatting, retained update patterns, safety badges, and compact degradation. Phase 1 adds appearance resolution around those contracts; later phases replace only the bar body and its layout strategy.

## 3. Baseline locked

### 3.1 Visual evidence

Eight existing bar scenes were rendered under the real stock light palette and the representative dark palette. Both strict gallery runs completed with zero scene failures and zero render warnings. The committed SVGs and manifest above are the before-redesign reference.

The gallery still reports that many non-bar-specific options are not varied inside the `barra` section. That is expected: the complete gallery covers them elsewhere. Phase 7 will add face/palette-specific variants rather than pretending this narrow baseline is full option coverage.

### 3.2 Current retained-object baseline

| Scene | Visible objects |
|---|---:|
| Bar 300×70, normal/default | 9 |
| Bar 300×70, Sections + min/max text + CRIT | 12 |
| Dial 200×200 worst existing scene | 33 |

Replacing the current track and fill leaves a conservative **10-object shared bar reserve** for value/unit/name, state badge, threshold references, and history. Phase 0 face budgets use that measured reserve.

### 3.3 CPU and allocation baseline

| Bar path | Result |
|---|---:|
| Structural `update()`/rebuild | 20 hook fires = about 4,000 VM instructions |
| Ordinary changing refresh | 11 fires = about 2,200 instructions |
| Idle refresh | 2 fires = about 400 instructions |
| Steady changing-value allocation | about 310 B/frame |
| Steady changing-value instruction estimate | about 814 instructions/frame |

The whole existing widget's measured worst callback remains the 360-degree Sections dial rebuild at about 10,200 instructions, leaving 49% headroom below the firmware's 20,000-instruction kill limit. Bar v2 must not consume that dial headroom merely because the current bar is cheaper.

### 3.4 Frozen option wire contract

Slots are positional and append-only. EdgeTX 2.11 exposes the first 10; 2.12+ exposes all 24 current slots.

| Slots | Frozen keys |
|---|---|
| 1–10 | Source, Min, Max, Warn, Crit, HighGood, Style, ColorMode, Precision, ShowMinMax |
| 11–24 | Accent, Label, Suffix, Scale, Sweep, Damping, Cells, Battery, Alerts, AlertSw, Delay, Vibrate, ResetSw, ShowChip |

The existing frozen-slot test remains exact. Phase 1 must change it to freeze this 24-slot sequence as a prefix before appending anything.

`VALUE` is `WidgetOption::Integer`: defaults, minima, maxima, stored values, and Lua delivery are signed integers. Therefore manual scale and threshold options cannot represent fractional endpoints. This is an EdgeTX option-type limitation, not a formatting bug; displayed telemetry may still contain decimals.

## 4. EdgeTX zone atlas

The atlas generator parses all layout `zmap` arrays from the checked-out firmware instead of copying their geometry. It covers:

- 16 standard layout templates;
- the separate 1×1 app-mode layout;
- 320×240 (`LCD_SCALE=0.8`), 480×272 (`1.0`), and 800×480 (`1.375`);
- every meaningful boolean branch in `ViewMainDecoration::getWidgetsZone`: top bar, flight mode, sliders, vertical sliders, trims, visible vertical/horizontal trims, and six-position-switch behavior;
- every supported top-bar span on each display family.

Results:

- 162 meaningful decoration/hardware inputs per display family;
- 60 unique widget roots per display family;
- 180 target-specific roots total;
- 6,570 exact unique `(x,y,w,h)` rectangles after layout integer truncation, including top-bar spans and app mode;
- every rectangle classified using the existing micro/compact/normal/large thresholds plus `topbar-micro`, `short-strip`, `tall`, or `balanced` subprofiles.

The atlas is intentionally a conservative geometry superset: different radios expose different hardware branches, while the bar must be safe in every rectangle EdgeTX can produce. `lua dev/zone_atlas.lua ./ --check` detects drift when firmware layouts change.

## 5. Risky primitive feasibility

### 5.1 Spatial gradients

The checked-out Lua rectangle binding exposes fill, outline thickness, opacity, position/size, and radius—but no LVGL gradient descriptor. Portable gradients must therefore use retained, gapless rectangle slices.

| Slices | Prototype build instructions | Total with 10 shared objects | Decision |
|---:|---:|---:|---|
| 12 | ~1,600 | 22 | Supported |
| 20 | ~2,800 | 30 | Supported |
| 24 | ~3,400 | 34 | Portable maximum |
| 32 | ~4,400 | 42 | Rejected by object budget |

The integer partition was verified without gaps at 120, 300, and 800 pixels. Production gradients will build at most 24 slices and update only crossed slices plus one exact partial head. A native binding may be proposed separately if 24 slices remain visibly banded at large 800-pixel widths; it cannot be a portability dependency.

### 5.2 True hex cells

A true retained hex uses exactly three supported objects: one rectangle and two triangles. Ten cells were built successfully at all shipped LCD scales:

| LCD scale | Prototype size | Objects | Build instructions |
|---:|---:|---:|---:|
| 0.8 | 240×19 | 30 | ~4,400 |
| 1.0 | 300×24 | 30 | ~4,400 |
| 1.375 | 413×33 | 30 | ~4,400 |

With the 10-object shared reserve, ten true hexes land exactly on the 40-object ceiling. Six is the compact floor. No option may promise more than ten true hexes; when points cannot remain crisp, the documented compact block/chamfer fallback is required.

### 5.3 Vertical and zero-origin geometry

The prototype pins the authored scale start to the bottom and the authored scale end to the top. Ascending, descending, and `-100..100` zero-origin mappings passed. Separate value/body/name regions passed at representative 320-, 480-, and 800-scale tall zones, with at least 64 logical pixels retained for the current-position body.

This proves a vertical retained construction is feasible. It does not ship vertical production layout early; that remains Phase 5.

### 5.4 Theme switching and wallpaper grounding

Badge ink decisions now include the resolved active theme ink roles, not only the stable numeric fill flag. A theme-role swap therefore invalidates the decision when the resolver is invoked. Automatic theme-change detection and whole-face re-resolution remain explicit Phase 3 work.

Wallpaper policy is now fixed:

- filled state badges are self-grounded because the widget controls both fill and ink;
- transparent ordinary text or thin marks cannot guarantee contrast over an arbitrary photograph;
- Auto uses a controlled EdgeTX-theme panel/scrim wherever those elements need grounding;
- Transparent remains an explicit user choice.

### 5.5 Face object budgets

| Face | Body pool | Shared reserve | Total | Plan ceiling | Result |
|---|---:|---:|---:|---:|---|
| Continuous | 4 | 10 | 14 | 24 | Pass |
| Continuous gradient | 24 | 10 | 34 | 38 | Pass |
| Blocks | 16 | 10 | 26 | 38 | Pass |
| Hex | 30 | 10 | 40 | 40 | Pass at cap |
| Fine ticks | 24 | 10 | 34 | 40 | Pass |
| Steps | 10 | 10 | 20 | 32 | Pass |
| Dual rail | 8 | 10 | 18 | 36 | Pass |

All are feasible as retained-mode constructions. The counts are ceilings/pools, not permission to show maximum detail in every zone.

## 6. Evidence and deployment repairs completed

- Replaced invented/monotonic font estimates with the exact `sml`, `std`, and `lrg` EdgeTX line heights. XXL (`0x600`) and LXL (`0x700`) are now distinct and correctly ordered.
- The truthful font metrics exposed a real 46-pixel bar regression: enabling the name and larger padding temporarily removed the safety state row. Padding is now a degradation rung, restoring monotonic behavior at every LCD scale.
- Added UTF-8 regressions and changed source-name cleanup to strip only invalid leading UTF-8 bytes. Valid two-, three-, and four-byte names are preserved.
- Made badge contrast cache entries sensitive to resolved active-theme inks.
- Removed obsolete “still broken” captions for descending state, min/max ghost visibility, cell percentage, and hot accent repainting.
- Extended the SD deployment manifest for future `bar_style.lua` and `bar_faces.lua` modules without requiring them before Phase 1.
- The deployment helper now validates the exact `WIDGETS/GaugePro` target and removes only top-level stale `*.luac` siblings before copying. A disposable SD-tree probe verified 14 current runtime modules and removal of one stale bytecode file.
- Added a worst-case bar row to the retained-object census.

## 7. Deliberately deferred, with owners

| Item | Evidence | Owner phase |
|---|---|---:|
| Independent descending min and max markers | Probe reproduces `ghostX == minX` and no `maxMark` | Phase 2.1 |
| Settings schema/preset/palette resolver | Existing 24 slots remain unchanged | Phase 1 |
| Production theme-adaptive re-resolution | Resolver invalidates correctly; event/polling contract not yet implemented | Phase 3 |
| Rich gradients/blocks/hex faces | Primitive and object budgets proven only | Phases 3–5 |
| Vertical production face | Axis/region feasibility proven only | Phase 5 |
| Motion | No animation added during foundation work | Phase 6 |
| Optional native gradient binding | Lua binding confirmed absent | Separate firmware proposal only if justified |

## 8. Verification record

The following commands are the Phase 0 gate:

```text
lua tests/run_tests.lua ./                         38 passed, 0 failed
lua tests/smoke_test.lua ./                       143 passed, 0 failed
lua dev/phase0_probe.lua ./                       PASS
lua dev/zone_atlas.lua ./ --check                 current, 17 layouts
lua dev/gallery.lua ./ --only barra --theme both --strict
                                                    8 scenes, 0 failures/warnings
lua dev/census.lua ./                             worst bar 12; worst dial 33
lua dev/instructions.lua ./                       bar max ~4,000; global max ~10,200
lua dev/measure_frames.lua ./                     bar ~310 B/frame, ~814 instr/frame
dev/sync-sd.ps1 against disposable SD tree        14 modules; stale .luac removed
```

## 9. Exit-gate decision

**Phase 0 passes.**

- Useful/Beautiful/Customizable and the theme/semantic separation are frozen.
- Current behavior has reproducible visual, object, CPU, allocation, option, and known-gap baselines.
- Every proposed face has a supported retained-mode construction and explicit object ceiling.
- Every EdgeTX layout/decor/top-bar geometry has a deterministic responsive family.
- The font, UTF-8, theme-contrast, scene-caption, and SD-copy evidence is trustworthy.
- Known production work is assigned to later phases instead of being hidden inside the foundation milestone.

Phase 1 may now begin with personalization architecture while keeping the default render and the first 24 option slots unchanged.

The subsequent [intensive validation pass](PHASE0_VALIDATION_REPORT.md)
expanded the canonical catalog to 79 scenes in both themes, regenerated every
visual artifact, added two responsive regressions, unified all visual tools on
the measured font map, and completed with zero render warnings.
