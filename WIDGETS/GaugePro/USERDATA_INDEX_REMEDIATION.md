# GaugePro — `attempt to index a userdata value` remediation plan

Status: **root cause confirmed, tested, not yet fixed in code**
Affected: bar style (Continuous + Dual-rail faces) and, in the same class, the dial's
Sections mode and the bar's threshold marks.
Firmware: EdgeTX (this repo). Widget: `WIDGETS/GaugePro`.

---

## 1. Summary

GaugePro stores per-object Lua state directly **on the LVGL objects** it creates
(e.g. `band.role = range.role`). On real EdgeTX firmware, `lvgl.rectangle{}` and
every other `lvgl.*` constructor return a **full userdata** whose metatable exposes
only `__index`, `__gc` and methods — there is **no `__newindex`**. Assigning any
field to such an object raises `attempt to index a userdata value` at runtime.
That is exactly the reported Alert 1 (`bar_faces.lua:239`) and the `?:0` Alert 2.

The entire test harness (`tests/mock_env.lua`) returns **plain Lua tables** from
the `lvgl.*` constructors, so every one of the 270 tests passes while the radio
crashes on the first paint of the affected faces.

## 2. Symptoms

| Alert | Reported message | Where it fires | Root write |
|---|---|---|---|
| 1 | `ERROR in refresh(): /WIDGETS/GaugePro/bar_faces.lua:239: attempt to index a userdata value (local 'band')` | First `refresh()` of the Continuous face with color mode **Rail** or **Sections** | `band.role, band.baseOpacity = range.role, opacity` |
| 2 | `ERROR in refresh(): ?:0: attempt to index a userdata value` | Same class, raised through the C lvgl path so no Lua source line is attached (typically the second failing write of the same refresh, or a second instance) | `slice.fromPosition, ... = ...` (gradient) or `track.negative = ...` (dual-rail) |

The `?:0` in Alert 2 means the failing instruction had no attachable Lua source
position. That happens when the error is raised from inside the C++ lvgl layer
(`luaL_error`, `lua_widget.cpp:456-472`) rather than from a direct Lua field
assignment — the same userdata-indexing class, different stack context. Both
alerts share one mechanism and one fix.

## 3. Root cause (with firmware evidence)

1. `lvgl.rectangle{}` returns a userdata. The binding creates a full userdata
   holding a `LvglWidgetObjectBase*` and sets the registry metatable:
   - `radio/src/lua/lua_lvgl_widget.cpp:356-377` (`getRef` / `push`)
   - `radio/src/lua/api_colorlcd_lvgl.cpp:452` (`rectangle` entry) and `:564-617`
     (`lvgl_base_mt` / `lvgl_mt`, declared with `LROT_MASK_GC_INDEX`).

2. The metatable has **no `__newindex`**. A grep for `NEWINDEX` across
   `radio/src` finds it only in the Lua VM itself (`thirdparty/Lua/src/lvm.c`)
   and never in the lvgl bindings. Lua semantics: writing `obj.field = v` to a
   userdata whose metatable lacks `__newindex` raises
   `attempt to index a userdata value` (reads of unknown fields return `nil`,
   silently — so even the *read* sites would return `nil` on a real radio).

3. Metadata cannot be smuggled through the build/`set` params table either:
   `LvglWidgetObjectBase::parseParam` raises `Invalid property '%s'` for any key
   it does not recognise (`radio/src/lua/lua_lvgl_widget.cpp:659-661`).

4. The widget already contains the correct pattern: `renderer.setProp`
   (`renderer.lua:47-89`) keeps a per-object cache **keyed by the userdata** in
   `widget.frame.props` and only ever sends known LVGL keys through `lvgl.set`.
   `bar_faces.lua` instead reaches *into* the objects, which is the defect.

5. The harness cannot see the bug: `tests/mock_env.lua:112-127` `makeObject`
   returns a plain table with the params copied in, so reads and writes of
   arbitrary fields succeed. `run_tests.lua` (70 tests) and `smoke_test.lua`
   (200 tests) are both green while the radio fails.

## 4. Reproduction

`C:\Users\bulto\AppData\Local\Temp\kilo\repro_gaugepro_bar.lua` (stock Lua 5.3)
loads the real `geometry/ranges/theme/renderer/bar_faces` and swaps the mock's
`lvgl` for EdgeTX-faithful objects — full userdata (FILE\*) with
`__index`/`__gc` and no `__newindex`:

```
continuous face build (RAIL colour) => ERROR: bar_faces.lua:239: attempt to index a FILE* value (local 'band')
continuous face build (GRADIENT)     => ERROR: bar_faces.lua:305: attempt to index a FILE* value (local 'slice')
```

Line 239 is byte-for-byte the Alert 1 site. The same repro with the mock's plain
tables completes without error (as the green suites show).

## 5. Inventory of affected object-field writes (and reads)

### `bar_faces.lua` (bar style)

| Site | Object | Fields written | Face / mode | Read back at |
|---|---|---|---|---|
| `:239` | `band` (rect, reference rail) | `role`, `baseOpacity` | Continuous, Rail/Sections | `:776-779` |
| `:305-310` | `slice` (rect, gradient slice) | `fromPosition, toPosition, baseX, baseY, baseW, baseH, paintX, paintY, paintW, paintH, barShown` | Continuous, Gradient | `:529-590`, `:614`, `:791` |
| `:482-485` | `slice` | `barShown` | Continuous, Gradient | — |
| `:494-509` | `slice` | `paintX, paintY, paintW, paintH` | Continuous, Gradient | — |
| `:528-560`, `:580-590` | `slice` | `paintY, paintH, paintW` | Continuous, Gradient | — |
| `:788-792` | `slice` | `gradientT` | Continuous, Gradient | `:795-798` |
| `:1505` | `track` (rect, dual track) | `negative` | Dual-rail | `:1529` |

### `bar.lua` (bar style)

| Site | Object | Fields written | Mode | Read back at |
|---|---|---|---|---|
| `:123` | `m` (line, threshold mark) | `role` | Continuous, non-static colour with marks | `:386` |

### `renderer.lua` (dial style — same class, separate symptom)

| Site | Object | Fields written | Mode | Read back at |
|---|---|---|---|---|
| `:176` | `sec` (arc, section band) | `role` | Dial, Sections | `:551` |

Notes:
- The segmented faces (blocks/hex/ticks/steps) are clean: their per-cell state
  already lives in the Lua `cell` tables built by `appendCell` (`bar_faces.lua:1284-1295`).
- `ui.*` names and `frame.*` caches are fine — they are Lua tables.

## 6. Remediation design

**Principle:** treat LVGL objects as opaque handles. All per-object state moves
into parallel Lua tables on `widget.ui`, built alongside the objects in
`build()` and indexed identically. This mirrors the existing `renderer.setProp`
design (`widget.frame.props[obj]`) and the `ui.gradientSlices` /
`ui.faceCells` arrays already in use. No firmware change is proposed — the
binding behaviour is intentional.

Because `rebuild()` (`app.lua:106-112`) replaces `widget.ui` and `widget.frame`
together, the parallel arrays are always rebuilt in the same step as their
objects and can never go stale.

### 6.1 `buildReferenceBands` → rail metadata (fixes Alert 1)

`bar_faces.lua:214-244`. Keep the retained rects in `ui.rails`; add a parallel
`ui.railMeta`:

```lua
-- buildReferenceBands
ui.rails   = {}
ui.railMeta = {}
...
local band = lvgl.rectangle{ ... }
ui.rails[#ui.rails + 1]    = band
ui.railMeta[#ui.railMeta + 1] = { role = range.role, baseOpacity = opacity }
```

`continuousPalette` (`:772-781`) reads `objects.railMeta[i].role` /
`.baseOpacity` instead of `rail.role` / `rail.baseOpacity`.

### 6.2 Gradient slices → `ui.sliceState`

This is the largest surface: 11 fields × ~8 functions. Add one parallel array,
one entry per slice, holding every field the code currently puts on the userdata:

```lua
-- continuousBuild (gradient branch, replaces :305-310)
ui.sliceState = {}
...
ui.gradientSlices[i] = slice
ui.sliceState[i] = {
  fromPosition = t1, toPosition = t2,
  baseX = x, baseY = y, baseW = max(1, w), baseH = max(1, h),
  paintX = x, paintY = y, paintW = max(1, w), paintH = max(1, h),
  barShown = false,
}
```

Then rewrite the slice helpers to take the state (they already receive
`objects`, which is `widget.ui`):
- `showSlice(state, shown)` — `barShown` read/write (`:482-485`).
- `setSliceGeometry(widget, state, x, y, w, h)` — paint fields (`:494-509`).
- `updateGradientPrefix` / `updateGradientIndex` — replace every
  `slice.<field>` read/write with `state.<field>` where `state =
  objects.sliceState[i]` (`:515-626`).
- `continuousPalette` — `gradientT` lives in `objects.sliceState[i]`
  (`:788-792`); `fromPosition`/`toPosition` reads at `:791` move with it.
- `continuousBuild` `ui.pulseTargets` stays as-is (array of the rect userdata).

Sites that never touch object fields (`hideGradient`, `continuousVisible`,
`moveHead`, etc.) are unchanged.

### 6.3 Dual-rail tracks → `ui.dualTrackNeg`

`bar_faces.lua:1505`: `track.negative = negative`. Store alongside:
`ui.dualTrackNeg[i] = negative`. `dualPalette` (`:1526-1531`) reads
`objects.dualTrackNeg[i]`.

### 6.4 Threshold marks → `ui.markRoles`

`bar.lua:123`: `m.role = r.role`; read at `:386`. Add
`ui.markRoles[#ui.marks] = r.role` at build, iterate `ui.markRoles` in the
palette pass (the two arrays always have the same length).

### 6.5 Dial sections → `ui.sectionRoles`

`renderer.lua:176`: `sec.role = r.role`; read at `:551`. Same pattern:
`ui.sectionRoles[#ui.sections] = r.role`, read by index in `applyColors`.

## 7. Harness hardening (so this class can never return)

1. **`tests/mock_env.lua`**: give every object returned by `makeObject` a
   metatable whose `__newindex` rejects any key that is not (a) the object
   kind's allowed LVGL property set (already computed in `allowedKeys`) or
   (b) the harness instrumentation keys (`kind`, `params`, `props`, `sets`,
   `setCount`, `visible`). A rejected write raises
   `attempt to write '<key>' on <kind> (radio: userdata has no __newindex)`.
   This makes `run_tests.lua` and `smoke_test.lua` fail at every site in
   section 5 until the widget is fixed, mirroring the radio exactly.
2. **`tests/smoke_test.lua`**: migrate the assertions that read object fields
   to the new state locations:
   - `:835`, `:888` — `slice.baseW` → `w.ui.sliceState[i].baseW`
   - `:1068` — `mark.role` → `w.ui.markRoles[i]`
   - `:3752` — `s.role` → section role array
   - `:3764` — `m.role` → rail role array
3. Keep the `repro_gaugepro_bar.lua` userdata harness in `dev/` so a CI/radio
   check can run the Continuous build against userdata objects on demand.

## 8. Validation

1. `lua5.3 tests/run_tests.lua ./` — 70/70.
2. `lua5.3 tests/smoke_test.lua ./` — 200/200, now including the hardened mock
   (fails before the fix, passes after).
3. `lua5.3 dev/repro_gaugepro_bar.lua` (userdata lvgl) — no error for Rail,
   Sections, Gradient, and Dual-rail configurations.
4. Manual on-radio: place the widget in bar style, cycle colour mode
   Static → Rail → Sections → Gradient, and both origins; confirm no
   `ERROR in refresh()` overlay.
5. Object-budget suites (`smoke_test` census, `bar_faces` estimates) unchanged:
   the parallel arrays add no LVGL objects.

## 9. Alternatives considered (and rejected)

- **Side table keyed by userdata** (`widget.ui.objState[obj] = {...}`): minimal
  diff, but scatters state per site, adds a hash lookup on hot update paths, and
  is harder to reason about than parallel arrays. Rejected in favour of §6.
- **Smuggling metadata through `lvgl.set`/build params**: impossible — the
  binding raises `Invalid property '%s'` (`lua_lvgl_widget.cpp:660`). Rejected.
- **Reading fields back from the object**: reads of unknown fields return `nil`
  on real userdata, so this cannot work. Rejected.
- **Firmware change to add `__newindex`**: out of scope; the binding is shared
  by every widget and its read-only object contract is deliberate. Rejected.
