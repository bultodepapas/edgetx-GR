# Gauge Pro Bar v2 — Phase 2 report

> **Histórico:** evidencia pre-split de Bar, hoy `GaugeBarPro`/`BarPro`. Consulte
> [`DOCUMENTATION.md`](DOCUMENTATION.md) para la arquitectura vigente.

**Completed:** 2026-08-09  
**Scope:** Perfect the flagship horizontal Continuous default without pulling
the Phase 3 gradient renderer, Phase 4 faces, Phase 5 axis/origin work, or Phase
6 motion profiles forward.

## Outcome

The default bar is now the **Continuous Precision Rail**, not the former pair
of rectangles. It preserves the dial's data/state hierarchy while adding a
self-grounded casing, neutral track, permanent severity reference channel,
semantic active fill, exact position head, explicit threshold marks, and three
independent history readings.

The implementation keeps the project rule intact: useful first, then beautiful,
then personal. A pilot can change thickness, end shape, surface and palette
without weakening range truth or alert semantics.

## What shipped

- Four real thicknesses: Thin, Medium, Thick and Maximum. They resolve inside
  the existing containment-proven bar slot; large zones receive a larger
  physical default and short zones retain the five-rung degradation ladder.
- Three materially different ends: round, square and true chamfer. Chamfer uses
  retained rectangle + triangle primitives and a retained active start cap.
- Transparent, HTX theme-panel and exact custom-panel surfaces. Custom panels
  keep the user's color and select the better existing theme ink on top.
- Classic Rail permanently shows warning and critical reference zones in a
  lower channel. Sections permanently shows all three semantic bands. Static,
  Threshold and Gradient retain distinct, tested reading models.
- One exact retained position head. It shares the same normalized axis as fill,
  thresholds and history and reuses its point/set buffers on every frame.
- Separate ghost, minimum and maximum markers. Min/max can appear and disappear
  independently; descending scales place all three at their authored positions.
- Responsive profile facts for micro, short, compact, standard, tall and large.
  Existing wide zones remain horizontal. Vertical rendering and zero origin
  remain explicit Phase 5 fallbacks.
- Stock, representative dark and explicit high-contrast visual fixtures.

## Correctness evidence

New regressions cover:

- ascending and descending scales;
- low-is-good and high-is-good ranges;
- a -100..+100 zero crossing;
- clamped out-of-range readings;
- threshold order and every Colour mode;
- independent history visibility and reset behavior;
- exact head position and persistent buffers;
- all thicknesses, all end shapes and all surfaces;
- exact custom panel color and hot recoloring;
- high-contrast Theme panel behavior;
- no-op layout purity, retained object count and no object churn.

## Measured gates

| Gate | Phase 2 result |
|---|---:|
| Pure Lua tests | **55 / 55** |
| Lifecycle / firmware-contract tests | **161 / 161** |
| Luacheck | **0 warnings / 0 errors** |
| Production catalogue | **109 scenes per theme, 0 failed** |
| Visual themes | **stock + dark + high contrast** |
| Gallery warnings | **0** |
| Visual option coverage | **complete** |
| Collision audit | **all audited cases clean** |
| Firmware-layout atlas | **17 layouts current** |
| Phase 0 feasibility/budget probe | **PASS** |
| Default bar changing frame | **1,130 instructions (5.7%)** |
| Stable per-frame allocation | **310 B/frame** |
| Bar structural update/build probe | **8,200 instructions** |
| Continuous theoretical worst | **21 / 24 objects** |
| Worst audited callback | **10,600 / 20,000 (47% headroom)** |

The head originally had a second moving halo. Pixel review found it visually
negligible while the instruction probe put the default above the plan's 1,200
instruction gate. Removing only that halo brought the bar to 1,130; the exact
head, casing, permanent rail and all safety cues remain.

## Visual evidence

- `docs/phase2/full-validation/gallery-stock.svg` / `.png`
- `docs/phase2/full-validation/gallery-dark.svg` / `.png`
- `docs/phase2/high-contrast/gallery-highcontrast.svg` / `.png`
- `docs/gauge-pro-options.svg` / `.png`
- `docs/gauge-pro-options-dark.svg` / `.png`
- `docs/gauge-pro-options-highcontrast.svg` / `.png`

The SVG gallery itself is generated directly from the real retained LVGL object
tree. Chrome headless produced the committed PNG review artifacts; the
Playwright wrapper was attempted first, but its Linux-side Chrome distribution
was not installed in this environment.

## Explicit deferrals

- Gapless spatial gradient slices and contrast-assistance structures: Phase 3.
- Blocks, Hex, Fine Ticks, Steps and Dual Rail renderers: Phase 4.
- Vertical axes, zero origin and centered signed rails: Phase 5.
- Configurable state transitions and motion profiles: Phase 6.

These choices still resolve through the Phase 1 contracts and expose an explicit
fallback/downgrade; no unavailable feature silently pretends to be complete.
