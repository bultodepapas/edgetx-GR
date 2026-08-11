# Gauge Pro Bar v2 — Phase 4 report

> **Histórico:** evidencia pre-split de Bar, hoy `GaugeBarPro`/`BarPro`. Consulte
> [`DOCUMENTATION.md`](DOCUMENTATION.md) para la arquitectura vigente.

**Completed:** 2026-08-09  
**Scope:** Production Blocks, Hex, Fine Ticks and Signal Steps faces, their
presets and source-aware Auto mapping. Signed Dual Rail, vertical/zero-origin
axes and configurable motion remain Phase 5/6 work.

## Outcome

Gauge Pro now offers four additional ways to read the same truthful telemetry
model. They are not decorative masks: each face retains the shared numeric
value, exact position head, warning/critical thresholds, history, availability
states, safety badge, palette rules and critical pulse while emphasizing a
different operational question.

- **Blocks** makes discrete progress and capacity glanceable while its current
  cell preserves the exact partial fraction.
- **Hex** gives battery/system telemetry a distinctive technical silhouette;
  every true cell is one rectangle plus two static retained triangles.
- **Fine Ticks** emphasizes position and change rate through a major/minor
  rhythm, exact warning/critical ticks and a separate exact head.
- **Signal Steps** uses rising height for immediate RC-link recognition while
  keeping the numeric RSSI/RQly reading dominant.

Classic green/amber/red remains the default severity language. Every face also
supports Theme Adaptive, exact Custom Three/Custom Two anchors, custom
surfaces, contrast assistance and all five Colour modes. HTX theme changes
repaint retained objects in place without rebuilding or replacing authored
colors.

## What shipped

- Blocks with 6–24 cells, square/soft geometry, physical Tight/Normal/Wide
  gaps and exact partial-cell opacity.
- True Hex with 6–10 responsive cells, static seams at LCD scales 0.8, 1.0 and
  1.375, and an explicit compact block variant when a real tip cannot fit.
- Fine Ticks with 8–28 marks, readable two-pixel stock-scale strokes, stronger
  endpoints/fifths, threshold ticks forced onto exact shared threshold x
  coordinates, and retained range-only updates for fast sources.
- Signal Steps with 5–10 strictly increasing rectangles on one baseline.
- Source-aware Auto appearance: RSSI/RQly/VFR-style sources select Steps;
  other signal sources select Ticks; batteries select Hex; capacity selects
  Blocks. Explicit overrides still win and stored options are never mutated.
- Polished Classic, Theme, Hex, Blocks, Ticks, Minimal and Bold Data presets.
- Five honest color readings per face: Static neutral reference, Threshold
  state-active scale, Rail permanent severity context, spatial Gradient and
  complete semantic Sections.
- Shared retained dirty buffers, one reusable segment paint table and
  range-only activation updates. Moving faces allocate no per-cell tables.
- Staged structural settings rebuilds. Parsing/configuration, tree construction
  and ordinary paint occupy separate callbacks, so dense trees never approach
  the firmware kill limit.

## Correctness evidence

New regressions cover:

- production renderer selection and the still-explicit Phase 5 Dual fallback;
- preset precedence and source-aware Auto mapping for signal, battery,
  capacity, control and generic sources;
- partial-cell math, exact heads, full-scale and zero-scale behavior;
- true Hex seams and retained triangle point buffers at all shipped scales;
- compact Hex downgrade reporting;
- tick major/minor hierarchy and exact threshold alignment;
- increasing step heights and shared baseline;
- four faces × five Colour modes with rejected visual collapse;
- whole-tree object ceilings in feature-rich 480×120 layouts;
- live HTX theme changes for every face without rebuild or object churn;
- critical pulse isolation to the exact head, dropout clearing, reconnect and
  retained-tree recovery for every face;
- staged dense structural edits and the one-frame build/paint boundary;
- compact, standard and rich collision cases for every Phase 4 face.

## Measured gates

| Gate | Phase 4 result |
|---|---:|
| Pure Lua tests | **61 / 61** |
| Lifecycle / firmware-contract tests | **178 / 178** |
| Luacheck (35 authored Lua files) | **0 warnings / 0 errors** |
| Production catalogue | **151 scenes per theme, 0 failed** |
| Visual themes | **stock + dark + high contrast** |
| Gallery warnings | **0** |
| Visual option coverage | **complete** |
| Face × Colour-mode matrix | **20 / 20 distinct** |
| Collision audit | **all cases clean, including 12 Phase 4 face/zone cases** |
| Firmware-layout atlas | **17 layouts current** |
| Phase 0 feasibility/budget probe | **PASS** |
| Blocks 24 retained objects | **37 / 38** |
| True Hex 10 retained objects | **40 / 40** |
| Fine Ticks 24 retained objects | **37 / 40** |
| Signal Steps 10 retained objects | **23 / 32** |
| Dense Blocks changing frame | **1,932 instructions** |
| Dense Hex changing frame | **1,952 instructions** |
| Dense Ticks changing frame | **1,854 instructions** |
| Dense Steps changing frame | **1,432 instructions** |
| Phase 4 state transition | **≤ 5,200 instructions** |
| Phase 4 structural frame | **≤ 7,800 instructions** |
| Dense-face steady allocation | **32 B/frame total; no face table churn** |
| Worst audited Phase 4 callback | **7,800 / 20,000 (61% headroom)** |

The instruction probe now fails automatically when any production bar reaches
2,000 instructions on ordinary motion, 6,000 on a state transition, 10,000 on
a structural frame or 20,000 on any callback. The allocation probe disables
the harness audit trail, stops GC and measures 100 changing frames.

## Visual evidence

- `docs/phase4/full-validation/gallery-stock.svg` / `.png`
- `docs/phase4/full-validation/gallery-dark.svg` / `.png`
- `docs/phase4/high-contrast/gallery-highcontrast.svg` / `.png`
- `docs/gauge-pro-options.svg` / `.png`
- `docs/gauge-pro-options-dark.svg` / `.png`
- `docs/gauge-pro-options-highcontrast.svg` / `.png`

All 151-scene sheets and the 32-scene focused Phase 4 sheet were regenerated
from the production retained object tree. Chrome headless rasterized the final
stock/dark/high-contrast SVGs for pixel review. That review found Fine Ticks
too faint at one pixel; the production face was strengthened to a readable
major/minor opacity and two-pixel stock-scale stroke, then every automated and
visual gate was rerun.

## Explicit deferrals

- Centered Dual Rail: Phase 5, together with truthful signed zero-origin axes.
- Vertical bars and asymmetric zero-origin mapping: Phase 5.
- Refined/Expressive motion profiles and transition animation: Phase 6.

The frozen options already resolve these requests deterministically. Unsupported
axis/origin combinations report their fallback instead of pretending the
requested visual exists.
