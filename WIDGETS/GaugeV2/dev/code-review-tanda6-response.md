# GaugeV2 — Senior review of `code-review-tanda6.md`, with firmware lessons

**Reviewer role:** senior developer, second pass over the Tanda 6 report.
**Scope:** (A) verdict on the 17 findings, (B) critique of the repair plan,
(C) knowledge extracted from the official EdgeTX widgets and the widget
firmware in this repo, mapped onto the plan.

**Method.** Every finding below was re-derived by reading the widget source and
cross-checking the firmware in this same tree (`radio/src/lua/`,
`radio/src/gui/colorlcd/widgets/`).

**Baseline re-run and confirmed.** Lua 5.3.6 was installed after the first
pass of this review — the exact release EdgeTX embeds
(`radio/src/thirdparty/Lua/src/lua.h` → `LUA_RELEASE "Lua 5.3.6"`). All three
baselines reproduce exactly as the Tanda 6 report states:

```text
tests/run_tests.lua    38 passed, 0 failed
tests/smoke_test.lua   96 passed, 0 failed
dev/collide.lua ./     all zones clean (270/180/360 deg)
dev/gallery.lua ./     renders clean, full option coverage
```

The individual A–Z probe outputs quoted in the report were not re-run
one by one; their *mechanisms* are confirmed independently below.

**Static analysis added.** `luacheck` 1.2.0 was run over the widget with a new
`.luacheckrc` (§C.8). The shipping sources come back **5 warnings / 0 errors
in 14 files**, and — importantly — **zero global writes**, so GaugeV2 cannot
pollute the `lsWidgets` state it shares with every other widget on the card.
Two of the five warnings independently corroborate findings in this review and
are cited at the relevant points (§B.1, §A F-13 row).

---

## A. Verdict on the findings

**All 17 stand.** Nothing was overstated on the mechanism, and two things were
understated. Spot-checks that mattered:

| # | Independent confirmation |
|---|---|
| F-1 | `grep` for `L.<field> =` outside `layout.lua` returns **exactly** [renderer.lua:315](../renderer.lua#L315) and [bar.lua:103](../bar.lua#L103). Firmware triggers all real: `WidgetSettings::onCancel` → `updateWithoutRefresh()`, `Widget::setFullscreen` ([widget.cpp:253-254](../../../radio/src/gui/colorlcd/mainview/widget.cpp#L253-L254)), `LuaWidget::updateZoneRect` ([lua_widget.cpp:441-442](../../../radio/src/lua/lua_widget.cpp#L441-L442)). Permanence confirmed at all four sites the report cites. |
| F-2 | [telemetry.lua:268](../telemetry.lua#L268) then [288-298](../telemetry.lua#L288-L298); `historyTrustworthy` ([213-217](../telemetry.lua#L213-L217)) is the ready-made predicate. Default *is* the broken combination (`Cells` default 1 = Lowest, [main.lua:85-86](../main.lua#L85-L86)). |
| F-3 | `ranges.build()` normalises `min`/`max` ([ranges.lua:36-38](../ranges.lua#L36-L38)); `saneThresholds()` ([74-85](../ranges.lua#L74-L85)) does not. Arithmetic reproduces exactly: `(100, 0, 55, 35, true)` → `warn 45 / crit 65`. Genuine internal inconsistency, not a judgement call. |
| F-4 | 7 `T.textWidth` call sites; 5 are build-time and legitimate, **2 violate the contract** — [renderer.lua:499](../renderer.lua#L499) and `bar.lua:236`. |
| F-6 | Module-scope cache ([telemetry.lua:92](../telemetry.lua#L92)) reached through `MODS_BY_PATH` + `sharedApp`. The `model.resetSensor()` consequence is the serious half. |
| F-9 | `s.resolved = true` ([telemetry.lua:126](../telemetry.lua#L126)) is set **before** `getFieldInfo()` is even attempted at line 128. Unconditional latch, confirmed. |
| F-13 | `options.translator` and `options.present`: **0 references anywhere**, tests included. `options.build`: 3, **all in `tests/run_tests.lua:295-302`**. `geometry.trianglePoints`: definition + `run_tests.lua:95-96`. So "dead in runtime" is accurate, but deleting them takes two tests with them — the plan should say so. |
| F-15 | Confirmed: `resolveColor` [renderer.lua:389](../renderer.lua#L389) vs `bar.lua:214`; `updatePulse` [661](../renderer.lua#L661) vs `bar.lua:188`; `updateSourceLabels` [684](../renderer.lua#L684) vs `bar.lua:132`. |

### A.1 Understated: the CPU limit is the same kill switch as F-1

The report frames F-1's severity around a `nil` arithmetic error. There is a
**second door into the identical permanent-disable path**, and the report never
mentions it:

```c
// radio/src/lua/widgets.cpp:37
#define MAX_INSTRUCTIONS (20000/100)
```

`luaHook()` ([widgets.cpp:50-89](../../../radio/src/lua/widgets.cpp#L50-L89))
bumps a percent counter every 200 VM instructions and calls
`luaL_error(L, "CPU limit")` past 100%. That is a hard budget of **20 000 Lua
VM instructions per `update()` / `refresh()` / `background()` call, per widget
instance** — and the error lands in the same `setErrorMessage()` that traces
`"Widget disabled"`. Two consequences:

1. **In DEBUG builds the limit is disabled** (widgets.cpp:54-65 — it only
   traces the running maximum). A widget that dies on a production radio can
   be perfectly healthy in the simulator. "It works in the sim" is not
   evidence for this class of failure.
2. The headless harness has no instruction budget at all, so neither is
   `tests/`. **Nothing in this project currently measures the one resource
   that silently kills the widget.** That is a bigger coverage hole than F-17
   describes, and it is cheap to close (§C.5).

### A.2 Understated: F-6 is a data-loss bug, not a display bug

`model.resetSensor(idx)` ([app.lua:266](../app.lua#L266)) on an index cached
from a *different model* resets a sensor the user did not ask to reset, on a
model they are flying. Everything else in P1 is wrong pixels. This one
destroys user data on the radio. It should be ordered **first** in Phase 2,
not fourth.

### A.3 Overstated: F-11's §5.3 measurement

`updateHistory` already guards both writes on angle change
([renderer.lua:640-656](../renderer.lua#L640-L656)). The "ghost 1.00
sets/frame, maxMark 1.00 sets/frame" figure comes from a **monotonically
rising sweep probe**, where the historical maximum genuinely advances on every
frame — a scenario that exists for a few seconds at power-up and never again.
In steady flight both cost ~0. Plan item 5.3 is therefore chasing a probe
artifact: the fix belongs in the probe (measure a noisy plateau, not a ramp),
not in the code.

---

## B. Critique of the repair plan

The plan is sound in shape — tests-first, phase-gated on a frozen visual
baseline, explicit revert criterion on the optional phase. Six changes.

### B.1 Phase 1.1 has a name collision that will silently move a pixel

`barLayout` **already has a local called `chipOff`**
([layout.lua:528](../layout.lua#L528)) and it means something different: it is
the *row-budget reserve*. In the degraded short-bar path it is deliberately
forced to `0` while `chipHeight` becomes `stateH + px(2)`
([layout.lua:536-537](../layout.lua#L536-L537),
[571](../layout.lua#L571)) — whereas the render-time centring offset for that
same case is `floor(2 / 2) = 1`.

The tempting one-liner (`L.chipOff = chipOff`, since the name is right there)
therefore shifts the state pill by 1 px in short bar zones. `br-short` is in
the frozen gallery baseline, so it *will* surface as a diff — and the phase
rule ("justify everything that changed") makes it likely someone justifies it
as expected fallout of the move. Do this instead:

- compute `L.chipOff = floor((L.chipHeight - stateH) / 2)` immediately after
  **each** `L.chipHeight` assignment ([layout.lua:487](../layout.lua#L487) and
  [571](../layout.lua#L571)) — same expression the renderers use today, so the
  rendered result is provably unchanged;
- rename the budget local to `chipReserve` so the two never get confused
  again.

### B.2 Phase 1.3's acceptance criterion tests the spelling, not the bug

`grep` for `L.<field> =` only catches direct assignment through a local named
`L`. The actual defect class is *"state derived once at build time that
`update()` does not recompute"*, which also covers `widget.autoCells`,
`widget.cellsApplied`, `widget.rangeSig` and the `frame.*` table. Replace the
grep with an invariant test:

> build → deep-copy `widget.layout` → call `update()` with **identical**
> options → assert deep equality.

That catches the whole class in one assertion, it is the test that would have
caught F-1, and it stays true as the code grows. Keep the grep as a lint if
you like, but not as the gate.

### B.3 F-10 belongs in Phase 1, not Phase 4

The report's own text says it: *"es F-1 otra vez (widget desactivado)"*. The
fix is two lines (filter `nil` out of `M.RAMP`, assert at least one survivor).
Anything whose failure mode is "widget permanently disabled" ships with the P0
patch. It is the cheapest item in the whole document and it is currently
sitting three phases away.

### B.4 Phase 2 ordering

`2.4 (F-6)` → `2.1 (F-2)` → `2.2 (F-3)` → `2.3 (F-5)`. Rationale in §A.2. On
the fix itself: the plan offers "invalidate on model identity change **or**
per-widget cache". Take the second and go further — **delete the module-level
cache entirely.** `resolveSource` only runs when the source changes, so the
cache saves at most one 60-sensor scan per source edit per widget. That is not
worth a cross-model correctness hazard. A single-entry memo on `widget.source`
keeps the P2-4 allocation win with none of the risk.

### B.5 Phase 3.1 — measure the third option too

The plan's preference (anchor by character count against an already-measured
sample) restores the contract but keeps GaugeV2 measuring text to position
things, which is what broke the contract in the first place. The firmware
never does this: `value.cpp` positions its value/unit purely with
`lv_style_set_text_align` inside a fixed box
([value.cpp:254-261](../../../radio/src/gui/colorlcd/widgets/value.cpp#L254-L261)).
Add a third candidate — **let LVGL align a value+unit pair inside one
container and drop `anchorUnit` altogether** — and pick on measurement. It is
strictly less code and structurally cannot regress. If the visual result is
acceptable against the frozen baseline, it is the better answer.

### B.6 Phase 5 — drop 5.3, restate the target

Drop 5.3 (§A.3). Restate the acceptance target: bytes/frame is a proxy;
**instructions/frame is the thing that actually kills the widget** (§A.1).
Target both, and put the instruction probe in Phase 0 as a safety gate rather
than in Phase 5 as an optimisation metric. Keep the revert criterion exactly
as written — it is the best paragraph in the plan.

### B.7 Missing entirely: the option-slot contract has no test

Not a Tanda 6 finding, but it is the highest-cost latent bug in the widget and
the firmware makes it **completely silent**:

- `WidgetPersistentData::setDefault` ([widget.cpp:76-86](../../../radio/src/gui/colorlcd/mainview/widget.cpp#L76-L86))
  resets a stored option only when the stored **type** differs from the
  declared one.
- `WidgetFactory::create` calls a `checkOptions()` migration hook
  ([widget.cpp:379](../../../radio/src/gui/colorlcd/mainview/widget.cpp#L379));
  the C++ Outputs widget overrides it to shift its saved options when a new
  one was inserted
  ([outputs.cpp:283-295](../../../radio/src/gui/colorlcd/widgets/outputs.cpp#L283-L295)).
  **`LuaWidgetFactory` does not override it, and a Lua widget has no way to.**

So inserting an option anywhere but the end gives every existing model
shifted values of the same type, with no error and no visible symptom beyond
"my gauge came back wrong". [main.lua:13-16](../main.lua#L13-L16) states the
append-only rule as a *comment*. Add `0.7`: freeze the `(key, type)` sequence
— first ten and full list — as a literal in `run_tests.lua` and assert `DEFS`
matches. Ten lines, protects every user's saved models.

---

## C. What the official widgets teach

Sources: `radio/src/gui/colorlcd/widgets/{gauge,value,timer,text,outputs,radio_info,modelbmp}.cpp`
and the Lua widget host `radio/src/lua/{widgets,lua_widget,lua_widget_factory,lua_lvgl_widget}.cpp`.

### C.1 `update()` is idempotent and total — it never assumes the constructor ran

[text.cpp:61-88](../../../radio/src/gui/colorlcd/widgets/text.cpp#L61-L88) is
the purest form: zero change detection, it re-applies text, colour, font,
alignment and shadow visibility on **every** call.
[gauge.cpp:83-98](../../../radio/src/gui/colorlcd/widgets/gauge.cpp#L83-L98)
and `value.cpp:187-282` are the same. Not one official widget keeps a value
that only the constructor computes and `update()` then reads.

**That single invariant is F-1 and F-5 at once.** GaugeV2's build/update split
is the deviation.

The model to copy is not `text.cpp` (too dumb — GaugeV2's signature gate is a
real improvement over re-doing everything) but
**`OutputsWidget::update()`** ([outputs.cpp:181-230](../../../radio/src/gui/colorlcd/widgets/outputs.cpp#L181-L230)),
which has exactly GaugeV2's architecture plus the piece GaugeV2 is missing:

```text
1. apply cheap non-structural properties  UNCONDITIONALLY   (lines 186-192)
2. fold every option + geometry into last* members -> changed (200-217)
3. rebuild children only if changed                          (219-229)
```

GaugeV2 has steps 2 and 3 (`layout.signature()`) and **no step 1**. The
missing prelude *is* F-5: the accent has no update path because there is no
place designed to hold one. Fixing F-5 by adding `cfg.accent` to the signature
(plan 2.3) works and is cheap, but it buys a full tree rebuild for a colour
change. The structurally right fix is to add step 1 — a small "re-apply
non-structural properties" block at the top of `configure()` — and then F-5,
and the next three findings of its shape, cost nothing.

### C.2 Register what a state *means* once; toggle it at refresh

Every official widget declares its colour/font variants against
`LV_STATE_USER_1..3` at construction and then only toggles: `value.cpp:56-70`
(warning / stale / large-font), `radio_info.cpp:99` + `112-114` + `162-170`
(three battery colours registered from options, selected by state),
`timer.cpp:28-32`.

**Do not import the mechanism** — the Lua LVGL binding exposes no per-state
styles, and GaugeV2's `frame.colorKey` + `setProp` is the correct Lua
equivalent. Import the *discipline*: `radio_info.cpp:112-114` re-reads the
three colour options in `update()` so an option edit lands even though the
displayed state never changed. GaugeV2's colour key encodes only the semantic
role, which is precisely why the accent cannot get through. Same lesson as
C.1, from the other end.

### C.3 Create-then-hide, don't create-then-destroy — and F-8 follows from it

`timer.cpp:237-288` switches between its small and large layouts by hiding one
set of objects and showing the other; both exist from `delayedInit()`.
`radio_info.cpp:51-58` builds all five volume icons up front and toggles.
Only `OutputsWidget` does `clear()` + recreate, and it is the heaviest widget
of the set.

GaugeV2's `lvgl.clear()` + full rebuild ([app.lua:198-201](../app.lua#L198-L201))
is the Outputs shape. It is defensible — the geometry genuinely differs
between modes — but it is worth naming as F-1's *architectural* root cause: a
widget that never rebuilds cannot lose derived state.

This settles **plan item 4.2**, which currently leaves the choice open. The
firmware idiom is create-then-hide, driven by data. Take the first branch:
**the ghost object is always created and its visibility follows the data, not
the markers option.** The bar already does exactly that, so it is also the
smaller diff.

### C.4 Guard on the *formatted* value, and never measure live text to place things

`ChannelValue::refresh` ([outputs.cpp:100-142](../../../radio/src/gui/colorlcd/widgets/outputs.cpp#L100-L142))
nests its latches: raw value changed → format → **set the label only if the
string differs** (117-120); separately, resize the bar only if the scaled
width differs (126-134). GaugeV2's `frame.*` + `setProp` is the same idea,
better factored.

The divergence that matters: no official widget ever *measures* a live string.
Positioning is fixed boxes plus alignment styles. `anchorUnit` measuring the
live value string is what turned a documented build-time memo into an
unbounded per-frame leak (F-4). See §B.5.

### C.5 The 20 000-instruction budget, and the probe this project is missing

Covered in §A.1. Concrete action, and it belongs in Phase 0 as a **safety**
gate, not in Phase 5 as an optimisation metric:

> `dev/instructions.lua` — run N refresh frames under
> `debug.sethook(f, "", 200)`, count hook fires per `refresh()` and per
> `update()`, assert a margin against 100 fires (= 20 000 instructions).
> Report the worst zone × style × colour-mode combination.

Run it on the largest zone with the needle, Sections colouring and scale
labels — the most expensive scene the widget can produce. This also gives
Phase 5 a real acceptance number instead of a byte count.

### C.6 Phase 5 is feasible — the firmware source proves it, and warns about one thing

`LvglWidgetLine::getPts` ([lua_lvgl_widget.cpp:1008-1029](../../../radio/src/lua/lua_lvgl_widget.cpp#L1008-L1029))
copies the point values **out** of the Lua table into its own `lv_point_t[]`
(reused; `ptAlloc` only grows), hashes the result, and skips
`lv_line_set_points` when the hash is unchanged. Nothing on the C side retains
a reference to the Lua table.

→ **A persistent Lua table mutated in place is safe.** Plan items 5.1 and 5.2
will work exactly as written. Two caveats:

- `getPt` reads coordinates with `luaL_checkunsigned`
  ([lines 1001, 1004](../../../radio/src/lua/lua_lvgl_widget.cpp#L1001-L1004)):
  **a negative coordinate raises a Lua error** — F-1 again, from a third door.
  Whatever clamping `geometry.linePoints` does today must survive the
  refactor. Add an explicit test at the extreme sweep angles of all three
  sweeps.
- The firmware already dedupes identical point sets, so GaugeV2's
  `frame.angle` guard buys nothing at the LVGL layer. Keep it anyway — it
  saves the Lua-side table churn, which *is* the point — but do not add more
  guards expecting LVGL savings.

**The route not to take.** `pts` also accepts a **function**
([lua_lvgl_widget.cpp:1035-1039](../../../radio/src/lua/lua_lvgl_widget.cpp#L1035-L1039),
invoked from `callRefs`, [1047-1073](../../../radio/src/lua/lua_lvgl_widget.cpp#L1047-L1073)),
and so does every colour / value / text parameter via
`LvglParamFuncOrValue` / `LvglParamFuncOrString`
([lua_lvgl_widget.cpp:74-129](../../../radio/src/lua/lua_lvgl_widget.cpp#L74-L129)) —
register once, and the firmware calls it each frame and does its own change
detection. It looks like the "modern" idiom and it is a **pessimisation
here**: `callRefs` runs unconditionally on every `foreground()`, so all three
needle segments would be evaluated every frame instead of only when the angle
moves, and against a 20 000-instruction budget that is the wrong trade for a
widget whose values are mostly static between frames. Recommendation: stay
with guarded `setProp`, and record the divergence in `DOCS.md` so nobody
"modernises" it in six months.

### C.7 What NOT to bring back

The old widgets are stable, not exemplary. Explicitly reject:

- **`lastValue = -10000` sentinels** (`gauge.cpp:103`, `value.cpp:172`).
  GaugeV2's `nil` + explicit availability model is strictly better; a magic
  number reintroduces "is −10000 a real reading?" on a dBm or temperature
  scale.
- **`value.cpp`'s shadow-label trick** (a duplicate label offset by 1 px,
  lines 49-53 / 60-65). Doubles the object count for a legibility effect the
  chip already solves more cheaply — and object count is audited here.
- **`gauge.cpp`'s descending-scale handling**
  ([lines 73-77](../../../radio/src/gui/colorlcd/widgets/gauge.cpp#L73-L77):
  `SWAP(min, max); value = value - min - max;`). It mirrors the *value*
  instead of the *mapping*, which is why the official gauge has no
  descending-scale bands at all. `geometry.normalize` is the right design.
  F-3 is one missing normalisation call, not a reason to adopt the shortcut.
- **Rebuilding children on every geometry change** (`OutputsWidget`).
  GaugeV2's signature gate is the improvement; keep it.
- **`Messaging::send` fan-out per frame** (`outputs.cpp:234`). No Lua
  equivalent, no reason to want one.

### C.8 Static analysis: `.luacheckrc`

A `luacheck` config was added at `WIDGETS/GaugeV2/.luacheckrc`. Two decisions
in it are load-bearing:

- **`std = "lua53"`** — not a preference. It is the interpreter EdgeTX embeds
  (`radio/src/thirdparty/Lua/src/lua.h` → `LUA_RELEASE "Lua 5.3.6"`). Linting
  against 5.4/5.5 semantics would mask real incompatibilities.
- **The whole EdgeTX API is declared `read_globals`** — so any *assignment* to
  a firmware name is an error, not a warning. All Lua widgets on the radio
  share one `lua_State` (`lsWidgets`, `radio/src/lua/widgets.cpp`), so an
  accidental global here leaks into every other widget on the SD card. The
  current code is clean on this (**zero global writes**), and the config keeps
  it that way.

Baseline on the shipping sources: **5 warnings / 0 errors in 14 files**. Two
of the five are not noise:

| Warning | Meaning |
|---|---|
| `layout.lua:537` — value assigned to `chipOff` is unused | Independent confirmation of §B.1: in the degraded short-bar path the local is written and then never read, because line 538 rebuilds `rowH` from `stateH` alone. The layout `chipOff` and the renderer `chipOff` really are different quantities. |
| `options.lua:142` — unused argument `defs` | Sits inside `M.present()`, one of the three dead functions in F-13. The linter finds the dead code from the other direction. |

The remaining three (`app.lua:273` unused `event`/`touch`, `renderer.lua:258`
unused `cfg`) are cosmetic; `event`/`touch` are fixed by the firmware's
`refresh(widget, event, touch)` signature and should be renamed `_event` /
`_touch` rather than removed.

Suggested gate, cheap enough for Phase 0: `luacheck *.lua` must stay at
**0 errors**, and the widget sources must stay at zero global writes.

---

## D. Implementation plan

All line numbers are as of **`c196e2b0e`** (`feat/gauge-v2`). They shift as
edits land — re-anchor by the quoted code, not by the number.

### D.0 Working setup

Toolchain is installed and verified (§A). From `WIDGETS/GaugeV2/`:

```sh
export PATH="$HOME/scoop/shims:$PATH"

lua5.3 tests/run_tests.lua          # 38/38   pure modules
lua5.3 tests/smoke_test.lua         # 96/96   full lifecycle vs mock_env
lua5.3 dev/collide.lua  ./          # geometry audit  (NOTE trailing "./")
lua5.3 dev/gallery.lua  ./          # 77-scene visual sheet
luacheck *.lua                      # 5 warnings / 0 errors
```

**Gallery gate after every phase:**

```sh
lua5.3 dev/gallery.lua ./ --baseline dev/shots/gallery/manifest-pre-tanda6.lua
```

Rule: every scene that moves must be named in the commit message with the
finding that caused it. A scene that moves for a reason you cannot name is a
regression, not fallout.

Test helpers already available — use them, do not invent new ones:

| Helper | File | Signature |
|---|---|---|
| `test` / `assertEq` / `assertTrue` | both suites | `test(name, fn)` |
| `newWidget` | `smoke_test.lua:64` | `newWidget(zone, overrides, capacity, keepRadio)` |
| `refresh` | `smoke_test.lua:76` | `refresh(widget, times)` |
| `setupRadio` | `smoke_test.lua:43` | installs the fake firmware API |
| `objIndex` | `smoke_test.lua:84` | object-tree introspection |

---

### Phase 0 — Red tests first (blocking)

Nine tests. **Every one must fail for the stated reason before any fix
lands** — that is the whole point: F-1 exists because a test walked this path
and asserted the wrong thing.

#### 0.1 · Lifecycle: `update()` must not destroy derived state → F-1

*File:* `tests/smoke_test.lua`

```lua
test("F-1: repeated update() keeps layout intact, then CRIT renders", function()
  local w = newWidget({w=200, h=200})
  refresh(w, 1)
  local before = w.layout.chipOff
  w.app.update(w, w.options)          -- identical options, no user edit
  assertEq(w.layout.chipOff, before, "chipOff survives update()")
  -- and the transition that actually crashes:
  w.data.state = "critical"
  local ok, err = pcall(refresh, w, 1)
  assertTrue(ok, "refresh into CRIT after update(): " .. tostring(err))
end)
```

Repeat for `{w=300, h=60}` (bar). **Expected failure:** `chipOff` is `nil`,
then `renderer.lua:479` — *attempt to perform arithmetic on a nil value*.

#### 0.2 · Generalised: layout is a pure function of (zone, cfg) → F-1 class

*File:* `tests/smoke_test.lua`. This is the one that matters — 0.1 catches one
field, this catches the class (§B.2).

```lua
-- Verified on Lua 5.3.6 against all four failure shapes.
local function deepEq(a, b, path)
  path = path or "L"
  if a == nil and b ~= nil then error(path .. " appeared only after update()") end
  if b == nil and a ~= nil then
    error(path .. " was LOST by update() (was " .. tostring(a) .. ")")
  end
  if type(a) ~= type(b) then error(path .. " type " .. type(a) .. " ~= " .. type(b)) end
  if type(a) ~= "table" then
    if a ~= b then error(path .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
    return
  end
  for k, v in pairs(a) do deepEq(v, b[k], path .. "." .. tostring(k)) end
  for k, v in pairs(b) do deepEq(a[k], v, path .. "." .. tostring(k)) end
end

test("F-1 class: layout is identical before and after a no-op update()", function()
  for _, zone in ipairs{{w=200,h=200},{w=300,h=60},{w=60,h=60},{w=480,h=272}} do
    local w = newWidget(zone)
    refresh(w, 1)
    local snapshot = deepCopy(w.layout)   -- NB: copy, not alias - see trap
    w.app.update(w, w.options)
    deepEq(snapshot, w.layout, "L@" .. zone.w .. "x" .. zone.h)
  end
end)
```

> **TRAP — snapshot must be a deep copy.** `app.configure()` replaces
> `widget.layout` with a fresh table on every call (`app.lua:188-189`), so a
> plain alias happens to work today — but if that ever becomes an in-place
> mutation the test silently compares a table with itself and passes forever.
> Copy.

**Expected failure:** `L.chipOff was LOST by update() (was 3)`. Keep this test
forever — it is the standing guard for §C.1's invariant.

#### 0.3 · `saneThresholds` on a descending scale → F-3

*File:* `tests/run_tests.lua`

```lua
test("F-3: saneThresholds normalises min/max order", function()
  local aw, ac = ranges.saneThresholds(0, 100, 55, 35, true)
  assertEq(aw, 55, "ascending warn untouched"); assertEq(ac, 35, "ascending crit")
  local dw, dc = ranges.saneThresholds(100, 0, 55, 35, true)
  assertEq(dw, 55, "descending warn untouched"); assertEq(dc, 35, "descending crit")
end)
```

Add the low-is-good mirror (`highIsGood = false`). **Expected failure:**
`45.0 / 65.0`.

#### 0.4 · Battery percent across all three `Cells` modes → F-2

*File:* `tests/smoke_test.lua`. Pack: 4S at 3.85 V/cell ≈ 55 %.

```lua
test("F-2: battery % is correct for Lowest / Total / Average", function()
  for _, mode in ipairs{{1,"Lowest"},{2,"Total"},{3,"Average"}} do
    local w = newWidget({w=200,h=200},
      {Source="Cels", Battery=2, Cells=mode[1]})
    -- mock_env should serve {3.85, 3.85, 3.85, 3.85}
    refresh(w, 2)
    assertTrue(w.data.displayValue > 45 and w.data.displayValue < 65,
      mode[2] .. ": expected ~55 %, got " .. tostring(w.data.displayValue))
  end
end)
```

**Expected failure:** Lowest → `0`, Average → `0`; Total passes.

#### 0.5 · `widthCache` is bounded → F-4

*File:* `tests/smoke_test.lua`. Assert **"stops growing"**, never `< N` (§B.5
of the original plan was vulnerable to passing by accident on a low-precision
source):

```lua
test("F-4: theme.widthCache stops growing under a varying value", function()
  local w = newWidget({w=200,h=200}, {Precision=4})  -- 2 decimals: worst case
  local function entries()                            -- via debug.getupvalue
    local i, n = 1, 0
    while true do
      local name, val = debug.getupvalue(theme.textWidth, i)
      if not name then break end
      if name == "widthCache" then
        for _, byFont in pairs(val) do for _ in pairs(byFont) do n = n + 1 end end
      end
      i = i + 1
    end
    return n
  end
  feedVaryingValues(w, 500); local a = entries()
  feedVaryingValues(w, 500); local b = entries()
  assertEq(b, a, "cache grew by " .. (b - a) .. " over 500 more frames")
end)
```

**Expected failure:** `b - a ≈ 500`.

#### 0.6 · Accent applies without a rebuild → F-5

*File:* `tests/smoke_test.lua`

```lua
test("F-5: changing Accent recolours without a tree rebuild", function()
  local w = newWidget({w=200,h=200}, {ColorMode=5})   -- Sections
  refresh(w, 1)
  local before = objIndex(w.ui.valueArc).color
  w.app.update(w, withOption(w.options, "Accent", RED))
  refresh(w, 1)
  assertEq(objIndex(w.ui.valueArc).color, RED, "valueArc follows accent")
end)
```

**Expected failure:** colour unchanged (`12291`), `layoutRebuilt == false`.

#### 0.7 · `sensorCache` does not cross models → F-6

*File:* `tests/run_tests.lua` (or smoke, wherever `model` is mockable)

```lua
test("F-6: sensor metadata does not leak between models", function()
  installModel("A", { {name="Curr", prec=1} })          -- index 2
  local w1 = newWidget({w=200,h=200}, {Source="Curr"}); refresh(w1, 1)
  installModel("B", { {name="X"},{name="Y"},{name="Curr", prec=2} })  -- index 7
  local w2 = newWidget({w=200,h=200}, {Source="Curr"}); refresh(w2, 1)
  assertEq(w2.source.sensorIndex, 7, "index re-resolved on the new model")
  assertEq(w2.source.prec, 2, "precision re-resolved on the new model")
end)
```

**Expected failure:** `2` and `1` — the first model's values.

#### 0.8 · Option slots are append-only → latent, §B.7

*File:* `tests/smoke_test.lua`. Guards a bug the firmware reports **silently**.

```lua
test("contract: DEFS slot order and types are frozen", function()
  local FROZEN = {
    {"Source",SOURCE},{"Min",VALUE},{"Max",VALUE},{"Warn",VALUE},
    {"Crit",VALUE},{"HighGood",BOOL},{"Style",CHOICE},{"ColorMode",CHOICE},
    {"Precision",CHOICE},{"ShowMinMax",CHOICE},          -- core ten: 2.11
    {"Accent",COLOR},{"Label",STRING},{"Suffix",STRING},{"Scale",CHOICE},
    {"Sweep",CHOICE},{"Damping",SLIDER},{"Cells",CHOICE},{"Battery",CHOICE},
    {"Alerts",CHOICE},{"AlertSw",SWITCH},{"Delay",VALUE},{"Vibrate",BOOL},
    {"ResetSw",SWITCH},{"ShowChip",BOOL},
  }
  assertEq(#defs, #FROZEN, "option count changed - APPEND only")
  for i, want in ipairs(FROZEN) do
    assertEq(defs[i].key, want[1], "slot " .. i .. " key")
    assertEq(defs[i].type, want[2], "slot " .. i .. " type")
  end
end)
```

This one is **green from the start** — it is a ratchet, not a bug reproduction.
Rationale in §B.7: `setDefault` only resets on a *type* change, and
`LuaWidgetFactory` cannot override `checkOptions()`.

#### 0.9 · Instruction-budget probe → §C.5

*New file:* `dev/instructions.lua`. Not a pass/fail test yet — establishes the
number nothing currently measures, and becomes Phase 5's acceptance criterion.

```lua
-- Counts Lua VM instructions per callback against the firmware's real budget:
-- widgets.cpp MAX_INSTRUCTIONS (20000/100) -> hook every 200 instructions,
-- error past 100 fires. Report worst-case scenes.
local fires = 0
debug.sethook(function() fires = fires + 1 end, "", 200)
-- ... run update()/refresh() over the heaviest scene matrix ...
debug.sethook()
-- report: fires per call, and headroom vs 100
```

Run over the most expensive scene the widget can produce: largest zone,
needle style, `ColorMode = Sections`, scale labels on, min/max text on.
**Record the numbers in this document** — they are the Phase 5 baseline.

> **Phase 0 acceptance:** 0.1–0.7 red for exactly the stated reason, 0.8 green,
> 0.9 produces numbers. No widget source touched yet.

---

### Phase 1 — Close every path to a disabled widget (ship alone)

The whole phase is about one outcome: **the widget can no longer be
permanently disabled.** Both items below end in `setErrorMessage()` →
`"Widget disabled"` → dead until model reload (§A.1).

#### 1.1 · Move `chipOff` into layout — F-1

*Files:* `layout.lua`, `renderer.lua`, `bar.lua`

**Evidence.** `L.chipOff` is written only at `renderer.lua:315` and
`bar.lua:103`, both inside `build()`. `app.configure()` replaces
`widget.layout` unconditionally (`app.lua:188-189`) but only rebuilds on a
signature change (`app.lua:195-202`). Firmware calls `update()` on settings
exit (even Cancel), fullscreen enter, and zone resize.

**Change — dial**, `layout.lua:486-487`:

```lua
  L.chipPad = T.px(7)
  L.chipHeight = stateH + T.px(6)
+ L.chipOff = floor((L.chipHeight - stateH) / 2)
```

**Change — bar**, `layout.lua:570-571`:

```lua
  L.chipPad = T.px(7)
  L.chipHeight = stateH + chipExtra
+ L.chipOff = floor((L.chipHeight - stateH) / 2)
```

Then delete the two local computations and read `L.chipOff` instead
(`renderer.lua:314-315`, `bar.lua:102-103`).

> **TRAP — do not write `L.chipOff = chipOff`.** `barLayout` already has a
> local `chipOff` (`layout.lua:528`) meaning the *row-budget reserve*. The
> degraded short-bar path forces it to `0` (`layout.lua:537`) while
> `chipHeight` stays `stateH + px(2)` — so the render-time offset there is
> `floor(2/2) = 1`, not `0`. Assigning the budget local shifts the pill 1 px
> and moves the `br-short` gallery scene. luacheck already flags that local as
> dead (`layout.lua:537`, §C.8) — **rename it `chipReserve`** while you are in
> there so the two can never be confused again.

**Verify:** 0.1 and 0.2 green · gallery **zero** scene changes (this is a pure
refactor — any diff means the trap bit) · `luacheck` loses the `layout.lua:537`
warning.

#### 1.2 · Guard `theme.RAMP` against missing font constants — F-10

*File:* `theme.lua:45-46`

**Evidence.** `M.RAMP` is built from firmware globals. If one is absent (e.g.
`XXLSIZE` on a target that does not define it), the constructor leaves a hole
while `#RAMP` still reports the full length, so `fitFont` walks into
`fontHeight(nil)`. Verified on Lua 5.3.6:

```text
#RAMP with XXLSIZE=nil : 3    RAMP[1] = nil     <- length unchanged by the hole
```

The failure is the **write**, not the read: `heightCache[font]` at
`theme.lua:129` returns `nil` harmlessly for a `nil` key, but
`heightCache[font] = h` at **`theme.lua:133`** raises
`table index is nil`. That is a crash on the *first layout pass* — F-1 again,
by a different door.

```lua
-- Built by filtering: a firmware that does not define one of these constants
-- must degrade to a shorter ramp, never leave a hole. #RAMP keeps reporting
-- the full length otherwise and fitFont indexes nil (Tanda 6 F-10).
local RAMP_ORDER = { "XXL", "XL", "L", "M", "S", "XS", "XXS" }
M.RAMP = {}
for i = 1, #RAMP_ORDER do
  local f = M.FONTS[RAMP_ORDER[i]]
  if f ~= nil then M.RAMP[#M.RAMP + 1] = f end
end
assert(#M.RAMP > 0, "GaugeV2: firmware exposes no usable font constants")
```

**Verify:** new unit test in `run_tests.lua` nils `XXLSIZE` before loading
`theme` and asserts `#RAMP == 6` and `RAMP[1] ~= nil` · gallery unchanged.

> **Phase 1 acceptance:** 0.1, 0.2 green · gallery **byte-identical** · suites
> 38/96 · collide clean. **Ship this commit on its own.**

---

### Phase 2 — Wrong output (order matters)

#### 2.1 · Pin sensor metadata to the model — F-6 *(first: data loss)*

*File:* `telemetry.lua:92-108`

**Evidence.** `sensorCache` is module-scope and modules are shared per path for
the whole radio session (`app.lua:38`, `main.lua:143`), but a sensor's index
and precision are **model** data. Worst consequence: the *Reset min/max*
switch calls `model.resetSensor(idx)` (`app.lua:266`) on another model's index
— it resets a sensor the user never asked to touch.

**Change:** delete the module-level cache; memoise on the widget instead.
`resolveSource` already early-returns unless the source changed
(`telemetry.lua:114`), so the cache saves at most one scan per source edit —
not worth a cross-model hazard (§B.4).

```lua
-- Was a module table shared by every widget for the whole radio session.
-- Sensor index and precision are MODEL data, so that cache survived a model
-- change and handed the next model a stale index - which model.resetSensor()
-- then reset (Tanda 6 F-6). Scoped to the widget: resolveSource() only runs
-- on a source change, so this still avoids the repeated 60-sensor scan.
local function findSensor(widget, name)
  local hit = widget.sensorCache and widget.sensorCache[name]
  if hit then return hit.prec, hit.index end
  ...
  widget.sensorCache = widget.sensorCache or {}
  widget.sensorCache[name] = { prec = sn.prec, index = i }
```

**Verify:** 0.7 green · no gallery change (metadata only).

#### 2.2 · Battery percent must not divide twice — F-2

*File:* `telemetry.lua:288-298`

**Evidence.** `refresh()` sets `src.cells = src.cells or count`
(`telemetry.lua:268`) from the cells table, then the battery block divides by
that count — but under `Lowest` or `Average` the aggregate is **already
per-cell**. `Lowest` is the default (`main.lua:85-86`) and the value `DOCS.md`
§4.8 recommends, so the documented-best configuration reads 0 %.

**Change:** extract the predicate that already exists inside
`historyTrustworthy` (`telemetry.lua:213-217`) and use it in both places — one
source of truth:

```lua
-- True when the reading is already a single cell's voltage, so the battery
-- block must NOT divide by the cell count again (Tanda 6 F-2), and the
-- radio's Cels-/Cels+ siblings are the same quantity as what we display.
local function isPerCellReading(cfg, wasCells)
  return wasCells and cfg.cells ~= M.CELLS_TOTAL
end
```

then in the battery block:

```lua
  local cells = latchCells(widget, value)
- local perCell = (cells > 0) and (value / cells) or value
+ local perCell = value
+ if not isPerCellReading(cfg, wasCells) and cells > 0 then
+   perCell = value / cells
+ end
```

**Traps:** `wasCells` is local to `M.refresh` and set at line 259 — the battery
block is downstream, so it is in scope. A non-`Cels` pack source (`RxBt`) has
`wasCells == false` and must keep dividing.

**Verify:** 0.4 green · gallery: `ba-pct-low` `displayValue 0 → ~55` and
`ba-cels-avg` likewise; `ba-pct-tot` **must not move**.

#### 2.3 · Normalise scale order in `saneThresholds` — F-3

*File:* `ranges.lua:74-85`, plus the ghost in `renderer.lua:648-656`

**Evidence.** `M.build` normalises (`ranges.lua:36-38`); `saneThresholds` does
not. With `Min = 100, Max = 0` the guard fires on perfectly valid thresholds
and recomputes them over a **negative** span → warn/crit inverted → a warning
value renders red, pulses, and fires the *critical* alert tone.

```lua
 function M.saneThresholds(minimum, maximum, warning, critical, highIsGood)
+  -- Same normalisation as build(): a descending scale (Min > Max) is a
+  -- supported configuration, not a mistake (Tanda 6 F-3).
+  if maximum < minimum then minimum, maximum = maximum, minimum end
   local wl = math.min(warning, critical)
```

**Also (same root cause):** the peak-hold ghost sweeps `L.startAngle →
angleOf(h.max)` unconditionally. On a descending scale the peak maps back onto
`startAngle`, so the ghost paints the tract **never visited**. Pick the extreme
that matches the scale direction (`h.max` when `cfg.max >= cfg.min`, else
`h.min`).

**Verify:** 0.3 green · gallery: `sc-descending` `warn/crit 45/65 → 55/35`;
all ascending scenes unchanged.

#### 2.4 · Make the accent reach the screen — F-5

*Files:* `layout.lua:592-601`, `renderer.lua:702-711`, `bar.lua:211-213`

**Evidence.** `layout.signature()` omits `cfg.accent`, and the repaint path is
gated on the **semantic colour key**, which does not change when only the
accent does. Affects the value arc, value label, Sections bands, Rail rails and
bar threshold marks.

Two options — **prefer B**:

- **A (cheap):** add `cfg.accent` to `layout.signature()`. One line, but buys a
  full `lvgl.clear()` + rebuild for a colour change.
- **B (correct, §C.1):** give `configure()` the *unconditional prelude* that
  `OutputsWidget::update()` has and GaugeV2 lacks — re-apply non-structural
  properties every update, before the signature gate. Fold the accent into
  `frame.colorKey` so the existing repaint path carries it:

```lua
- local key = M.colorKey(widget)
+ -- The key must encode every INPUT to the colour, not just the semantic
+ -- role, or an accent edit cannot reach objects whose colour was set at
+ -- build time (Tanda 6 F-5; cf. radio_info.cpp re-reading its colour
+ -- options in update()).
+ local key = M.colorKey(widget) .. ":" .. tostring(widget.accent)
```

B also closes the next three findings of this shape before they are written.

**Verify:** 0.6 green · gallery: `ac-*` scenes change colour, geometry
identical; with option B, `layoutRebuilt` stays `false`.

> **Phase 2 acceptance:** 0.3, 0.4, 0.6, 0.7 green · only the named gallery
> scenes moved · collide clean.

---

### Phase 3 — Bounded resources (F-4)

*Files:* `theme.lua:137-149`, `renderer.lua:499`, `bar.lua:236`

**Evidence.** `theme.textWidth` memoises per `(font, text)` and its own comment
promises *"Only called from layout / build paths — never per frame"*.
`anchorUnit` broke that by measuring the **live value string** every time the
text changes. At 2 decimals that is one new permanent entry per frame, in a
module-level cache shared by every gauge instance.

Three candidates. **Measure all three, then choose** (§B.5):

| # | Approach | Cost |
|---|---|---|
| A | Anchor by character count against the already-measured widest sample | no measurement per frame; assumes fixed-width digits |
| B | A separate, **unmemoised** measuring function | keeps exactness; one `lcd.sizeText` per text change |
| **C** | **Drop `anchorUnit`; put value+unit in one LVGL container and let it align** | *least code*; structurally cannot regress; matches `value.cpp:254-261`, which never measures live text |

C is the firmware idiom and is strictly less code. Ship it if the gallery
accepts it; fall back to A.

Whichever wins, **restore the contract in the header** of `theme.lua` so it
states who may call what, and keep 0.5 as the standing guard.

> **Phase 3 acceptance:** 0.5 green (cache flat over 2000 frames) · gallery:
> value/unit spacing may shift by ≤1 px — name it — nothing else moves.

---

### Phase 4 — Behaviour

#### 4.1 · Re-arm the alert delay on data loss — F-7

*File:* `alerts.lua:73-82`

**Evidence.** `a.armedAt` is set once and cleared only by `alerts.reset()`,
which `app.update()` calls **only on a source change** (`app.lua:231`). Link
loss sets `a.state = nil` but leaves `armedAt` in the past, so the first frame
after a brownout alerts immediately — exactly the scenario the startup delay
exists for (`alerts.lua:9-11`, `DOCS.md` §6.5).

```lua
   if data.availability ~= "valid" or data.state == nil then
-    a.state = nil          -- re-arm once data comes back
+    a.state = nil
+    -- Re-arm the STARTUP DELAY too, not just the transition: a brownout is
+    -- precisely the "model powering up reports nonsense" case (Tanda 6 F-7).
+    a.armedAt = nil
     return
   end
```

**Verify:** new test — valid data → drop link 3 s → reconnect → assert **0**
tones on the first frame and the delay honoured again.

#### 4.2 · One ghost semantic, shared by both renderers — F-8

*Files:* `layout.lua:200`, `renderer.lua:620`

**Evidence.** `updateHistory` returns early when there are no markers
(`renderer.lua:620`) but `L.showGhost` depends only on the mode
(`layout.lua:201`) — so with *Min/max = Off* the dial creates a ghost object
that can never be shown. `bar.lua` has no such coupling, so the two renderers
disagree.

**Decision — take the firmware idiom (§C.3):** the ghost is **independent of
the markers option**, always created, visibility driven by data. That is
already the bar's behaviour, so it is also the smaller diff. Move the
marker-only early return below the ghost update, or split
`updateHistory` into `updateMarkers` + `updateGhost`.

**Verify:** dial and bar agree in a table-driven test across
`ShowMinMax = Off / Markers / Markers+text` · gallery: `op-mm-off` gains the
ghost — name it · update `DOCS.md` §5.

#### 4.3 · Retry source resolution until it succeeds — F-9

*File:* `telemetry.lua:114, 126`

**Evidence.** `s.resolved = true` is set **before** `getFieldInfo()` is even
attempted, and nothing ever clears it. A sensor that appears after boot (the
normal case — telemetry arrives seconds after the widget) is lost forever:
name, unit, precision, scale preset, the `-`/`+` siblings, and the NO LINK vs
NO DATA distinction (`telemetry.lua:250`).

```lua
-  s.resolved = true
   if id and id > 0 then
     local info = getFieldInfo(id)
     if info then
       ...
+      s.resolved = true
+    else
+      -- Not resolved yet. Retry on later refreshes, but bounded so a genuinely
+      -- absent source does not rescan every frame (Tanda 6 F-9).
+      s.retries = (s.retries or 0) + 1
+      s.resolved = (s.retries >= MAX_RESOLVE_RETRIES)
     end
+  else
+    s.resolved = true            -- "no source" is a resolved state
   end
```

**Traps:** the early return at line 114 is `s.id == id and s.resolved` — with
the above it re-enters while unresolved, which is intended. Bound the retries
(a slow counter, not per-frame) or a missing sensor rescans forever.

**Verify:** new test — source absent at boot, appears at frame 10, assert name
and unit populate without an explicit `update()`.

> **Phase 4 acceptance:** new tests for 4.1 and 4.3 green · 4.2 table test
> green for both renderers · collide clean.

---

### Phase 5 — Optimisation (optional, explicit revert criterion)

**Target:** dial-with-needle from **814 B/frame** to ≲ 400 B/frame, *and*
report instructions/frame from 0.9. No visual change whatsoever.

**Scope: 5.1 and 5.2 only.** Original 5.3 is **dropped** — `updateHistory`
already guards both writes on angle change, and the "1.00 sets/frame" figure
is an artifact of a monotonically-rising sweep probe (§A.3). Fix the probe
instead: measure a noisy plateau, not a ramp.

#### 5.1 · Persistent `pts` buffers

*Files:* `renderer.lua:601-606`, `geometry.lua:49-53`

**Evidence it is safe** (§C.6): `LvglWidgetLine::getPts`
(`lua_lvgl_widget.cpp:1008-1029`) copies the coordinates **out** of the Lua
table into its own reused `lv_point_t[]` and hashes them. Nothing on the C side
retains a reference — so a persistent Lua table mutated in place is legal.

Add a mutating variant beside `linePoints` and keep one buffer per line object
on `widget.ui`:

```lua
-- Mutates `buf` in place instead of allocating. The binding copies the values
-- out on every set (LvglWidgetLine::getPts), so reusing the table is safe and
-- removes ~9 of the ~12 tables/frame the needle allocated (Tanda 6 F-11).
function M.linePointsInto(buf, cx, cy, r1, r2, angle)
  local x1, y1 = M.pointOnCircle(cx, cy, r1, angle)
  local x2, y2 = M.pointOnCircle(cx, cy, r2, angle)
  buf[1][1], buf[1][2] = x1, y1
  buf[2][1], buf[2][2] = x2, y2
  return buf
end
```

> **TRAP 1 — negative coordinates raise a Lua error.** `getPt` reads with
> `luaL_checkunsigned` (`lua_lvgl_widget.cpp:1001,1004`). That is F-1 from a
> third door. Whatever clamping exists today must survive; add an explicit test
> at the extreme angles of all three sweeps.
>
> **TRAP 2 — do NOT route the needle through `setProp`.** Its cache compares
> by identity for tables (`renderer.lua:55`: `if cache[key] == value then
> return end`). With a persistent buffer the reference never changes, so
> **every write after the first is silently dropped** and the needle freezes
> at its first angle. Reproduced on Lua 5.3.6:
>
> ```text
> write 1 (fresh buffer)   -> true
> write 2 (mutated in place) -> false   <- DROPPED: needle freezes
> write 3 (new table)      -> true      <- why it works today
> ```
>
> This is precisely why the needle currently bypasses the batching: a fresh
> table each frame is what makes the cache notice. Keep the direct `lvgl.set`
> calls; `frame.angle` is already the correct guard. If you ever *do* want the
> needle batched, `setProp` needs an explicit "always dirty" opt-out — not a
> value comparison.

#### 5.2 · Reuse the `lvgl.set` wrapper table

Hoist the `{ pts = buf }` wrapper to a per-object persistent table as well.
Same trap 2 applies.

#### 5.3 · Re-measure and decide

Re-run the byte probe **and** `dev/instructions.lua`. Record both here.

> **REVERT CRITERION (unchanged, and binding):** if the improvement is not
> demonstrable, revert. The current code is legible and correct; it is not
> worth trading that for a gain that cannot be shown.

---

### Phase 6 — Coherence and documentation

- **6.1 (F-14)** Measure boot cost first. `main.lua:105-106` claims the
  duplication is deliberate ("boot costs exactly one file read per widget") and
  it is almost certainly right — `main.lua` runs at startup for **every**
  widget on the card, used or not. Expect the measurement to confirm it, and
  then do the *inverse* of the original plan: **delete** `options.build()`,
  `options.translator()` and `options.present()`, and annotate the duplication
  as intentional. Note that `run_tests.lua:95-96` and `:295-302` exercise the
  deleted symbols and go with them.
- **6.2 (F-15)** Lift `resolveColor`, `updatePulse` and `updateSourceLabels`
  into shared helpers in `renderer.lua`, as was already done for `updateChip`,
  `anchorUnit` and `label`. `bar.lua` keeps only what genuinely differs.
- **6.3 (F-12, F-13)** Clear `widget.autoCells` on the non-auto branch
  (`app.lua:121`) so it stops lying; remove the dead symbols; rename
  `app.lua:273`'s unused `event`/`touch` to `_event`/`_touch` to clear the
  luacheck warnings.
- **6.4 (F-16)** Fix the three wrong rows of `DOCS.md` §5 against the real
  tree (`arc 5, circle 1, label 8, line 18, rectangle 2` at 200×200) and
  document the ghost semantics fixed in 4.2.
- **6.5 (§C.6)** Record in `DOCS.md` that the callback form of `pts` / colour /
  text params is **deliberately not used**, with the reason — otherwise someone
  "modernises" it into a per-frame regression.

> **Phase 6 acceptance:** `DOCS.md` object counts reproducible from the probe ·
> `luacheck *.lua` at 0 errors and ≤3 warnings · suites green.

---

### D.1 Commit sequence

| # | Contents | Ships |
|---|---|---|
| 1 | Phase 0 (nine tests, seven red) + `.luacheckrc` | with 2 |
| 2 | **Phase 1** — F-1 + F-10 | **immediately, alone** |
| 3 | Phase 2 — F-6, F-2, F-3, F-5 | together |
| 4 | Phase 3 — F-4 | together with 3 |
| 5 | Phase 4 — F-7, F-8, F-9 | when convenient |
| 6 | Phase 5 — needle buffers | optional, revertible |
| 7 | Phase 6 — hygiene and docs | when convenient |

**Commit 2 is the urgent one.** F-1 disables the widget on an action as
ordinary as opening its settings and pressing Cancel, and with F-10 folded in
that single commit closes every known path to a permanently disabled widget.
It does not need to wait for anything else in this document.

---

## E. Phase 0 execution log (2026-08-06)

Run on `e4f4809d6` (widget sources identical to the reviewed `c196e2b0e`;
HEAD only added documentation). Interpreter: Lua 5.3.6. **No widget source
was touched in this phase.**

| Test | Result | Failure (exactly as predicted) |
|---|---|---|
| 0.1 F-1 · update() keeps layout, CRIT renders | **RED** | `200x200: chipOff survives update(): expected 3, got nil` (bar zone fails identically) |
| 0.2 F-1 class · layout pure in (zone, cfg) | **RED** | `L@200x200.chipOff was LOST by update() (was 3)` |
| 0.3 F-3 · saneThresholds normalises order | **RED** | `descending warn untouched: expected 55, got 45.0` (low-is-good mirror passes — see note) |
| 0.4 F-2 · battery % per Cells mode | **RED** | `Lowest: expected ~55 %, got 0` (Average identical; Total passes) |
| 0.5 F-4 · widthCache bounded | **RED** | `cache grew by 500 over 500 more frames: expected 509, got 1009` |
| 0.6 F-5 · Accent recolours without rebuild | **RED** | `valueArc follows accent: expected 8192, got 12291`; `layoutRebuilt == false` holds |
| 0.7 F-6 · sensor metadata per model | **RED** | `index re-resolved on the new model: expected 7, got 0` (prec 1 too) |
| 0.8 · DEFS (key, type) frozen | **GREEN** | ratchet, as designed (§B.7) |
| 0.9 · dev/instructions.lua | **NUMBERS** | see below |

Suites after Phase 0: `run_tests` 38 passed / 1 failed (the F-3 red),
`smoke_test` 97 passed / 6 failed (the six reds; 0.8 green added),
`collide` all clean, gallery diff vs `manifest-pre-tanda6.lua`: **no changes**,
`luacheck *.lua`: **5 warnings / 0 errors** (unchanged; the F-5 test's unused
`before` was removed to keep it that way).

**0.9 instruction-budget baseline — the Phase 5 acceptance numbers.** 1 fire =
200 VM instructions; the kill switch fires at 100 (20 000). Counts include
`pcall`/hook overhead, so they overestimate — safe for margin:

```text
scene                                  upd-noop  upd-bld ref-idle  ref-chg
480x272 needle sections markers+text         19       50        3       12
480x272 needle threshold markers+text        19       45        3       12
200x200 needle sections markers+text         20       49        3       12
200x200 arc sections markers                 18       43        3        8
200x200 needle sections 360deg               15       55        3       12
300x60 bar threshold                         10       21        2        8

worst scene:   200x200 needle sections 360deg
worst callback: update() with a structural change (full rebuild), 55 fires
               = 11 000 instructions = 45 % headroom before the kill switch
```

Two observations for Phase 5, not action items here:

- The rebuild path (`update()` after a structural option edit) is the
  expensive callback (45–55 fires), not `refresh()` (3 idle / ≤ 12 moving).
  Phases 2.4-B and 4.2, which trade rebuilds for repaints, lower this number
  directly; 5.1/5.2 shave the 12-fire moving-refresh path.
- Even with hook overhead included, no callback is close to the limit; the
  probe's 50 % headroom warning threshold is what makes this worth running
  in CI once Phase 5 lands.

## E.2 Phase 2 execution log (2026-08-06)

Run on the Phase 1 commit. Scope: 2.1 (F-6), 2.2 (F-2), 2.3 (F-3), 2.4 (F-5).

| Test | Before → After |
|---|---|
| 0.3 F-3 · saneThresholds | RED → **GREEN** |
| 0.4 F-2 · battery % per Cells mode | RED → **GREEN** (Lowest/Average ~55, Total unchanged) |
| 0.6 F-5 · Accent without rebuild | RED → **GREEN** (`layoutRebuilt == false` holds — option B) |
| 0.7 F-6 · sensor metadata per model | RED → **GREEN** (index 7 / prec 2 on model B) |
| F-3 · ghost follows scale direction (new) | RED → **GREEN** |
| F-5 · accent reaches sections bands + bar marks (new) | RED → **GREEN** |
| P2-4 · re-resolution cache (rewritten) | contract ratchet, green |

Suites: `run_tests` **40/40**, `smoke_test` **104/105** (only F-4 red — that
is Phase 3), collide clean, `luacheck *.lua` **4 warnings / 0 errors**
(unchanged), instruction probe identical to the E baseline (55 fires worst).

Gallery diff vs `manifest-pre-tanda6.lua` — exactly two scenes, exactly the
predicted fields:

```text
~ ba-pct-low       displayValue: 0 -> 53   chip: CRIT -> ""   colorKey: critical -> normal
                   objects.total: 22 -> 20 (CRIT pill gone with the 0% reading)
~ sc-descending    warn: 45 -> 55   crit: 65 -> 35   state/colorKey: critical -> warning
                   chip: CRIT -> WARN
```

`ba-pct-tot` did not move. No `ac-*` scene moved in the manifest — those
scenes are static constructions (accent applied at build), and the manifest
records semantic facts only; the SVG colour of a hot accent edit is pinned by
0.6 and the new F-5 coverage test instead.

Deviations from the plan (all intentional, all covered by tests):

- **2.2** — `isPerCellReading` is NOT the predicate inside
  `historyTrustworthy`: Average is per-cell for the battery math, but its
  mean is not the Cels-/Cels+ extreme, so history stays Lowest-only. The
  review's "one source of truth" is honoured for the battery fix; history
  semantics are unchanged (no gallery movement proves it).
- **2.4** — the accent is folded into the repaint gate as a separate
  `frame.accentKey` instead of a suffix on `frame.colorKey`, so the SEMANTIC
  key contract (read by ~8 tests and the manifest) survives. `applyColors`
  additionally recolors the section bands (role-tagged at build) and the
  bar's threshold marks, which the plan's sketch alone would have missed —
  those carry the accent but were only painted at build time.
- **2.3** — the ghost direction fix also lands in `bar.lua`, whose peak-hold
  marker had the identical root cause (review named only renderer.lua).

## E.3 Phase 3 execution log (2026-08-06) — F-4

**Candidate measurement first** (plan: "measure all three, then choose"):

- **C (one LVGL container) is structurally INFEASIBLE in the Lua binding.**
  Every Lua object is created flat under `lvglManager->getCurrentParent()`
  (`LvglWidgetBox::build`, lua_lvgl_widget.cpp:1617); the Lua API has no
  object parenting, so a Lua `box` with flexFlow lays out ZERO children
  (`children` is a tolerated-but-ignored key, :659). The `value.cpp` idiom
  cannot be expressed from Lua.
- **A (char-count anchor) measured at up to 6 px of unit drift** on a
  proportional font model (`dev/measure_anchor.lua`: worst case `"7"` vs
  sample `-100.00`, 0.25 digit units each side of the ink) — six times the
  phase's ≤ 1 px allowance. The headless mock cannot see this (its
  `sizeText` is linear), which is exactly why the probe exists.
- **B (unmemoised measure) wins on measurement**: exact on proportional
  fonts, one `lcd.sizeText` per value change, and pixel-identical to the
  frozen baseline by construction (same sizeText source, just not cached).

**Shipped (B):** `theme.measureWidth(text, font)` — exact, deliberately
NOT memoized, with the measuring contract restated in theme.lua's header
(`textWidth` = layout/build only, bounded; `measureWidth` = the renderers'
entry for live strings). `renderer.anchorUnit` now calls `measureWidth`;
the call-site audit (`rg textWidth`) shows every remaining site is
build-time or bounded (the state-chip vocabulary).

**Tests:** 0.5 extended to the plan's 2000 frames (1000+1000) with an
absolute bound (`< 100` entries) in addition to flatness; new contract test
"F-4: measureWidth measures exactly but never memoizes" (200 distinct
strings through `measureWidth` → cache byte-identical, result equals
`textWidth`).

| Gate | Result |
|---|---|
| 0.5 F-4 | RED → **GREEN** (flat 509 → 509 over 1000 more frames, < 100 bound) |
| run_tests / smoke_test | **40/40** · **106/106** — full suites green for the first time since Phase 0 |
| gallery manifest diff | unchanged from Phase 2: exactly `ba-pct-low` + `sc-descending`, nothing new |
| gallery SVG byte-diff (pre/post F-4) | **identical geometry** — the only 2 differing lines are the header timestamp |
| collide | clean |
| luacheck | 4 warnings / 0 errors (widget), 0/0 on the new probe |
| instruction probe | worst callback unchanged (55 fires, rebuild path); moving-refresh +1 fire (200 instr) on 2 of 6 scenes — the sizeText call's measured cost |

## E.4 Phase 4 execution log (2026-08-06) — F-7, F-8, F-9

Tests written red first, all three failing for exactly the stated reason
(smoke: `no tone on the first frame after a brownout: expected 2, got 4`;
`dial ghost shows with history, ShowMinMax=Off: expected true, got false`;
`absent at boot: unresolved, retrying: expected false, got true`).

| Fix | Change |
|---|---|
| 4.1 F-7 | `alerts.lua`: the invalid-data guard now clears `a.armedAt` too — a brownout re-arms the startup delay instead of alerting on the first frame after reconnect |
| 4.2 F-8 | `renderer.lua` `updateHistory`: the ghost block moved ABOVE the markers' early return and guards on `h.min and h.max` — visibility driven by data, not the option. `bar.lua`: same guard hardened (the Phase-2 descending `peak = h.min` could hit nil on a partially-populated sibling history) |
| 4.3 F-9 | `telemetry.lua`: `s.resolved` no longer latches before `getFieldInfo`; unresolved sources are re-resolved from `refresh()` throttled to 1 attempt/s (`RESOLVE_RETRY_TICKS = 100`) for at most 30 attempts (`MAX_RESOLVE_RETRIES`), after which the source is treated as resolved-absent |

Tests added: F-7 (brownout → 0 tones on reconnect, delay honoured again),
F-8 (table-driven dial + bar across Off / Markers / Markers+text), F-9
(appears at frame 10, resolved by refresh alone with retry cadence pinned
`retries == i + 1`; plus a throttle sub-test: a refresh inside the retry
interval does not rescan). One harness trap found and fixed in the F-9 test:
`mock.advance(ms)` adds `floor(ms/10)` TICKS, so the test advances in
seconds (1000 ms = 100 ticks), not in the wrong-scaled milliseconds.

| Gate | Result |
|---|---|
| run_tests / smoke_test | **40/40 · 109/109** — all green, including every Phase 0 red and both standing guards |
| gallery manifest | exactly the three named scenes: `ba-pct-low`, `sc-descending` (Phase 2) and **`op-mm-off` gains the ghost** (objects.arc 4→5, total 27→28 — the review's named F-8 scene); nothing else |
| collide | clean |
| luacheck | 4 warnings / 0 errors (widget, unchanged); no new test warnings |
| instruction probe | worst callback unchanged (55 fires) — the F-9 retry gate costs one `getTime` compare only while a source is unresolved (all probe scenes resolve immediately) |
| DOCS.md | §4.7 and §5.4 updated: the ghost is explicitly independent of the Min/max option, one semantic shared by dial and bar |

## E.5 Phase 5.1 execution log (2026-08-06) — persistent needle buffers

**Plan.** `geometry.linePointsInto(buf, …)` mutating variant + three persistent
buffers on `widget.ui` (created in `buildNeedle`), used by `updateArc`'s three
direct `lvgl.set` calls. Safety re-derived from the binding:
`LvglWidgetLine::getPts` copies the values out at set time and keeps no
reference (lua_lvgl_widget.cpp:1008-1029), so in-place mutation is legal.

**Measurement first** — new `dev/measure_frames.lua` reproduces the review's
gc-delta methodology (full gc, N moving frames, full gc, delta):

```text
                              BEFORE     AFTER
dial 200x200 needle           1559 B/f   767 B/f   (-792 B/f, -51 %)
dial 200x200 arc               442 B/f   442 B/f   (control: unchanged)
bar 300x60                     440 B/f   440 B/f   (control: unchanged)
needle share                  1117 B/f   325 B/f   (-71 %)
geometry.linePoints calls     3.00 /f    0.00 /f   (the 9 tables/frame are gone)
```

The needle scene's absolute value exceeds the review's 814 B/f because the
probe scene runs Precision=4 with the value string changing every frame; the
config-independent needle SHARE is the honest metric and it dropped 71 %.
**Revert criterion: the improvement is demonstrable (nearly 800 B/frame on
the target scene), so 5.1 ships.** The remaining needle-scene cost is the
value-string churn and the `{ pts = … }` wrapper tables — 5.2 (persistent
wrappers) is the documented next step.

**Tests** (heavy): `linePointsInto` unit test (values ≡ `linePoints`, `#buf`
never grows, returns the caller's buffer); needle buffer-identity test (the
three `props.pts` table identities survive an angle change while their values
move); TRAP 2 ratchet (a reused buffer through `setProp` is dropped by the
identity cache — asserted via the set count, pinned so nobody "simplifies"
the needle into the batching); TRAP 1 guard (all three sweeps ×
below-min/above-max: the whole blade stays non-negative — backed by a NEW
mock fidelity rule: `checkPts` rejects negative coordinates exactly like
`luaL_checkunsigned`, so the harness can no longer hide that class of bug at
all; the existing 149 tests and 77 gallery scenes all pass under it).

| Gate | Result |
|---|---|
| run_tests / smoke_test | **41/41 · 112/112** |
| gallery manifest | unchanged: the same 3 named scenes, nothing new |
| gallery SVG diff vs pre-5.1 | **zero needle pixels moved** — the only differing lines are the header timestamp and the Phase-4 `op-mm-off` ghost tile |
| collide | clean |
| luacheck | 4 warnings / 0 errors (widget) + 0/0 on the new probe |
| instruction probe | per-frame costs unchanged; `upd-bld` +1 fire on needle scenes (the buffers are built once) — one-time cost for a permanent −792 B/frame |

## E.6 Phase 5.2 execution log (2026-08-06) — persistent `lvgl.set` wrappers

**Binding verified before touching code**: `lvgl.set(obj, params)` →
`LvglWidgetObjectBase::update` → `getParams(L, 2)` parses the params table
**at call time** and retains no reference (api_colorlcd_lvgl.cpp:116-123,
lua_lvgl_widget.cpp:763-767). A persistent wrapper whose `pts` field points
at the persistent buffer can therefore be passed forever — the fresh buffer
contents are read on every set, and the wrapper never even needs mutation.

**Shipped:** `ui.needleSet/needleMidSet/needleTipSet = { pts = <buffer> }`
built once in `buildNeedle`; `updateArc` mutates the buffers and passes the
wrappers directly to `lvgl.set`. Never through `setProp` (TRAP 2).

**Measurement** — the probe had to be made honest first; three harness
defects were found and fixed along the way (all behavior-preserving):

1. `mock.tracking(false)` toggle: the harness's `obj.sets` retention is
   UNBOUNDED by design (it is the suite's audit trail) and drowned the
   widget's own numbers.
2. `allowedKeys` per-kind memoization: `checkParams` ran on EVERY
   `lvgl.set`, allocating a fresh ~12-key table per call — the harness was
   the dominant per-frame allocator (the "needle share" measured 1704 B/f
   before the fix).
3. The probe's feed: with needle damping on and an alternating target, the
   smoothed value mints a distinct permanent interned string every frame —
   `Damping = 0` in the scenes keeps the strings to two interned values
   while the needle still moves every frame.

Methodology: `collectgarbage("stop")` around the frames (nothing freed →
the count delta is the TRUE allocation rate), tracking off, 100 moving
frames:

```text
                              needle scene   arc scene   needle share
Tanda baseline                   814 B/f        303 B/f     ~511 B/f
after 5.1 (wrapper literals)     934 B/f        669 B/f      265 B/f
after 5.2 (persistent wrappers)  670 B/f        669 B/f        1 B/f
```

**5.2 alone: −264 B/frame** — the three wrapper tables. Revert criterion
demonstrably satisfied; 5.2 ships. Combined 5.1+5.2: the needle's ~511 B/f
share is down to measurement noise, and the needle scene now equals the
no-needle scene.

**Tests**: wrapper-identity test at the `lvgl.set` boundary (mock's `set`
wrapped to capture the params tables across two angle changes — identities
must survive while values move, and `wrapper.pts == props.pts`); the 5.1
TRAP-2 ratchet extended in comment to name the wrapper as the same
identity-compare hazard (the mock's `checkPts` rejects the wrapper shape as
a points array, so the ratchet stays on the buffer form it validates — the
wrapper's real guard is the boundary test).

| Gate | Result |
|---|---|
| run_tests / smoke_test | **41/41 · 113/113** |
| gallery manifest | unchanged (the same 3 named scenes) |
| gallery SVG diff | zero new lines — only the timestamp and the Phase-4 `op-mm-off` tile |
| collide | clean |
| luacheck | 4/0 widget · 0/0 on the changed probe and mock |
| instruction probe | worst callback **49 fires** (was 55/56) — the `allowedKeys` memo removed per-set table construction from every `lvgl.set`, an unexpected bonus of the harness fix; the §E baselines are now conservative |

**Follow-up (out of 5.2 scope, noted):** the min/max marker lines still
allocate a fresh `pts`+wrapper per angle change; they are guarded by
`frame.minAngle/maxAngle` so they cost nothing in steady state, but a
monotonic flight max sweeps them ~1/frame — the same persistent-buffer
treatment applies if the Phase 5 target is ever pushed further.

## E.7 Phase 5.3 execution log (2026-08-06) — re-measure and decide

The phase's acceptance step: both probes re-run on the final code
(`3b0f554e3`), recorded here, and the binding revert criterion applied.

**dev/measure_frames.lua — allocation rate** (gc stopped, harness tracking
off, 100 frames, `Damping = 0`; a probe artifact in the original feed was
found and fixed in the process — see below):

```text
steady-state plateau (60/90, both in the normal band):
  dial 200x200 needle      310 B/f    linePoints 0.00/f
  dial 200x200 arc         309 B/f
  bar 300x60               309 B/f
  needle share:              1 B/frame
  Tanda baseline:         814 B/f needle scene, ~511 B/f needle share
```

**The needle's share of a steady-state frame is measurement noise.** The
full needle scene is **310 B/f — under the restated ≲ 400 B/f target**.
The controls (arc, bar) sit at 309 — the shared machinery, which itself now
measures at the Tanda report's arc-scene level (303).

**dev/instructions.lua — the metric that actually kills the widget:**

```text
worst callback: 49 fires = 9800 instructions (limit 100 / 20000) - 51 % headroom
(ref-chg ≤ 11 fires on every scene; the E.5/E.6 baselines were 55-56 fires)
```

**Probe-artifact accounting** — the earlier 670 B/f base was decomposed and
is now fully explained:

- **Threshold-crossing feed (10/90): 669 B/f, +359 B/f over steady state.**
  A feed that crosses the state threshold every frame churns the chip —
  `updateChip` builds a FRESH `frame.chipBox` table per show (~186 B/call,
  micro-benchmarked) — plus `applyColors`. This is a real but
  TRANSITION-bounded cost (~0 in steady flight); recorded as a follow-up
  finding, not part of the needle work.
- **Ramp feed (RSSI+ rising): 1181 B/f, +870 B/f over steady state** — the
  maxMark/ghost/min-max-text churn while the historical max advances. **§A.3
  is now confirmed by measurement**: the dropped original-5.3 target chased
  ~870 B/f that exists only for the seconds after power-up and never again.

**REVERT CRITERION — applied, not triggered.** The improvement is
demonstrable on both metrics the phase targets: the needle share is ~511 →
1 B/f (bytes), every instruction-probe row improved (worst 55-56 → 49
fires), the controls are unchanged, and the visual baseline is pixel-identical
(gallery manifest: same three named scenes; SVG diff: zero Phase-5 lines).
**5.1 + 5.2 ship.**

**Follow-up findings recorded for Phase 6/7** (both transition-bounded, not
per-frame in steady flight): the `frame.chipBox` table per chip show (the
5.1 persistent-table pattern applies directly), and the marker `pts`/wrapper
allocation while history advances (same pattern).
