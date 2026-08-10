# Gauge Pro Bar v2 — Phase 6 report

**Completed:** 2026-08-10  
**Scope:** Retained motion profiles, bounded semantic colour transitions,
truthful data-loss fade, segment activation settle, refined critical pulse,
Expressive one-shot emphasis, responsive reduction, and temporal resource and
visual evidence.

## Outcome

Phase 6 adds motion without giving motion authority over telemetry truth.
Gauge Pro still answers the pilot's first questions immediately: the raw
number, availability, WARN/CRIT badge, threshold state and alerts all change in
the current refresh. Temporal behavior is a short presentation layer around
that truth.

The result follows the project's core:

- **Useful:** state is immediate, position never overshoots, dropout never
  invents a new value, and hidden widgets do not replay old animation.
- **Beautiful:** Refined uses a short exact-endpoint colour transition, calm
  critical breathing and precise segment/head feedback. The effects read as
  instrument behavior, not decoration.
- **Customizable:** Off, Essential, Refined and Expressive work with Classic,
  Theme Adaptive and exact custom palettes. The generated evidence uses a
  deliberately non-classic purple/yellow/cyan palette in stock, dark and
  high-contrast HTX themes.

## What shipped

### One retained motion state

- `motion.lua` owns one fixed scalar table per bar. It creates no LVGL object
  and stores no unbounded transition/cache history.
- `bar.lua` resolves the raw render state first, then asks motion for visual
  colour, visibility opacity, settle level and optional head emphasis.
- Position continues to use `smoothing.lua` and the existing **Gauge damping**
  slider. Motion adds no duplicate speed control.
- A source/range/profile/theme context edit lands on the newly authored
  endpoint and retains the existing UI tree.
- More than 500 ms without a visible refresh is treated as hidden time: the
  next frame lands at current truth instead of replaying elapsed effects.

### Four profiles

| Profile | Behavior |
|---|---|
| **Off** | No bar pulse, colour tween, fade, settle or expressive emphasis. Gauge damping remains active. |
| **Essential** | Immediate semantic state, 180 ms last-truth dropout fade, established two-state 1 Hz critical pulse. |
| **Refined** | Essential plus four fixed colour steps over 180 ms, Blocks/Steps exact-head settle, and a calm full/mid/trough/mid critical breath. |
| **Expressive** | Refined plus a 220 ms rearmable one-shot position-head emphasis after a material move. Micro and short families execute Refined. |

Critical entry always bypasses colour interpolation. The target at the end of
every transition is the exact resolved palette value, including user-authored
custom colours. Theme switches also land directly; colours from two active
themes are never blended together.

### Responsive and density caps

- Expressive automatically reduces to Refined in micro and short families.
  The saved choice is not rewritten.
- Blocks and Steps settle only at 12 segments or fewer in useful non-small
  families.
- True Hex and Fine Ticks keep their exact damped position head but omit the
  extra settle branch: repainting multipart/dense cells would add cost without
  improving the reading.
- Expressive emphasis is a one-shot. It cannot restart continuously on noisy
  or oscillating telemetry; a calm sample rearms the next meaningful move.

## Defect found by the hard gate

The first Expressive implementation restarted its head emphasis on every
material sample. A deliberately oscillating feed exposed two failures:

1. it could become permanent shimmer, violating the motion language; and
2. dense faces reached 2,277 instructions/frame and 192 B/frame in the test
   harness.

The effect was redesigned as a retained, rearmable one-shot. No acceptance
limit was relaxed. The same 48-case probe now measures 32–33 B/frame and all
ordinary temporal paths stay below the 2,000-instruction ceiling.

The global gate later caught true Hex at 2,000–2,002 instructions after the
new profile checks. The hot path was reduced to retained boolean/profile state
and reused colour-context decisions. Final independent measurements are
1,990–1,994 instructions/frame; the strict `<2,000` gate passes.

## Measured gates

| Gate | Phase 6 result |
|---|---:|
| Pure Lua tests | **70 / 70** |
| Lifecycle / firmware-contract tests | **200 / 200** |
| Motion resource matrix | **48 / 48 cases** |
| Matrix dimensions | **6 faces × 2 orientations × 4 profiles** |
| Temporal evidence | **105 production frames, 0 warnings** |
| Static catalogue | **222 scenes per theme, 0 failed** |
| Rendered static theme-scene combinations | **666** |
| Gallery warnings / uncovered visual options | **0 / 0** |
| Collision audit | **all cases clean** |
| Worst ordinary production face | **1,994 / 20,000 instructions** |
| Worst temporal/state transition | **5,400 / 20,000 instructions** |
| Worst structural callback | **9,200 / 20,000 instructions** |
| Absolute callback headroom | **54%** |
| Motion-matrix allocation | **32–33 B/frame** |
| Global ordinary allocation | **32–56 B/frame** |
| Object/table identity during motion | **fixed** |

`dev/instructions.lua` enforces `<2,000` ordinary, `<6,000` transition,
`<10,000` structural and `<20,000` absolute callback instructions using the
same 200-instruction hook period as release firmware.

`dev/motion_sequences.lua` independently runs stable, same-band movement,
warning, warning settle, critical, dropout, dropout midpoint, recovery and
hidden-resume callbacks for every face/orientation/profile combination. Its GC
is stopped and mock LVGL tracking is disabled while allocation is measured;
it also asserts retained motion/frame table identity, fixed scalar footprint,
fixed LVGL object count and raw-warning truth on hidden resume.

## Visual validation

The complete catalogue was rebuilt for all three theme fixtures and then
rasterized in headless system Chrome for image inspection. All 222 scenes in
each theme render with no warning and complete visual-option coverage. The
collision audit is clean.

The dedicated filmstrip uses the same production `main.lua`, mock firmware and
`svgkit.lua` object-tree renderer as the gallery. It captures 35 ordered frames
per theme for:

- Refined custom-colour WARN transition;
- Expressive one-shot head behavior;
- Blocks segment settle;
- Essential dropout fade;
- immediate CRIT plus the four-phase breath;
- vertical Steps motion; and
- micro Expressive → Refined reduction.

Browser review found and corrected two evidence-generator defects: narrow
vertical/micro captions overlapped, and the pulse row originally reported
semantic opacity rather than the actual LVGL pulse target. The final sheet is
readable and explicitly records `255 → 203 → 150 → 203 → 255`.

## Evidence

- `docs/phase6/motion/motion-filmstrip-stock.svg` / `.png`
- `docs/phase6/motion/motion-filmstrip-dark.svg` / `.png`
- `docs/phase6/motion/motion-filmstrip-highcontrast.svg` / `.png`
- `docs/phase6/motion/motion-filmstrip-manifest.txt`
- `docs/phase6/full-validation/gallery-stock.svg` / `.png`
- `docs/phase6/full-validation/gallery-dark.svg` / `.png`
- `docs/phase6/full-validation/gallery-highcontrast.svg` / `.png`
- `docs/phase6/full-validation/manifest.lua`

Every image is generated from the widget's actual retained object tree. The
filmstrips are `1460×1489`; the complete galleries are `1292×16056`.

## Next phase

Phase 7 remains the release-completion audit: hardware and Companion checks,
multi-instance/theme-switch endurance, full flight-readability review and the
final P0/P1 defect gate. Phase 6's implementation and automated/visual evidence
are complete; hardware claims are intentionally not inferred from the
headless harness.
