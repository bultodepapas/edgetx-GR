# GaugeV2 — Tanda 7 design plan: three changes

**Author role:** senior developer, final production review pass.
**Baseline:** `feat/gauge-v2`, working tree after the Tanda 7 robustness fixes
(38 unit + 128 lifecycle + 18 collision zones + 77 gallery scenes green,
luacheck 0/33).
**Status:** **PROPOSED — awaiting owner decision.** Nothing in this document is
implemented. §8 lists exactly what needs a yes/no.
**Date:** 8 August 2026.

---

## 0. Summary

Three changes, ranked by what they do for the instrument. Every number below
was measured on the real object tree, not estimated — §1 gives the method.

| # | Change | Kind | Evidence | Risk |
|---|---|---|---|---|
| **A** | Let the needle pass **behind** the state chip instead of being truncated | **defect** | needle keeps **13 %** of its blade at value 50; 25–35 % of the scale affected | reverses Tanda 5 P0-4 |
| **B** | Value typography + vertical rhythm of the dial's text block | design, **already requested** | Tanda 5 **P1-5 still 🟡**; every gap in the block is 2 px regardless of slack | touches P0-2's test |
| **C** | Tall / narrow zone composition | design | 100×260 wastes **142 of 260 px** and shows no source name | contained |

**A is not a taste call.** It is a functional regression in the primary
indicator, active precisely in the abnormal states the chip announces. I would
ship A alone if only one were allowed.

**A and B are one piece of work.** A's finding — that labels and the chip are
created *after* the needle and therefore already paint over it — is exactly
what unblocks B's open question about `valueDrop`. Doing B without A means
re-deriving the same fact. C is independent and can land in any order.

---

## 1. Method

Every measurement is reproducible from the widget directory:

```sh
lua5.3 tests/run_tests.lua  ./     # 38  pure modules
lua5.3 tests/smoke_test.lua ./     # 128 lifecycle
lua5.3 dev/collide.lua      ./     # 18  geometric collision zones
lua5.3 dev/gallery.lua      ./     # 77  scenes, both palettes
luacheck .
```

The figures in §2–§4 come from driving the real widget through
`create → update → refresh` against `tests/mock_env.lua` and reading the
resulting `widget.layout` / `widget.ui` / `widget.frame`, then measuring the
geometry directly. The mock enforces the firmware's contract (per-object
property allow-lists, `{x, y}` point arrays, `luaL_checkunsigned` on line
coordinates, the 1-based integer option wire format), so a number taken here
is a number the radio would produce.

**Not verified on hardware.** Everything below is source- and harness-level.
A bench run on a real radio is still owed before release, and is the only way
to confirm the draw-order assumption in §2 on the actual LVGL build.

---

## 2. Change A — the needle must not be amputated by the state chip

### A.1 Evidence

Zone 200×160, `Sweep = 270`, chip on. Full blade =
`L.needleOuter - L.needleInner` = 38 px.

| value | chip | blade drawn | kept |
|---|---|---|---|
| 0–20 | CRIT | 38.0 px | 100 % |
| 30 | CRIT | 15.5 px | 41 % |
| 34 | CRIT | 10.5 px | 28 % |
| 40 | WARN | 6.8 px | 18 % |
| **50** | **WARN** | **5.0 px** | **13 %** |
| 60–100 | — | 38.0 px | 100 % |

With `ShowChip = false` the same values render **38 of 38 px, 100 %**. The
truncation is caused entirely by the chip.

Share of the scale affected (51 sampled values, chip shown):

| sweep | truncated |
|---|---|
| 270° | 13 / 51 (25 %) |
| 180° | 18 / 51 (35 %) |
| 360° | 8 / 51 (16 %) |

Visible in the shipped renders: `dev/shots/mode-Rail-pos2.png` (value 50,
WARN) shows a pivot dot and a stub — no blade. `dev/shots/op-chip-off.png` is
the same gauge with the chip off and a full tapered needle.

Two things make this worse than the percentages suggest:

1. The chip only appears in **WARN / CRIT / STALE / NO LINK / NO DATA** — the
   states where the pilot actually looks at the gauge. In the normal state the
   needle is perfect and the fault is invisible.
2. The needle **changes length as it sweeps**. No real instrument does that.
   It reads as a rendering fault, not as a design.

### A.2 Root cause

`renderer.needleReach()` (Tanda 5 review 3.12 / P0-4) shortens the blade to
`rayBoxEntry(...) - px(2)` whenever the current angle's ray would enter
`frame.chipBox`. Its stated purpose is to avoid "drawing the needle through
solid UI".

**That purpose is already served by the paint order.** Measured creation
indices on a built 200×160 dial:

| object | index |
|---|---|
| `needle` / `needleMid` / `needleTip` | 11 / 12 / 13 |
| `chipEdge` / `chip` / `stateLabel` | 20 / 21 / 22 |

`chip.filled = 1`, `chip.opacity = nil` → 255, fully opaque. LVGL paints
children in creation order, so the chip is painted **over** the needle
already. The truncation removes a blade that would have been invisible anyway
— and, because it stops `px(2)` *short* of the pill, it also removes the
2 px that were never covered, producing the visible gap.

This is not a new assumption. The widget already relies on creation order for
the "text paints over geometry" contract (Tanda 5 review 3.1): the value and
name labels are created after the arcs for exactly this reason.

### A.3 Options

| # | Option | Blade length | Code | Verdict |
|---|---|---|---|---|
| **A0** | Status quo | 13–100 %, angle dependent | — | rejected: the defect |
| **A1** | Delete `needleReach`, rely on occlusion | constant 100 % | **−1 function, −1 frame gate** | core of the recommendation |
| **A2** | A1 **+ pin the draw order with a test** | constant 100 % | A1 + 1 test | **recommended** |
| A3 | Truncate only the tip segment | 60–100 % | same complexity | half a fix; still varies |
| A4 | Move the chip out of the needle's path | constant 100 % | large layout change | breaks a settled layout for no gain over A2 |
| A5 | Make the chip translucent, needle shows through | constant 100 % | trivial | **rejected**: costs chip legibility, which is the point of the chip |
| A6 | Shorten the needle globally so it never reaches the chip band | constant, but short at *every* angle | trivial | rejected: pays at 100 % of angles to fix 25 % |

A2 is A1 plus the one thing that makes A1 safe: an explicit, named test that
fails the day the assumption stops holding.

### A.4 Recommended implementation (A2)

**`renderer.lua`**

```lua
-- DELETE needleReach() entirely.

local function updateArc(widget)
  ...
  local a = angleOf(widget, sv)
  if a ~= frame.angle then                       -- (1)
    frame.angle = a
    setProp(widget, ui.valueArc, "endAngle", a)
    if ui.needle then
      -- Full, constant reach at every angle. The state chip is created
      -- AFTER the needle (renderer.build) and is filled/opaque, so LVGL
      -- paints it over the blade: the needle passes BEHIND the badge, the
      -- way a pointer passes behind a label on a real instrument. This is
      -- the same creation-order contract the value/name labels already use
      -- to paint over the arcs (Tanda 5 review 3.1).
      G.linePointsInto(ui.needlePts,    L.cx, L.cy, L.needleInner,   L.needleBodyOuter, a)
      lvgl.set(ui.needle,    ui.needleSet)
      G.linePointsInto(ui.needleMidPts, L.cx, L.cy, L.needleMidInner, L.needleMidOuter, a)
      lvgl.set(ui.needleMid, ui.needleMidSet)
      G.linePointsInto(ui.needleTipPts, L.cx, L.cy, L.needleTipInner, L.needleOuter,    a)
      lvgl.set(ui.needleTip, ui.needleTipSet)
    end
  end
```

`(1)` — the `or frame.chipShown ~= frame.needleClampChip` term goes away with
`needleReach`. That gate existed only to re-cut the blade when the chip
appeared or vanished; with a constant blade there is nothing to re-cut. **This
removes per-frame work**, it does not add any.

Also removed as now-dead:

- `frame.needleClampChip` (build-time init in `renderer.build`)
- `frame.chipBox` and the block in `M.updateChip` that maintains it
- `geometry.rayBoxEntry()` — its only caller was `needleReach`

> **Variant A2-lite:** keep `geometry.rayBoxEntry()` and its unit tests. It is
> a correct, tested, pure function and someone may want the slab method again.
> Cost: ~20 lines of dead code. My preference is to delete it — `git` is the
> archive — but this is a coin-flip and the owner may reasonably differ.

**Test changes — `tests/smoke_test.lua`**

The existing P0-4 test asserts the needle stops short of the pill. It must be
*replaced*, deliberately and by name, not deleted:

```lua
test("A: the needle keeps its full length behind the state chip", function()
  -- REPLACES the Tanda 5 P0-4 test, which asserted the opposite. P0-4
  -- truncated the blade to avoid drawing through the pill; the pill is
  -- opaque and painted after the needle, so it already occludes it -
  -- truncation only cost a needle that changed length as it swept
  -- (measured: 13 % of the blade at value 50, 25-35 % of the scale).
  local w = newWidget(nil, { Source = ID_RSSI })
  local L = w.layout
  local full = L.needleOuter - L.needleInner
  for _, v in ipairs({ 0, 20, 30, 34, 40, 50, 60, 80, 100 }) do
    mock.setValue(ID_RSSI, v)
    refresh(w, 6)
    local a, b = w.ui.needlePts[1], w.ui.needleTipPts[2]
    local drawn = math.sqrt((b[1]-a[1])^2 + (b[2]-a[2])^2)
    assertTrue(math.abs(drawn - full) <= 1,
      string.format("value %d: blade %.1f, expected %d", v, drawn, full))
  end
end)

test("A: the chip occludes the needle by paint order", function()
  -- The guarantee the test above depends on. If EdgeTX ever changes child
  -- paint order, or the chip stops being opaque, THIS fails first and says
  -- why - instead of the needle silently drawing through the badge.
  local w = newWidget(nil, { Source = ID_RSSI })
  mock.setValue(ID_RSSI, 10)
  refresh(w, 3)
  assertTrue(objIndex(w.ui.chip) > objIndex(w.ui.needleTip),
    "the chip must be created after the needle (later = painted on top)")
  assertEq(w.ui.chip.props.filled, 1, "and be filled")
  assertTrue(w.ui.chip.props.opacity == nil or w.ui.chip.props.opacity == 255,
    "and be fully opaque, or it does not occlude")
end)
```

### A.5 Files, risk, acceptance

| | |
|---|---|
| **Files** | `renderer.lua` (−~25 lines), `geometry.lua` (−`rayBoxEntry`), `tests/smoke_test.lua` (1 test replaced, 1 added), `run_tests.lua` (drop `rayBoxEntry` units if deleted) |
| **Perf** | net **negative** cost: one fewer frame gate, one fewer `rayBoxEntry` per angle change |
| **Renders changed** | `mode-Rail-pos2`, `mode-Rail-crit`, `st-warn`, `st-crit`, `st-stale`, `st-nolink`, `st-nodata`, `op-chip-on`, and the WARN/CRIT bar scenes — regenerate and eyeball |
| **Risk** | LVGL child paint order is an assumption. Mitigated by the pinned test; already relied on by contract 3.1 |
| **Rollback** | revert the commit; `needleReach` is self-contained |
| **Acceptance** | blade length constant (±1 px) across all three sweeps × 51 values; suites green; `dev/collide.lua` 18/18 clean |

---

## 3. Change B — make the value the hero, and give the block a rhythm

### B.1 Evidence

This is an **open owner request**, not a new opinion:
`dev/design-review-tanda5.md` P1-5 is still **🟡 partial** — *"Parte
pendiente: **agrandar la fuente del valor** … falta decidir cuánto de
`valueDrop` se cede a cambio y actualizar ese test a propósito, no por
accidente."*

Measured, balanced dials, `ShowMinMax = Markers + text`:

| zone | mode | value font | value→min/max | min/max→name | slack below name |
|---|---|---|---|---|---|
| 200×160 | normal | **S (16 px)** | 2 px | 2 px | 1 px |
| 200×200 | large | **M (24 px)** | 2 px | 2 px | 11 px |
| 260×220 | large | **L (32 px)** | 2 px | 2 px | 15 px |

Two separate problems:

1. **Every gap is 2 px** (`T.space.xs`), whatever the zone. A 260×220 dial
   has 15 px of unused slack sitting below the name while the three rows are
   jammed at the minimum spacing. The block does not breathe, and the slack is
   not offered to it.
2. **The value is small for the dial.** A 260 px instrument renders its number
   at 32 px; a 200×160 one at **16 px** — the same size as the `min 31`
   caption, which destroys the hierarchy the type ramp is supposed to express.

The horizontal branch has the mirror-image fault: 480×272 measures
**17 px** value→min/max and **85 px** min/max→name — one enormous arbitrary
gap, because the name is anchored to the bottom of the text column regardless
of where the content ended.

### B.2 Why `valueDrop` can now be reconsidered

`valueDrop = px(7)` (P0-2) pushes the value cell down so it clears the pivot
and the needle at critical angles. It is the reason the chord at the value row
is only 35 px at 200×160 — and the chord is what picks the font.

Change A establishes that **labels are created after the needle and therefore
already paint over it**. So the clearance `valueDrop` buys is *visual
tidiness*, not correctness — and the owner has already accepted the needle
passing behind a larger value (Tanda 5 3.13 / P2-5). Trading part of
`valueDrop` for chord width is exactly the decision P1-5 was waiting on.

### B.3 Options

**B-i — the spacing (independent, low risk)**

| # | Option | Verdict |
|---|---|---|
| B0 | Status quo: fixed `xs` everywhere | rejected |
| **B1** | **Distribute the slack**: gap = `clamp(slack / rows, xs, md)`, block centred in its band | **recommended** — no font change, no chord change, cannot regress the fit |
| B2 | Fixed larger gap (`sm`) | rejected: overflows the tight zones that need `xs` |
| B3 | Per-mode spacing table | rejected: a table to maintain where arithmetic suffices |

**B-ii — the value size (needs the owner's number)**

| # | Option | `valueDrop` | Effect | Verdict |
|---|---|---|---|---|
| B4 | Leave it | px(7) | none | the status quo P1-5 rejected |
| **B5** | **Reduce to px(3)** | px(3) | wider chord → ramp picks the next font up in most zones | **recommended starting point** |
| B6 | Reduce to 0 | 0 | widest chord, biggest font | needle/pivot visually behind the digits at many angles — likely too far |
| B7 | Make it mode-dependent (`large` gets px(2), others px(7)) | mixed | biggest win where there is most room | good fallback if B5 hurts 200×160 |
| B8 | Force the font one ramp step up, ignore the chord | px(7) | breaks the G-6 chord guarantee | **rejected — do not** |

B5 vs B7 must be **decided by measurement, not by argument**: implement B5,
run the table in B.1 again, and if any zone regresses (value overlapping the
pivot badly, or a font that no longer fits the chord) fall back to B7.

### B.4 Pseudocode

**`layout.lua` — distribute the slack (B1)**

```lua
-- Stack the dial's text rows in the band between the value's top and the
-- bottom of the dial, sharing whatever slack exists instead of pinning every
-- gap at xs and leaving the remainder unused below the name (measured at
-- 260x220: three 2 px gaps and 15 px of dead space under the name).
local function stackTextRows(L, top, bottom, rows)
  local contentH = 0
  for i = 1, #rows do contentH = contentH + rows[i].h end
  local gaps = #rows                              -- one above each row
  local slack = (bottom - top) - contentH
  local gap = clamp(floor(slack / max(gaps, 1)),
                    T.px(T.space.xs), T.px(T.space.md))
  -- centre the whole block in its band, so the leftover is split top/bottom
  local used = contentH + gap * (#rows - 1)
  local y = top + max(floor(((bottom - top) - used) / 2), 0)
  for i = 1, #rows do
    rows[i].y = y
    y = y + rows[i].h + gap
  end
end
```

Call site (balanced branch), replacing the current fixed-`xs` chain:

```lua
  local rows = { L.valueBox }
  if L.showMinMaxText then rows[#rows + 1] = L.minMaxBox end
  if L.showName       then rows[#rows + 1] = L.nameBox   end
  stackTextRows(L, L.valueBox.y, dial.y + dial.h, rows)
  -- minTextBox / maxTextBox inherit minMaxBox.y AFTER this, not before
```

> **Ordering trap.** `L.minTextBox` / `L.maxTextBox` are derived from
> `L.minMaxBox` today. They must be split **after** `stackTextRows`, or they
> keep the pre-distribution `y`. Same for the `clipToChord(L, L.minMaxBox)`
> call — the chord depends on the row's final depth, so it must run after the
> stack too, and the split after that.

**`layout.lua` — the value size (B5)**

```lua
-- P1-5 (Tanda 5, owner request): the value is the instrument's headline and
-- was rendering at the same size as its own min/max caption on a 200x160
-- dial. valueDrop (P0-2) pushed the cell down to clear the pivot and blade,
-- which narrows the chord that picks the font. Change A settled that the
-- labels are painted AFTER the needle and already cover it, so this
-- clearance buys tidiness, not correctness - and the owner accepted the
-- needle passing behind a larger value (3.13 / P2-5).
local valueDrop = T.px(3)          -- was T.px(7)
```

Everything else is automatic: `pickValueFont` walks the ramp against the wider
chord and takes the largest that fits, so no font is ever forced past the G-6
chord guarantee.

**Horizontal branch** — the same `stackTextRows` call fixes the 85 px gap,
with `top = L.valueBox.y + L.valueBox.h` and `bottom = textRegion.y +
textRegion.h`.

### B.5 Files, risk, acceptance

| | |
|---|---|
| **Files** | `layout.lua` (`dialLayout`: new helper + call sites), `tests/smoke_test.lua` |
| **Test to update deliberately** | *"P0-2: the value cell clears the hub…"* — P1-5 names this as the test that must be changed **on purpose**. New assertion: the cell clears the **pivot circle** (`L.pivotRadius`), which is what must stay readable; it need no longer clear the blade, which the label paints over |
| **Perf** | build-time only; zero per-frame cost |
| **Renders changed** | every dial scene. This is the change that must be reviewed by eye in both palettes |
| **Risk** | the fit is guarded by `pickValueFont` + `clipToChord`, so overflow is not possible; the risk is purely aesthetic |
| **Rollback** | `valueDrop` is one constant — revert it alone and keep B1 |
| **Acceptance** | no zone regresses in the B.1 table; `dev/collide.lua` 18/18 clean (it is the LABEL/RING collision audit — the real arbiter here); suites green |

---

## 4. Change C — tall / narrow zones

### C.1 Evidence

| zone | mode | orientation | name shown | dial ends | value box | air above | air below |
|---|---|---|---|---|---|---|---|
| **100×260** | compact | vertical | **no** | y=94 | 164–188 | **70 px** | **72 px** |
| 110×260 | normal | vertical | yes | y=104 | 163–187 | 59 px | 73 px |
| 140×280 | normal | vertical | yes | y=134 | 184–216 | 50 px | 64 px |
| 100×200 | compact | vertical | **no** | y=94 | 134–158 | 40 px | 42 px |
| 120×220 | normal | vertical | yes | y=114 | 144–176 | 30 px | 44 px |

At 100×260, **142 of 260 px (55 %)** is empty, and a 260 px-tall widget shows
**no source name at all**.

Two independent causes:

1. **The dial is width-limited.** `dialSide = min(w, h * 0.62)` → `min(100,
   161) = 100`. It cannot grow. The text region below it is then ~150 px tall
   and the value is simply centred in it, which puts ~70 px of air on each
   side. Nothing is wrong; nothing is composed either.
2. **`mode` is classified on `min(w, h)`.** At 100×260 that is 100 < 105, so
   the zone is *compact*, and `L.showName` is `normal`-or-`large` only. A very
   tall widget is judged by its narrow axis and loses its label.

### C.2 Options

**C-i — the composition**

| # | Option | Verdict |
|---|---|---|
| C0 | Status quo | rejected |
| **C1** | **Centre the whole dial+text group** in the zone rather than pinning the dial to the top | **recommended**: 3 lines, no classification change, no new state |
| C2 | Grow the dial | impossible — it is already `w`-limited |
| C3 | Let the text region shrink to content and centre only it | half of C1's benefit; still top-heavy |
| C4 | Move the value inside the dial as in *balanced* | rejected: a 100 px dial has no chord for it |

**C-ii — the missing name**

| # | Option | Blast radius | Verdict |
|---|---|---|---|
| C5 | Promote `mode` using `max(w, h)` when the ratio is extreme | **wide** — `mode` also drives tick count, minor ticks, fonts, `showScale`, `showGhost`, `showMarkers` | rejected: too much for one label |
| **C6** | **Decouple `showName` from `mode` in the vertical branch**: show it when the text region actually has room | narrow — one flag | **recommended** |
| C7 | Always show the name | rejected: micro zones genuinely have no room |

C6 is the surgical version of C5. It fixes the observed symptom without
reinterpreting a classification that six other decisions depend on.

### C.3 Pseudocode

```lua
-- layout.lua, dialLayout, vertical branch
elseif orientation == "vertical" then
  local dialSide = min(w, h * 0.62)
  ...
  -- C6: a very tall zone is classified by its NARROW axis, so a 100x260
  -- widget came out "compact" and dropped its source name - on 260 px of
  -- height. Mode still governs everything else; the name only needs room,
  -- and here we can measure whether there is any.
  local textH = h - (dial.y + dial.h) - T.px(T.space.sm) - pad
  L.showName = L.showName or (textH >= nameH + T.fontHeight(L.valueFont)
                                       + T.px(T.space.sm) * 2)
```

```lua
-- C1: centre the composition. Applied at the END of the vertical branch,
-- once every box is placed, so it is a pure translation of the whole group
-- and cannot change any fit already proven inside it.
local function centreVertically(L, w, h, boxes)
  local top, bottom = math.huge, -math.huge
  for i = 1, #boxes do
    local b = boxes[i]
    if b then
      if b.y < top then top = b.y end
      if b.y + b.h > bottom then bottom = b.y + b.h end
    end
  end
  -- the dial's painted extent, not just its box: ticks reach past it
  local dialTop = L.cy - L.tickOuter
  local dialBottom = L.cy + L.tickOuter
  if dialTop < top then top = dialTop end
  if dialBottom > bottom then bottom = dialBottom end

  local shift = floor(((h - (bottom - top)) / 2) - top)
  if shift <= 0 then return end          -- nothing to gain; never move up
  for i = 1, #boxes do
    if boxes[i] then boxes[i].y = boxes[i].y + shift end
  end
  L.cy = L.cy + shift                    -- the ring moves with its text
end
```

> **Trap.** `L.cy` must move with the boxes, and it must move **after** the
> containment clamp of §Tanda 7 (`edgeReach` is computed from `L.cy`). Either
> run `centreVertically` before that clamp, or re-derive `edgeReach`
> afterwards. Getting this wrong re-opens the negative-coordinate crash the
> current suite's `R-1` guards — so `R-1` and `R-4` are the acceptance gate
> for this change, not an afterthought.

### C.4 Files, risk, acceptance

| | |
|---|---|
| **Files** | `layout.lua` (vertical branch only), `tests/smoke_test.lua` |
| **Perf** | build-time only |
| **Renders changed** | `zone-100x260`, `zone-120x220`, and any vertical scene |
| **Risk** | interaction with the `edgeReach` containment clamp — see the trap above |
| **Rollback** | self-contained in one branch of `dialLayout` |
| **Acceptance** | air above/below within 15 px of each other on every zone in the C.1 table; name shown at 100×260; **`R-1` and `R-4` still green**; suites green |

---

## 5. Sequencing

```
A (needle occlusion)  ──┬─→  B (typography; B.2 depends on A's finding)
                        │
C (tall zones)  ────────┴─→  regenerate galleries, review both palettes
```

1. **A** first, alone, in its own commit. It is the defect, it is
   independently valuable, and it is the cheapest to revert.
2. **B1** (spacing) next — no font change, cannot regress the fit. Commit.
3. **B5** (`valueDrop`) next, as its own commit, so the aesthetic change is
   bisectable separately from the mechanical one. Re-measure the B.1 table;
   fall back to B7 if any zone regresses.
4. **C** independently.
5. Regenerate `dev/shots/` (both palettes) and `dev/gallery.lua`, then review
   by eye. Use `--baseline` against the current manifest to get a field-level
   diff of what moved.

---

## 6. Risk register

| Risk | Change | Likelihood | Mitigation |
|---|---|---|---|
| LVGL child paint order differs on hardware | A | low | pinned test; contract 3.1 already depends on it; **confirm on a bench radio** |
| A larger value collides with the ring | B5 | medium | `clipToChord` + `pickValueFont` make overflow structurally impossible; `dev/collide.lua` is the audit |
| Re-centring reopens the negative-coordinate crash | C1 | **medium** | `R-1` / `R-4` are the gate; order `centreVertically` vs `edgeReach` deliberately |
| Row-stacking leaves `minTextBox` on a stale `y` | B1 | medium | split min/max **after** the stack; noted inline |
| Every dial render changes at once | B | certain | one commit per concern, `--baseline` manifest diff, review both palettes |

---

## 7. Acceptance checklist

- [ ] `lua5.3 tests/run_tests.lua ./` — 38 green
- [ ] `lua5.3 tests/smoke_test.lua ./` — green, incl. `R-1`…`R-4`
- [ ] `lua5.3 dev/collide.lua ./` — 18/18 clean
- [ ] `lua5.3 dev/gallery.lua ./` — 77 scenes, 0 warnings, option coverage intact
- [ ] `luacheck .` — 0/0
- [ ] `dev/measure_frames.lua` — instr/frame not worse than 1458 on the needle scene; allocation still 310 B/frame, `linePoints/f` still 0
- [ ] Both palettes regenerated and reviewed by eye
- [ ] Replaced tests (P0-4, P0-2) changed **on purpose**, with the reason in the test body

---

## 8. Decisions needed from the owner

| # | Question | My recommendation |
|---|---|---|
| 1 | **A**: accept reversing Tanda 5 P0-4 (needle behind the chip)? | **Yes.** It is a defect fix; P0-4 solved a problem the paint order had already solved |
| 2 | **A**: delete `geometry.rayBoxEntry` or keep it as tested dead code? | Delete — `git` is the archive. Weak preference |
| 3 | **B5**: how much `valueDrop` to trade? `px(7) → px(3)`, or per-mode (B7)? | Start at **px(3)**, measure, fall back to B7 per-mode if 200×160 regresses |
| 4 | **B**: is a value that the needle passes behind acceptable at *every* angle, not just some? | You accepted it in 3.13/P2-5; confirming it here makes it explicit |
| 5 | **C6**: show the source name in tall zones the classifier calls *compact*? | **Yes** — 260 px of height with no label is indefensible |
| 6 | Scope: all three, or A only? | All three. A alone if time is short |

---

*Nothing here is implemented. On a "go" I will work through §5 in order, one
commit per concern, and report the measured before/after for each.*
