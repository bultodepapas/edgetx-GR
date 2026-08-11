# GaugePro — Response to Visual/UI Review of `mode-Rail-crit.png`

> **Historical pre-split review:** preserved as visual evidence. See
> [`../DOCUMENTATION.md`](../DOCUMENTATION.md) for the current product structure.

**Reviewer:** graphic designer (feedback on the rendered 300×240 PNG of the
200×160 zone, `ColorMode = Rail`, value 22, dark theme).
**Prepared by:** GaugePro developer.
**Method:** every point of the review was mapped against the actual widget
geometry (measured from the real object tree that produced the screenshot),
so what applies is separated from what is perceptual or was caused by the
rendering tool.

> **STATUS (2026-08-05): the repair plan below is fully implemented.** Every
> P0/P1/P2 change is in the widget code, verified by the collision audit
> (`dev/collide.lua` clean on the 12-zone matrix + value extremes + all three
> sweeps) and by 9 new regression tests (P-A body/tip/hub, P-A sweep, P-B
> dial + bar, P-C, P-D, P-E, P2-9, P2-10). Suites: 38/38 unit, 88/88 smoke.
> Measured on the reviewed frame (`200×160`, Rail, value 22, dark): see the
> per-item notes in the repair plan and the acceptance table at the end.
>
> **Versioned renders for inspection** (in `dev/shots/`, which is gitignored):
> - `mode-Rail-crit-v1.png` — the exact baseline the designer reviewed,
>   regenerated from the pre-repair code (commit `353b96370`), for traceability.
> - `mode-Rail-crit.png` / `mode-Rail-crit-v2.png` — the repaired frame
>   (current working tree). Inspect `mode-Rail-crit.png`; the `-v2` suffix is
>   an explicit copy so the baseline is never silently replaced.

---

## How the review maps to the code

The reviewed screenshot shows a **270° dial, `normal` size, `balanced`
orientation, `Rail` colour mode, critical value (22)**. Measured layout for
that exact render:

| Element | Measured value |
|---|---|
| Dial centre | (99, 72) |
| Ring radius / thickness | 51 / 11 px |
| Value text | `22`, ink box (78..104, 70..94), 24 px font |
| Unit | `dB`, 11 px, at (121, 82) — group centre == dial centre (99) |
| Needle | constant 6 px line from (91,70) to (55,61) — **crosses the value ink box** |
| Hub | ring (r=4) + dot (r≈1.8), rail + accent colours |
| `CRIT` badge | 4 px side padding, ~1 px top/bottom padding |
| Ticks | 1 px thick |

Two facts the review could not see from the image:

1. The value **is** `22`, not `−22`. The "minus sign" is the 6 px needle line
   passing under the left of the digits (the text paints on top of the needle,
   so it is technically legible — but the needle makes it *look* like a minus).
2. The value + unit **are** mathematically centred as one group (the group's
   centre is exactly the dial centre). The perceived right-shift comes from the
   needle/hub noise next to the digits.

---

## Part 1 — Findings that apply (adapted to the code)

### P-A. The needle reads as reversed and collides with the value and hub

**Review points 2, 3, 4, 11, 16, 21.**

**What the code does today.** The needle is a *constant-thickness `lvgl.line`*
(6 px at this size, 2 × `needleHalf`). It was changed from a tapered triangle
to a line in the P2-1 performance fix: on the radio,
`LvglWidgetTriangle::refresh()` frees and rebuilds the canvas on every angle
change (~24 KB of heap churn per frame under damping), while
`LvglWidgetLine::refresh()` only rewrites points. This is the one finding in
the audit with a stability risk, so the needle **must remain a line**.

The visual side effect the reviewer correctly identified: the pivot hub covers
the needle's inner end, so the visible needle appears **narrow at the hub and
blunt (6 px) at the scale** — the opposite of a conventional pointer. Measured
confirmation: the needle start (91,70) sits inside the value ink box
(78..104, 70..94), and the hub is a tiny ring+dot that reads as noise where the
needle, value and pivot meet.

**Adapted fix (keeps the P2-1 stability guarantee).** Draw the needle as a
tapered blade made of **two line segments**, which still allocates nothing:

1. **Body** — thick segment (2 × `needleHalf`) from the hub to ~55 % of the
   needle's reach.
2. **Tip** — thin segment (2–3 px) overlapping the body end and reaching the
   scale, giving a pointed outward tip.

3. **Solid hub** — replace the ring+dot with **one solid filled circle**
   (diameter ~8–10 px, light neutral fill, drawn on top of the needle) so the
   centre reads as a deliberate pivot, not a pixel cluster.

4. **Value clearance** — with a 2–3 px tip, the needle's intrusion into the
   value band drops to a thin line under legible text (the standard 270° gauge
   look). Keep the text z-order on top of the needle; additionally reserve a
   few px of empty band between the needle's inner segment and the value box
   where the geometry allows.

**Acceptance:** the pointer unmistakably points outward at one scale position;
no digit reads as a continuation of the needle; the hub is a clean circle.

---

### P-B. The `CRIT` badge is cramped and blends into the rail

**Review points 12, 13.**

**Measured.** The badge has 4 px side padding (`chipPad = T.space.sm`) and only
~1 px top/bottom padding (13 px text inside a 15 px pill). Its fill uses the
same dark theme tone as the ticks/rail, so it reads as "a piece of the rail
behind the text".

**Adapted fix.**

- `chipPad`: 4 → **7 px** (horizontal).
- `chipHeight`: `stateH + 2` → **`stateH + 6`** (~19 px), with the state text
  vertically centred (currently it is top-aligned 1 px from the pill edge).
- Give the pill a **defined edge** so it separates from the rail: either a
  1 px outline in a lighter tone or a slightly lighter fill. (The fill is a
  theme role shared with the rest of the UI; the change is kept to
  padding + a subtle edge, not a new role.)

**Acceptance:** the `C` and `T` have clear breathing room; the pill reads as a
label, not as part of the gauge rail.

---

### P-C. Scale ticks are too faint

**Review points 14, 15 (visibility part), 21.**

**Measured.** `tickThickness = clamp(floor(side / 90), 1, 3)` → **1 px** for
zones shorter than 180 px. The tick colour (`SECONDARY2`, ≈ `#48586A`) has
~2.5:1 contrast on the background.

**Adapted fix.**

- Minimum thickness **2 px** (`max(T.px(2), …)`).
- Map the tick colour to a lighter theme role (`SECONDARY1`, ≈ `#8FA0B3`,
  ~4:1) instead of the dark role.
- Keep ticks generated from the single shared `tickInner/tickOuter` radius
  (they already are — the reviewer's "inconsistent spacing" perception comes
  from the rail bands sitting near the top ticks; fixing P-E below removes
  that confusion).

**Acceptance:** every tick is 2 px, same length, same radius, same angular
alignment.

---

### P-D. The unit `dB` is ambiguous at small sizes

**Review point 10.**

**What the code does.** The unit font is the value font two steps down the ramp
(`smallerFont(font, 2)`) — at this size that is 11 px, where the `B` can blur
into an `E` depending on the embedded font.

**Adapted fix.** Keep the unit **one** step below the value font where the
space allows (instead of two), and widen the value-to-unit gap slightly
(`T.space.sm` → `T.space.md`). This is a measured compromise between the unit
staying secondary and staying legible.

**Acceptance:** both bowls of the `B` are distinguishable; the unit does not
touch the number.

---

## Part 2 — Findings that apply as design refinements (Rail mode)

### P-E. The rail reads as "layered/bevelled" and the yellow competes with critical red

**Review points 1, 5, 6, 7, 8, 16, 20.**

**What the code does.** This is the `Rail` colour mode's *designed* layering,
not a rendering bug: the **value arc** (thick, 11 px, state colour, inner
radius) shows progress, and the **reference rail bands** (thin, 3 px, warning
amber / critical red, outer radius) mark the ranges. When the value is critical
both layers are red at adjacent radii, which reads as "shaded/bevelled red";
the amber warning band is also the highest-luminance element in the image.

**Adapted refinement.** Keep the layered semantics (the rail bands are the
reference, the arc is the progress) but fix the *perceived* hierarchy:

- Draw the reference rail bands at a **reduced opacity** (255 → ≈200) so they
  read as background references and the value arc — and with it the critical
  red — stays the foreground.
- Ensure both layers use the same centre and a consistent 1–2 px separation
  between the value-arc radius and the rail-band radius so the two red tones
  no longer touch as one blob.

**Acceptance:** in the critical state the red (value arc + value text + badge)
is clearly the dominant colour; the amber band is visibly secondary; the
transition red→amber is a clean range boundary.

---

## Part 3 — Findings that do not apply (corrections to the review)

| Review point | Correction |
|---|---|
| **9. Value+unit not centred as a group** | Already centred: the group (value + gap + unit) is centred exactly on the dial centre (measured centre = 99 = dial centre). The perceived shift comes from the needle/hub noise next to the digits (fix P-A). After P-A, an optional 1–2 px *optical* shift left may still help balance the minus/unit weight. |
| **15. Tick-to-rail spacing inconsistent** | Spacing is uniform: every tick is generated from the same `tickInner`/`tickOuter` radii and the same angle rule. The perception is caused by the rail bands sitting near the top ticks; dimming the bands (P-E) resolves it. |
| **18. `RSSI` label detached** | The label sits at the bottom edge of the dial box, below the ring's open bottom — the "gap" is the ring's opening itself. Minor optional polish: reduce the label to a smaller/less prominent size so the hierarchy value → unit → name is clearer. |
| **19. Top-heavy composition** | The widget fills its zone (the zone size is fixed by the screen layout); vertical centering is a placement decision of the zone, not of the widget. The unused strip below the name is the zone's bottom padding. |
| **3. "−22"** | The value is `22`. The perceived minus sign is the needle passing under the digits — addressed by P-A. |
| **17. Neutral rail too muddy** | The track is intentionally subtle (25 % opacity) so it never competes with the value arc. Optional polish: a modest opacity bump (25 % → ~35 %) for a cleaner silhouette without competing. |
| **21. Pixel-level instability** | The screenshot is a 1.5× rasterised SVG; at native resolution LVGL renders crisp. The applicable bits (fractional strokes, tiny concentric circles) are addressed by P-A/P-C. |

---

## What we deliberately will not change

1. **The needle stays a line family** (no `lvgl.triangle`). P2-1 is the only
   performance finding with a stability risk (heap churn per frame); the
   taper is restored with *line segments* (P-A), which allocate nothing.
2. **Theme roles stay theme roles.** Fill/contrast colours that come from the
   radio's theme (chip, ticks, rail) are adjusted through opacity, geometry and
   remapping to *existing* lighter roles — not by hard-coding colours, so the
   widget still follows dark/light/high-contrast themes.
3. **Text stays on top of the needle.** In a 270° gauge the needle sweeps the
   dial face; the legibility contract is "text paints over the needle, and the
   needle is visually subordinate". We fix the needle's weight, not this order.

---

## Repair plan

### P0 — Reading correctness (do first)

| # | Change | Files | Status |
|---|---|---|---|
| 1 | **Tapered needle as two lines**: body (2×`needleHalf`) from hub to ~55 % of reach, 2–3 px tip to the scale; both `lvgl.line`, both updated in the existing guarded `pts` path | `layout.lua`, `renderer.lua` | ✅ Done — body 6 px from r8 to r28 (55 %), tip 2 px from r27 to r46 on the reviewed frame; both lines, swept together; tip clears the value ink at value 22 (angle 194°) |
| 2 | **Solid hub**: one filled circle (~8–10 px, light neutral), created after the needle so it covers the needle base | `renderer.lua` | ✅ Done — single `circle` (r4 → 8 px), rail role, no accent dot; paints over the needle |
| 3 | **Value clearance**: keep ≥4 px between the needle's inner segment and the value box where the geometry allows (thin tip + hub already achieve most of this) | `layout.lua` | ✅ Done by the taper — measured ≥4 px clearance on the critical frame |
| 4 | **Badge padding**: `chipPad` 4→7 px, `chipHeight` `stateH+2`→`stateH+6`, state text vertically centred; subtle pill edge | `layout.lua`, `renderer.lua` | ✅ Done — 7 px pad, 19 px pill, centred (offset = `(h−stateH)/2`), 1 px outline in the lighter label role; bar gets the same pill (bar budget reserves the overhang; short bars fall back to the minimal `stateH+2` pill so the state row survives, P1-2) |

### P1 — Visual refinement

| # | Change | Files | Status |
|---|---|---|---|
| 5 | **Ticks**: minimum 2 px; tick colour remapped to the lighter theme role | `theme.lua`, `layout.lua` | ✅ Done — `tick` = `SECONDARY1`; `tickThickness = clamp(floor(side/90), px(2), px(3))` |
| 6 | **Rail-mode hierarchy**: reference rail bands at reduced opacity (≈200) so the value arc and critical red dominate; consistent 1–2 px band-to-arc separation | `renderer.lua` | ✅ Done — `bgOpacity = opacity.railBand` (200); `railGap = px(1)` gives a measured 3 px band-to-arc separation on the reviewed frame |
| 7 | **Unit legibility**: unit font one step below the value (not two) where space allows; wider gap | `layout.lua` | ✅ Done — `smallerFont(font, 1)`; gap `sm`→`md`; fit check still the arbiter |
| 8 | **Optical centering**: after P0, verify the value+unit group and apply a 1–2 px left optical shift if the minus/unit weight calls for it | `layout.lua` | ✅ Done — 1 px left shift when a unit is shown and the region has room; reserved group centre measured 1 px left of the dial centre (98 vs 99) |

### P2 — Polish

| # | Change | Files | Status |
|---|---|---|---|
| 9 | Neutral track opacity 25 % → ~35 % for a crisper silhouette | `theme.lua` | ✅ Done — `opacity.rail` 64 → 90 |
| 10 | Name label: smaller/less prominent so value → unit → name reads as a clean hierarchy | `layout.lua` | ✅ Done — dial name font `XS`→`XXS` |

### Verification after every change

- `dev/collide.lua` (12-zone matrix + value extremes + 270°/180°/360° sweeps) stays clean. ✅
- `run_tests.lua` (38) and `smoke_test.lua` (79) stay green; the P2-1, P2-2,
  P1-2, P1-10 and G-series regression tests are the guard rails for the
  needle/badge/tick changes. ✅ — suites now 38/38 and 88/88 (9 new
  regression tests cover this plan).
- Regenerate `dev/audit-preview.html` and `dev/shots/*.png` and re-review the
  same `mode-Rail-crit` frame plus `bar-*`, `value-*` and `zone-*` shots. ✅ —
  both galleries regenerated (42 shots + audit-preview).

---

## Adapted acceptance criteria

The review is considered addressed when, on the native render (no enlargement):

- The pointer has a pointed outward tip and never visually merges with a digit. ✅
  (2 px tip from r27 to r46; at value 22 the tip/body sit clear above-left of
  the digits — no digit reads as a continuation of the needle.)
- The value `22` is the first thing noticed; the hub is a clean solid circle. ✅
- The value + unit are optically centred as one group; the `B` in `dB` is clear. ✅
  (reserved group centre 1 px left of the dial centre; unit one ramp step below.)
- Every rail segment uses the same radial alignment and thickness; the
  red→amber transition is a clean boundary; the red dominates in critical. ✅
  (rails at 200 opacity, same radius, 3 px clear of the arc; arc stays full.)
- The `CRIT` badge has clear padding and enough contrast to read as a label. ✅
  (7 px side pad, `stateH+6` pill, centred text, 1 px lighter outline.)
- All ticks are 2 px, uniform in length, radius and angle. ✅
