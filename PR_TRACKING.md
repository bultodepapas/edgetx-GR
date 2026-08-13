# EdgeTX Pull Request Tracking

Tracking document for pull requests authored by **bultodepapas** in the
official EdgeTX organization repositories.

Last updated: **2026-08-13** for the Gauge Pro and Widget Studio submissions.
Older entries below retain their 2026-08-06 review snapshot unless explicitly
updated.

## Current beta submissions

| Repository | PR | State | CI | Next action |
|---|---:|---|---|---|
| `EdgeTX/edgetx-sdcard` | [#289 — Gauge Dial Pro and Gauge Bar Pro beta](https://github.com/EdgeTX/edgetx-sdcard/pull/289) | OPEN · DRAFT | CodeRabbit success | Keep draft pending physical-radio testing, deterministic visual-evidence rerun and maintainer feedback |
| `EdgeTX/edgetx` | [#7646 — Widget Studio simulator hooks](https://github.com/EdgeTX/edgetx/pull/7646) | OPEN · DRAFT | All compile/test jobs passed; final packaging cleanup failed | Rerun the packaging job or obtain maintainer confirmation that its post-upload artifact-deletion 404 is infrastructure-only |

### [EdgeTX/edgetx-sdcard #289](https://github.com/EdgeTX/edgetx-sdcard/pull/289) — Gauge Pro beta

- **Base / head:** `master` ← `feat/gauge-pro-beta`
- **Scope:** one commit, 23 files; `GaugeDialPro`, `GaugeBarPro` and shared
  `GaugeCore` canonical SD payload only.
- **Excluded deliberately:** legacy combined widget, simulator changes,
  generated visual tooling/evidence, `imgui.ini` and formatter noise.
- **Validation:** 309 Lua tests, static analysis and resource/geometry/motion
  gates passed before packaging; all five color overlays inherit the payload.
- **Status / next step:** Appropriate as a first-public-beta draft. Complete a
  physical color-radio smoke test and repair/rerun deterministic visual
  navigation before marking it ready for final review.

### [EdgeTX/edgetx #7646](https://github.com/EdgeTX/edgetx/pull/7646) — Widget Studio simulator hooks

- **Base / head:** `main` ← `feat/widget-studio-simulator`
- **Scope:** one commit, 13 files; opt-in `WIDGET_STUDIO` simulator automation
  and documentation, independent of the Gauge Pro SD-card contribution.
- **CI:** Documentation, all test matrices and all firmware build matrices
  passed. `Package firmwares` successfully merged and uploaded 19 artifacts,
  then failed while deleting an already-missing source artifact (`404 Not
  Found`).
- **Status / next step:** Keep draft for API/naming feedback. Rerun the failed
  packaging job and confirm it completes cleanly.

## Summary Table

| # | Title | State | CI | Needs Action | Labels |
|---|-------|-------|----|--------------|--------|
| [7613](https://github.com/EdgeTX/edgetx/pull/7613) | fix(simu): force C locale for numeric parsing in simulator | OPEN | ✅ All green | No | `bug 🪲`, `simulator`, `translation` |
| [7612](https://github.com/EdgeTX/edgetx/pull/7612) | fix(sport): add Betaflight Pitch/Roll sensor unit and precision | OPEN | ✅ | **YES** — reply to 3djc feedback | _none_ |
| [7611](https://github.com/EdgeTX/edgetx/pull/7611) | fix(lua): compare float with int strictly in equality | OPEN | ✅ | **Labels requested** — author lacks permission to add them | _none_ |
| [7593](https://github.com/EdgeTX/edgetx/pull/7593) | feat(lua): expose touch enabled state | CLOSED (author) | ✅ | **Consider reopening** | _none_ |
| [7592](https://github.com/EdgeTX/edgetx/pull/7592) | fix(color): make messaging dispatch mutation-safe | CLOSED (author) | ✅ | Review closed decision | _none_ |

---

## OPEN — needs no action

### [#7613](https://github.com/EdgeTX/edgetx/pull/7613) — fix(simu): force C locale for numeric parsing in simulator
- **State:** OPEN · **Created:** 2026-08-03 · **Updated:** 2026-08-06
- **Base:** `main` · **Branch:** `fix/simu-force-c-locale` · **Draft:** no
- **Changes:** +6 / −0 in `radio/src/targets/simu/simulib.cpp`
- **Fixes:** #7453 (simulator fails under non-`C` host locales, e.g. `LANG=es_ES.UTF-8`; `strtof`/`strtod` use `,` decimal separator)
- **CI:** All `Run tests` / `Run builds` / `Package firmwares` **SUCCESS**; CodeRabbit ✅
- **Reviews:** Copilot commented (informational, no blocking issues). No maintainer review yet.
- **Labels:** `bug 🪲`, `simulator`, `translation`
- **Status / Next step:** In good shape, all checks green. Waiting on maintainer review. Nothing to do right now; consider pinging a reviewer if it sits too long.

---

## OPEN — needs action

### [#7612](https://github.com/EdgeTX/edgetx/pull/7612) — fix(sport): add Betaflight Pitch/Roll sensor unit and precision (#7116)
- **State:** OPEN · **Created:** 2026-08-03 · **Updated:** 2026-08-06
- **Base:** `main` · **Branch:** `fix/sport-betaflight-angle-sensors` · **Draft:** no
- **Changes:** +47 / −0 in `radio/src/telemetry/frsky_sport.cpp` and `radio/src/tests/frsky.cpp`
- **Fixes:** #7116 (Betaflight S.Port Pitch `0x5230` / Roll `0x5240` displayed with wrong unit/precision)
- **Review requested from:** `pfeerick` (still pending)
- **Reviews / comments (need to act):**
  - `copilot-pull-request-reviewer` — informational; suppressed a comment about unaligned writes / endianness in the test packet construction.
  - **`3djc` (COLLABORATOR)** — raised 3 concerns (**2026-08-06**):
    1. Don't hardcode sensor IDs — add them to the table in the corresponding `.h` file.
    2. The DIY range `0x5100–0x52FF` is free for anyone; claiming 2 values may collide with others' use.
    3. Suggest the fix belong in Betaflight (use existing `ACCX`/`ACCY` sensor IDs) rather than EdgeTX.
- **Labels:** none (consider adding `bug`/`triage`/`sport`/`telemetry` for visibility)
- **Status / Next step:** ⚠️ **Maintainer feedback is awaiting your reply.** Respond to 3djc: address the sensor-ID table, justify the DIY-range usage, and answer whether Betaflight should be fixed instead. Note the Copilot suggestion about endianness-safe packet writes in the test.

### [#7611](https://github.com/EdgeTX/edgetx/pull/7611) — fix(lua): compare float with int strictly in equality (#7587)
- **State:** OPEN · **Created:** 2026-08-03 · **Updated:** 2026-08-05
- **Base:** `main` · **Branch:** `fix/lua-float-integer-equality` · **Draft:** no
- **Changes:** +47 / −1 in `radio/src/thirdparty/Lua/src/lvm.h`, `lvm.c`, and `radio/src/tests/lua.cpp`
- **Fixes:** #7587 (`0.50 == 0` incorrectly returned `true`)
- **Reviews / comments:**
  - `copilot-pull-request-reviewer` — informational, no issues.
  - `J-Sorenson` — asked to add `<=`/`>=` tests; **you added them (commit 19dc95d0)** and they confirmed "Tests look good." They recommend leaving `math.tointeger` out of scope (done) and **adding the `bug`, `triage`, and `lua` labels** for visibility.
- **Labels:** none — author cannot add them (only maintainers can).
- **Status / Next step:** Code is approved-by-reviewer. Left a comment on the PR requesting maintainers apply `bug 🪲`, `triage`, `lua` for visibility (comment: 2026-08-06). No further author action possible for labels.

---

## CLOSED (not merged) — decisions to revisit

### [#7593](https://github.com/EdgeTX/edgetx/pull/7593) — feat(lua): expose touch enabled state
- **State:** CLOSED (by author) · **Closed:** 2026-07-29 · **Not merged**
- **Base:** `main` · **Branch:** `agent/expose-touch-state-lua`
- **Changes:** +43 / −0 in `radio/src/lua/api_general.cpp` and `radio/src/tests/lua.cpp`
- **Related to:** #1085 (visible indication when touch is disabled)
- **What happened:** You closed it after `philmoz` pointed out that PR #7565 already solves #1085 with a popup.
- **Reviews / comments:**
  - `philmoz` — noted #7565 solves #1085.
  - `pfeerick` (**MEMBER**, **2026-08-02**, AFTER closing) — "I think there is value in adding something along these lines anyway"; this PR is not really about #1085 but about adding Lua API surface for radio/UI state (more such indicators are needed, e.g. RGB LEDs).
- **Status / Next step:** ⚠️ **Reconsider reopening.** `pfeerick` explicitly expressed value in this API despite the popup. This closed PR may be worth reopening/rebasing as a general "radio/UI state in Lua" API, not tied to #1085.

### [#7592](https://github.com/EdgeTX/edgetx/pull/7592) — fix(color): make messaging dispatch mutation-safe
- **State:** CLOSED (by author) · **Closed:** 2026-07-29 · **Not merged**
- **Base:** `main` · **Branch:** `fix/color-messaging-reentrancy`
- **Changes:** +253 / −19 in `radio/src/gui/colorlcd/libui/messaging.{h,cpp}` and `radio/src/tests/messaging.cpp`
- **What happened:** You closed it after `philmoz` challenged the premise (no existing call site mutates subscriptions during dispatch; deemed overkill). You agreed and closed with an explanation.
- **Status / Next step:** Closed by design. Review your own closing comment to ensure it fully captures the decision (it does). No further action unless the underlying concern resurfaces. Likely leave closed.

---

## Suggested immediate actions
1. **#7612** — Reply to **3djc**'s 3 concerns (sensor-ID table, DIY-range collision, Betaflight-side fix). Add labels.
2. **#7611** — Labels requested via comment (author lacks add-label permission). **DONE 2026-08-06** — monitor for maintainer applying `bug 🪲`/`triage`/`lua`.
3. **#7593** — Consider **reopening** given `pfeerick`'s member feedback that the Lua radio/UI-state API is valuable.
4. **#7613** — Monitor; all checks green, awaiting maintainer review. No immediate action.
5. **#7592** — Leave closed; decision already documented.
