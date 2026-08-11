# Gauge Pro v2 Bar — Phase 1 Personalization Architecture Report

> **Histórico:** evidencia pre-split de Bar, hoy `GaugeBarPro`/`BarPro`. Consulte
> [`DOCUMENTATION.md`](DOCUMENTATION.md) para la arquitectura vigente.

**Status:** PASS — Phase 1 complete  
**Date:** 2026-08-09  
**Branch:** `feat/gauge-v2`  
**Scope:** bar personalization contracts; the approved dial is pinned

## Outcome

Gauge Pro now has a real personalization architecture rather than a collection
of renderer switches:

- 15 append-only settings occupy slots 25–39 on EdgeTX 2.12+;
- appearance presets resolve as immutable data bundles;
- explicit overrides win without changing stored options;
- Auto Source uses a coarse sensor-semantic hint only for appearance;
- Classic, Theme Adaptive, Custom Three and Custom Two palettes are functional
  on the current Continuous bar;
- semantic severity, HTX surfaces and HTX data ink remain separate layers;
- custom severity anchors are preserved exactly;
- custom track color is live; the custom panel color is stored/resolved for
  its Phase 3 surface layer;
- palette and badge caches are theme-aware, quantized and bounded;
- every planned face has the same retained-mode interface and a hard object
  ceiling;
- shared normalized render state contains no alert ownership;
- the dial does not resolve or consume bar palettes and remains visually exact.

This phase establishes the foundation. It does not pretend that later visual
faces already exist. Blocks, Hex, Ticks, Steps, Dual Rail, vertical direction,
zero origin and new thickness/end geometry resolve deterministically, are
represented in structural signatures, and report an explicit production
fallback to the existing Continuous face until their scheduled phases.

## Configuration contract

The original 24 positional slots remain unchanged. A second frozen ratchet now
protects this exact tail:

| Slots | Settings | Availability |
|---|---|---|
| 25–33 | preset, face, direction, origin, thickness, ends, count, gap, palette | 2.12+ |
| 34–36 | warning, critical and track colors | 2.12+ |
| 37–39 | surface, panel color and contrast assistance | 2.12+ |

Every key is at most 10 characters, every translated label is at most 20
characters, CHOICE values remain 1-based, and stored zero still means “use the
declared default.” EdgeTX 2.11 still receives exactly the original ten slots.

The slot-16 label remains `Needle damping` in this phase. Although the long-term
change map proposes `Gauge damping`, the Phase 1 gate explicitly requires
slots 1–24 to remain unchanged; the label rename is deferred rather than mixed
into the contract milestone.

## Preset and Auto resolution

`bar_style.lua` owns nine appearance presets as read-only data:

| Preset | Full form | Compact contract |
|---|---|---|
| Auto Source | semantic face, Classic, responsive | source face with reduced detail |
| Classic Rail | Continuous, Classic, medium round | continuous medium rail |
| Theme Clean | Continuous, Theme Adaptive, thin | thin line without panel |
| Hex Telemetry | Hex, Classic, 8 cells | six chamfered cells |
| Status Blocks | Blocks, Classic, 10 cells | six square blocks |
| Signal Ticks | Ticks, Theme Adaptive, 24 ticks | ten high-contrast ticks |
| RC Center | Dual Rail, zero origin, Custom Two | zero-notch dual rail |
| Minimal Line | Continuous, Theme Adaptive, thin | minimal theme line |
| Bold Data | Continuous, Classic, thick | medium external-value fallback |

Resolution order is:

`explicit override > preset > source-aware default > responsive default > safe fallback`

Auto Source reads only `presets.kind(source)`. That hint cannot alter ranges,
thresholds, battery transforms, hysteresis or alerts. Hex is capped at ten
cells even in large zones because ten true hexes plus shared layers reaches its
40-object ceiling; compact zones can reduce it to six.

## Palette engine

The current Continuous bar consumes the resolved palette immediately:

- **Classic:** existing Normal color, calibrated amber and red;
- **Theme Adaptive:** HTX ACTIVE and WARNING roles, fixed critical fallback;
- **Custom Three:** exact Normal, Warning and Critical picker values;
- **Custom Two:** exact Normal/Critical endpoints plus a gamma-aware generated
  midpoint.

Track and panel roles remain theme-derived unless Surface is Custom colors.
Data value/name/unit ink always remains theme-owned. Static Colour mode still
uses the existing Normal color by definition; palette selection and Colour mode
remain independent axes.

Palette signatures include resolved RGB values for all severity anchors,
track/panel/border/history/muted roles, value/label roles and both badge-ink
roles. A live theme role change therefore invalidates color decisions even
though the numeric `COLOR_THEME_*` flags did not change.

Contrast ratio and RGB distance are analysis signals only. If a theme or user
chooses close colors, the authored colors remain exact; later contrast-assist
layers add redundant structure instead of manufacturing replacement hues.

Interpolation is quantized to at most 25 entries per signature and retains at
most 12 signatures. Badge ink retains at most 32 signature/fill decisions.
Continuously changing live values cannot grow either cache.

## Face boundary

`bar_faces.lua` defines the required interface for Continuous, Blocks, Hex,
Ticks, Steps and Dual Rail:

- `supports(profile, config)`
- `estimateObjects(profile, config)`
- `build(widget, geometry, style)`
- `update(widget, objects, renderState)`
- `applyPalette(widget, objects, palette)`
- `setVisible(objects, visible)`

Only Continuous is production-drawn in Phase 1. Its track/fill body moved
behind this interface without changing creation order. `bar.lua` continues to
own thresholds, history, value/unit/name, badges, stale state and pulse.
`alerts.lua` remains the only alert authority.

The per-widget face render state is allocated once at build and updated in
place. It contains availability, semantic state, raw/smoothed normalized
positions, threshold positions, history positions, current color key and
opacity. No face creates objects or tables during ordinary refresh.

## Automated evidence

| Gate | Result |
|---|---:|
| Pure unit tests | **53 passed, 0 failed** |
| Lifecycle/smoke tests | **151 passed, 0 failed** |
| Full stock/dark gallery | **88 scenes, 0 failed** |
| Render warnings | **0** |
| Visual-option coverage gaps | **0** |
| Pre-existing stock SVGs | **85/85 byte-identical** |
| Pre-existing dark SVGs | **85/85 byte-identical** |
| New personalization scenes | **9** |
| Collision audit | **all clean** |
| Source-derived zone atlas | **current, 17 layouts** |

The 85 SVG files include historical aliases for the 79 Phase 0 catalogue
scenes. The only added files in either theme are the nine `pal-*` scenes. No
existing file changed by one byte.

The complete generated evidence is under:

- `docs/phase1/full-validation/gallery-stock.svg`
- `docs/phase1/full-validation/gallery-dark.svg`
- `docs/phase1/full-validation/gallery-stock.png`
- `docs/phase1/full-validation/gallery-dark.png`
- `docs/phase1/full-validation/manifest.lua`
- `docs/phase1/full-validation/shots-stock/`
- `docs/phase1/full-validation/shots-dark/`
- `docs/phase1/collage/`

The official `docs/gauge-pro-options*` SVG/PNG sheets were regenerated and now
contain all 88 scenes. Both complete light and dark raster sheets were visually
inspected after generation. Classic remains familiar; Theme Adaptive visibly
follows HTX; purple/yellow/cyan custom combinations remain exact and keep
theme-owned typography.

## Runtime evidence

| Probe | Result | Phase 1 gate |
|---|---:|---:|
| Default bar stable changing frame | **954 instructions (5%)** | < 1,200 |
| Default bar steady allocation | **309 B/frame** | no regression from harness/runtime plateau |
| Bar structural update/build | **6,600 instructions** | < 10,000 |
| Default bar visible objects | **9** | unchanged |
| Rich current bar visible objects | **12** | < 24 Continuous ceiling |
| Worst audited callback | **10,600 instructions** | < 20,000 |
| Worst callback headroom | **47%** | safe |

The dial skips bar palette analysis during configure, avoiding a measurable
bar-only tax on the approved renderer path.

## Exit gate

- [x] Slots 25–39 appended behind the 2.12+ guard.
- [x] Original slots 1–24 and new tail frozen independently.
- [x] Presets are data and overrides do not mutate stored values.
- [x] Auto Source is stable and appearance-only.
- [x] All four palettes resolve at runtime.
- [x] Exact custom anchors are preserved.
- [x] Theme inks participate in every palette/ink cache signature.
- [x] Color caches are bounded.
- [x] Contrast and color distance are measured.
- [x] Face interface and object ceilings are test-pinned.
- [x] Alerts remain centralized.
- [x] Default bar and all dial visuals are unchanged.

**Phase 1 exit gate: PASS.**

## Next phase

Phase 2 is the flagship Continuous bar: first fix independent min/max history
markers on descending scales, then add the polished body, head, permanent
Rail/Sections meaning, real spatial gradient slices, responsive thickness/end
geometry and the first complete motion language—while keeping the Phase 1
personalization contracts stable.
