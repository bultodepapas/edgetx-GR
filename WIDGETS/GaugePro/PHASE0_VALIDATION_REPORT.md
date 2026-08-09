# Gauge Pro — Phase 0 intensive validation report

**Status:** PASS  
**Executed:** 2026-08-09  
**Scope:** Rebuild and validate the complete current Gauge Pro visual system,
stress the Phase 0 evidence, repair in-scope regressions, and verify that the
implementation still follows the approved phased plan.

This report validates the Phase 0 foundation. It does **not** claim that the
current rounded bar is the finished Bar v2 design. The missing faces, palette
freedom, vertical layouts, and motion remain assigned to later phases.

## 1. Outcome

The Phase 0 gate remains approved after a broader and stricter pass:

- 38 pure unit tests pass;
- 143 lifecycle/smoke tests pass;
- 79 canonical scenes render in both stock and dark themes;
- all visual options have at least one variant in the complete gallery;
- 170 indexed individual scene SVGs were regenerated: 85 per theme,
  including six intentional aliases per theme;
- 181 generated SVG artifacts parse as valid XML;
- zero generated SVGs contain the renderer's clipping/wrapping diagnostic;
- all geometry, object, instruction, allocation, zone-atlas, and deployment
  probes pass;
- the authoritative gallery manifest is deterministic across a repeated run.

## 2. Defects found by the intensive pass

### 2.1 Min/max captions wrapped in balanced 200×200 and 220×200 dials

The corrected EdgeTX standard-screen XXS metric makes `min 31` and `max 92`
39 pixels wide. The safe ring chord in those responsive families supplied
only 36 pixels per caption. The old layout created the labels anyway, causing
two-line wrapping, clipping, and visually fused text.

Resolution:

- min/max text now participates in a real width-fit decision;
- when the configured-range captions cannot fit, only the secondary text is
  removed;
- both retained history marks remain visible;
- 260×220 and larger layouts still show the captions when they genuinely fit;
- regression tests cover the fallback and the visible-caption geometry.

This implements the plan's information-priority rule: telemetry position and
history survive before secondary annotation.

### 2.2 Three older visual tools used obsolete font tables

`preview.lua`, `audit-preview.lua`, and `collide.lua` still carried copied,
approximate font sizes after the mock and gallery moved to measured EdgeTX
metrics. Those paths could approve a layout that the authoritative gallery
rejected.

Resolution:

- all three tools now reuse `svgkit.FONT_PX`;
- the preview, audit preview, collision audit, and gallery therefore measure
  the same standard-screen display;
- repository-wide Lua lint confirms the refactor is clean.

### 2.3 Forced two-decimal telemetry wrapped in a 60×60 micro dial

The legacy audit preview contained a valuable case absent from the canonical
gallery: `16.62` in a 60×60 dial. The normal six-pixel frame left only a
22-pixel inner chord for a 33-pixel XXS value.

Resolution:

- micro dials now give their square to the primary value instead of retaining
  normal-size exterior padding after every secondary layer has disappeared;
- the micro tick gap is one pixel and the tick stroke remains a readable two
  pixels;
- requested precision is preserved; the widget does not silently round away
  telemetry truth;
- containment passes at LCD scales 0.8, 1.0, and 1.375;
- `tx-prec2-micro` is now a permanent canonical scene and regression test.

## 3. Visual rebuild

Authoritative artifacts:

- [Stock complete gallery](docs/phase0/full-validation/gallery-stock.svg)
- [Dark complete gallery](docs/phase0/full-validation/gallery-dark.svg)
- [Stock bar baseline](docs/phase0/full-validation/gallery-stock-only-barra.svg)
- [Dark bar baseline](docs/phase0/full-validation/gallery-dark-only-barra.svg)
- [Machine-readable manifest](docs/phase0/full-validation/manifest.lua)
- [Stock individual-shot index](docs/phase0/full-validation/shots-stock/_index.txt)
- [Dark individual-shot index](docs/phase0/full-validation/shots-dark/_index.txt)
- [Firmware-semantic audit preview](docs/phase0/full-validation/audit-preview.html)

Fresh browser-rasterized PNGs were produced at the SVGs' exact dimensions:

| Artifact | Dimensions |
|---|---:|
| Complete stock gallery | 1292×7378 |
| Complete dark gallery | 1292×7378 |
| Stock bar sheet | 1292×1078 |
| Dark bar sheet | 1292×1078 |
| Official stock options collage | 1232×7890 |
| Official dark options collage | 1232×7890 |

Human inspection covered both complete overview sheets, both full-resolution
bar sheets, and the two repaired high-risk layouts in both themes. No text is
cut, no diagnostic marker remains, the micro decimal value is centered and
legible, and the min/max fallback removes clutter without removing history.

The current bar baseline is functionally sound and readable in both themes,
but its visual limitations remain obvious and correctly motivate the plan:

- it still reads as a generic rounded progress bar;
- Rail, Threshold, Sections, and Gradient are not yet distinct spatial faces;
- the 160×44 CRIT pill intentionally dominates because safety outranks
  decoration at that size;
- there are no production segment, hex, tick, gradient-slice, theme-adaptive,
  custom-palette, vertical, or motion systems yet.

Those are later-phase product requirements, not hidden Phase 0 failures.

## 4. Functional and safety gate

| Gate | Result |
|---|---|
| Pure unit suite | 38 passed, 0 failed |
| Lifecycle/smoke suite | 143 passed, 0 failed |
| Full gallery, stock + dark | 79 scenes, 0 failures, 0 warnings |
| Gallery option coverage | Complete |
| Manifest repeat comparison | No changes |
| Collision audit | All catalog zones/extremes/sweeps clean |
| Three-scale containment | Clean at 0.8, 1.0, and 1.375 |
| Zone atlas | Current; 17 layout sources |
| Phase 0 primitive probe | PASS |
| Lua lint | 0 warnings, 0 errors |
| Git whitespace check | Clean |
| Disposable SD deployment | 14 modules; stale bytecode removed |

## 5. Resource gate

### Objects

| Scene | Visible objects |
|---|---:|
| Default 300×70 bar | 9 |
| Worst audited current bar | 12 |
| Revised worst audited current dial | 33 |

The bar's conservative shared reserve remains 10 objects. The Phase 0 face
budgets remain valid: Continuous 14/24, Gradient 34/38, Blocks 26/38, Hex
40/40, Ticks 34/40, Steps 20/32, and Dual Rail 18/36.

### Runtime

| Measurement | Result |
|---|---:|
| Bar changing refresh | about 814 instructions/frame (4%) |
| Bar steady allocation | about 310 B/frame |
| Threshold-crossing allocation | about 643 B/frame |
| Advancing-history allocation | about 649 B/frame |
| Worst current callback | about 10,200 instructions; 49% headroom |

The instruction probe's conservative warning remains visible because the
worst dial rebuild is just inside two times the firmware limit. It is not a
failure, but later phases must continue to enforce the per-face object and
instruction ceilings instead of consuming that headroom casually.

## 6. Plan compliance

| Phase 0 contract | Evidence | Status |
|---|---|---|
| Useful / Beautiful / Customizable frozen | Plan and execution report | PASS |
| Classic severity remains default | Existing defaults and color tests | PASS |
| Semantic color separate from theme surfaces | Theme and contrast tests | PASS |
| Existing option wire contract unchanged | 24-slot frozen-order tests | PASS |
| Current visual baseline reproducible | 79-scene galleries and manifest | PASS |
| All HTX layout geometry understood | Source-derived 6,570-rectangle atlas | PASS |
| Risky primitives measured before architecture | Phase 0 probe and ceilings | PASS |
| Font/gallery/deployment evidence trustworthy | This intensive validation | PASS |
| No premature production redesign | No new face or appearance option | PASS |

## 7. Explicit non-closures

The following remain intentionally open under the approved roadmap:

- the descending-scale ghost/min/max asymmetry is reproduced and owned by
  Phase 2;
- Phase 1 still owns the appended settings, preset data, palette data, face
  contracts, and migration tests;
- Phase 2 still owns the flagship Classic Rail redesign;
- Phase 3 still owns production theme-adaptive and custom palette behavior;
- Phases 4–6 still own multiple faces, vertical/centered semantics, and motion;
- Phase 7 still owns the final cross-product and hardware/Companion gate.

## 8. Decision

**Phase 0 remains PASS after intensive validation.** The evidence is stronger
than the original narrow bar-only baseline, three concrete visual/harness
defects were fixed, and no later-phase requirement was falsely marked done.

