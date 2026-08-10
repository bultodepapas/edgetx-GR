# Gauge Pro Bar v2 — Phase 3 report

**Completed:** 2026-08-09  
**Scope:** Color freedom for the horizontal Continuous Precision Rail. Phase 4
alternate faces, Phase 5 vertical/zero-origin rendering and Phase 6 motion
profiles remain out of scope.

## Outcome

The bar now treats personalization as a first-class instrument contract.
Classic Severity remains the understandable green/amber/red default, while HTX
Theme Adaptive and exact Custom Three/Custom Two palettes receive the same
retained geometry, threshold truth, history, state badge and critical pulse.

Gradient is no longer one flat color selected by the current reading. It is a
real spatial severity scale made from retained, gapless slices, with an exact
partial slice and exact position head. Contrast help is structural: Gauge Pro
strengthens the local ground, head and marks while preserving every authored
color.

## What shipped

- Exact normal, warning, critical, track and panel COLOR payloads. Tests cover
  purple/yellow, blue/orange/red, monochrome, pastel and high-saturation
  families plus the shared radio/Companion integer wire format.
- Theme Adaptive resolves ACTIVE and WARNING honestly, retains the fixed
  critical fallback, and resolves all theme chrome/ink roles to current RGB.
  A minimal signature probe runs at most once per second on visible bars.
- Theme changes recolor the retained panel, track, casing, history, value/name
  ink, badge ink, gradient slices and head without a layout rebuild or object
  creation. Palette and badge caches are signature-keyed and bounded.
- An 8–24 slice spatial gradient calibrated by physical rail length and the
  remaining whole-face object budget. Integer slice boundaries are contiguous;
  only a crossed boundary pool and the current partial slice change as the
  value moves.
- Ascending, descending, high-is-good and low-is-good scales share one authored
  scale mapping. Explicit warning/critical marks and WARN/CRIT badges remain
  above the color scale.
- Classic interpolation retains the approved constant-luminance ramp. Theme
  and custom ramps preserve exact anchors and use gamma-aware linear-light
  intermediate colors.
- Contrast Off, Auto and Strong. Auto combines ordinary distance, adjacent
  contrast and protanopia/deuteranopia/tritanopia simulation when the cheaper
  tests cannot decide. Assistance changes casing opacity, local track ground,
  head thickness and Strong threshold thickness—not stored colors.
- Geometry-only option updates reuse the current palette; gradient color work
  is split into the first retained paint. This keeps every bar callback below
  the phase CPU target.

## Correctness evidence

New regressions cover:

- exact five-color option payload round trips and hot recoloring;
- theme polling throttle, signature invalidation and in-place gradient/badge
  recoloring;
- palette/signature/ink cache bounds;
- CVD simulation and monochrome WARN/CRIT redundancy;
- spatial direction for high-is-good, low-is-good and descending scales;
- 8–24 physical slice calibration and remaining-budget reduction;
- gapless integer geometry, exact partial width, zero/full spans and threshold
  overlays;
- retained references and zero object creation while values move;
- Off/Auto/Strong structure with exact unchanged anchors;
- canonical and rich-layout 38-object hard ceilings.

## Measured gates

| Gate | Phase 3 result |
|---|---:|
| Pure Lua tests | **60 / 60** |
| Lifecycle / firmware-contract tests | **168 / 168** |
| Luacheck (`*.lua dev/*.lua tests/*.lua`) | **0 warnings / 0 errors (35 authored files)** |
| Production catalogue | **119 scenes per theme, 0 failed** |
| Visual themes | **stock + dark + high contrast** |
| Gallery warnings | **0** |
| Visual option coverage | **complete** |
| Collision audit | **all audited cases clean** |
| Firmware-layout atlas | **17 layouts current** |
| Phase 0 feasibility/budget probe | **PASS** |
| Canonical gradient retained objects | **38 / 38** |
| Panel/chamfer/markers gradient | **38 / 38** |
| Default solid changing frame | **1,192 instructions** |
| Gradient changing frame | **1,772–1,798 instructions** |
| Gradient structural rebuild | **9,600 instructions** |
| Gradient first retained paint | **9,000–9,200 instructions** |
| Gradient stable allocation | **337 B/frame** |
| Worst audited callback overall | **10,800 / 20,000 (46% headroom)** |

The overall worst callback remains the pre-existing 360-degree dial rebuild.
Every Phase 3 bar callback is at or below 9,600 instructions. The gradient's
ordinary value-changing frame stays below the 2,000-instruction production-face
gate and retains zero face-owned point/table allocation.

## Visual evidence

- `docs/phase3/full-validation/gallery-stock.svg` / `.png`
- `docs/phase3/full-validation/gallery-dark.svg` / `.png`
- `docs/phase3/high-contrast/gallery-highcontrast.svg` / `.png`
- `docs/gauge-pro-options.svg` / `.png`
- `docs/gauge-pro-options-dark.svg` / `.png`
- `docs/gauge-pro-options-highcontrast.svg` / `.png`

All three 9,808-pixel validation sheets were regenerated from the production
retained object tree. The final audit also regenerated 125 close-up SVGs per
theme. Pixel review covered vivid, pastel and monochrome palettes;
Auto/Off/Strong; compact and large bars; descending and low-is-good scales; and
Theme Adaptive under every fixture. Chrome headless rasterized the committed
PNG evidence after the gallery correctly reported that its optional portable
rasterizers were unavailable.

## Explicit deferrals

- Blocks, Hex, Fine Ticks, Steps and Dual Rail production renderers: Phase 4.
- Vertical axes and zero-origin/centered signed rails: Phase 5.
- Configurable refined/expressive motion profiles: Phase 6.

Those choices continue to resolve through the frozen option contract and use
the explicit Continuous fallback; Phase 3 does not pretend a later face exists.
