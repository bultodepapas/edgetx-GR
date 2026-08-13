# Gauge Dial Pro + Gauge Bar Pro — Beta and Pre-PR Review

Review date: **2026-08-13**
Original integration branch: `feat/gauge-v2`
Reviewed commit: `a10e264992ee815876085d99b26619eca5317da2`

## Official PR handoff — 2026-08-13 update

The mixed development branch reviewed below was not submitted directly. Its
upstream-facing work was split into two minimal, independent draft pull
requests in the official EdgeTX organization:

- [EdgeTX/edgetx-sdcard #289](https://github.com/EdgeTX/edgetx-sdcard/pull/289)
  contains only Gauge Dial Pro, Gauge Bar Pro and their shared Gauge Core SD
  payload. It excludes the legacy combined widget, visual-development assets,
  simulator changes and `imgui.ini`.
- [EdgeTX/edgetx #7646](https://github.com/EdgeTX/edgetx/pull/7646) contains only
  the opt-in Widget Studio simulator automation hooks and their documentation.
  The widgets do not depend on these hooks at runtime.

Both source worktrees were clean at the handoff. PR #289 was open as a draft
with CodeRabbit green. PR #7646 was open as a draft with all compile and test
jobs green; its final packaging job failed after successfully merging and
uploading all firmware artifacts, when the artifact action received a 404
while deleting an already-missing input artifact. That packaging cleanup
failure requires a rerun or maintainer confirmation, but it is not a reported
compile or test failure.

## Executive verdict

**The widget runtime is a strong beta candidate. The original mixed branch was
not suitable for upstream submission, and that scope problem has now been
resolved by the two official draft PRs above. Neither draft should be promoted
as a stable release yet.**

The production Lua implementation passed all 309 automated tests, static
analysis, callback and memory gates, geometry checks, motion checks, package
installation, the C++ simulator build, and the real Bar Pro settings-form
probe. Representative valid simulator captures show good containment,
hierarchy, status readability and stock/dark-theme adaptation.

The remaining beta gates are:

1. The visual harness occasionally drops `PageDown`, so the fresh evidence set
   contains stale frames for Arc, dark CRIT and dark NO SOURCE. This is an
   evidence-integrity blocker, not a confirmed widget-runtime failure.
2. No physical color-radio test was available. The 2.11 option contract is
   automated, but the current visual evidence is from the development
   simulator path rather than a 2.11 radio.
3. Both official submissions are intentionally drafts and still need
   maintainer feedback. The simulator PR also needs its packaging cleanup job
   rerun or otherwise resolved.

For a controlled first beta, close the visual-evidence blocker, run a physical
radio smoke test, and retain the beta caveats and feedback template added to
the READMEs. The correct official repository and PR scope are now established.

## Scope and architecture reviewed

| Product        | EdgeTX ID | 2.11 options | 2.12+ options | Entry point                     |
| -------------- | --------: | -----------: | ------------: | ------------------------------- |
| Gauge Dial Pro | `DialPro` |           10 |            24 | `WIDGETS/GaugeDialPro/main.lua` |
| Gauge Bar Pro  |  `BarPro` |           10 |            42 | `WIDGETS/GaugeBarPro/main.lua`  |

Both front ends declare Core API 1 and load the same runtime from
`/SCRIPTS/TOOLS/GaugeCore/`. The review covered registration, option contracts,
lazy loading, telemetry and availability handling, ranges, hysteresis,
history, theme resolution, alerts, retained-object updates, Dial layout and
rendering, Bar layout and all Bar faces.

The family split is sound: `app.lua` loads common modules plus only the active
family modules. Dial Pro does not load Bar faces/layout, and Bar Pro does not
load the Dial renderer/layout. Telemetry rejects invalid and non-finite data,
distinguishes unset/disconnected/unavailable/stale states, and treats cell
tables and battery aggregation defensively. Stable refreshes update retained
properties without rebuilding the LVGL tree.

No confirmed production-runtime defect was found in the reviewed Lua code.
There were no production `TODO`/`FIXME` markers, leaked writable globals, or
stable-frame LVGL object creation in the audited paths.

## Verification evidence

Commands in the first part of the table were run from `WIDGETS/GaugePro/`.
Visual-kit commands were run from `tools/gaugepro-visual-kit/`.

| Check                                                                                  | Result                                                                                 |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `lua tests/run_tests.lua ./`                                                           | **PASS** — 72 passed, 0 failed                                                         |
| `lua tests/smoke_test.lua ./`                                                          | **PASS** — 220 passed, 0 failed                                                        |
| `lua tests/widgets_test.lua ./`                                                        | **PASS** — 17 passed, 0 failed                                                         |
| Combined Lua tests                                                                     | **PASS** — 309 passed, 0 failed                                                        |
| `luacheck --config .luacheckrc *.lua ../GaugeBarPro/main.lua ../GaugeDialPro/main.lua` | **PASS** — 22 files, 0 warnings/errors                                                 |
| `lua dev/split_resources.lua ./`                                                       | **PASS** — Dial 323 KB, Bar 564 KB, mixed estimate 887 KB retained                     |
| `lua dev/collide.lua ./`                                                               | **PASS** — all zone, sweep, face, vertical, zero and dual-rail cases clean             |
| `lua dev/instructions.lua ./`                                                          | **PASS** — worst callback 9,400 instructions; 53% headroom below the 20,000 gate       |
| `lua dev/measure_frames.lua ./`                                                        | **PASS** — 13–56 B/stable frame and zero LVGL object creation                          |
| `lua dev/motion_sequences.lua ./`                                                      | **PASS** — 48/48 temporal/resource cases                                               |
| `lua dev/boot_cost.lua ./`                                                             | **PASS** — boot-cost invariant                                                         |
| `lua dev/census.lua ./`                                                                | **PASS** — retained object caps; worst visible/retained count 40                       |
| `python run.py check`                                                                  | **PASS** — Dial 24, Bar 42, 229 catalog cases, 8 layouts, split/docs contracts         |
| `cmake --build build/simu --target simu --parallel 2`                                  | **PASS** — simulator target builds                                                     |
| `dev/sync-sd.ps1` to an isolated destination                                           | **PASS** — 21 files; shared Core + both widget front ends; Core API check passed       |
| `python settings_probe.py`                                                             | **PASS** — 6/6 steps; widget menu plus top/bottom Bar Pro settings evidence            |
| `python run.py all`                                                                    | **CONDITIONAL** — 277 fresh captures, 0 runtime failures; final report 268 pass/9 warn |
| `python verify_dupes.py`                                                               | **BLOCKED** — 277 files, 229 unique, 26 groups, 2 unexpected groups                    |

The failed rerun was fully fresh (277 fresh, 0 retained), so its warnings
cannot be dismissed as old evidence. Its stale frames were deliberately not
promoted over the last clean committed visual-kit snapshot; the exact failed
run results are retained in this review and in the recoverable cleanup stash.
[`visual-kit/RUN_SUMMARY.md`](visual-kit/RUN_SUMMARY.md) therefore continues to
describe the last promoted evidence set until a deterministic clean rerun is
available.

## Visual review

Representative captures were manually inspected at original resolution:

- [`L02_fullscreen_needle.png`](visual-kit/screenshots/L02_fullscreen_needle.png)
  has a clear full-screen hierarchy and well-separated value/status layers.
- [`L04_fullscreen_bar_hex.png`](visual-kit/screenshots/L04_fullscreen_bar_hex.png)
  retains exact position and limit cues without crowding.
- [`L05_layout2p3_dial_vs_bar.png`](visual-kit/screenshots/L05_layout2p3_dial_vs_bar.png)
  shows Dial/Bar parity, clear WARN/CRIT semantics and correct containment.
- [`L07_layout4p2_mixed.png`](visual-kit/screenshots/L07_layout4p2_mixed.png)
  and [`L08_layout2x2_grid.png`](visual-kit/screenshots/L08_layout2x2_grid.png)
  remain legible in dense mixed-family layouts.
- The matching dark-layout captures retain readable chrome, text and status
  contrast.
- The wide TX battery WARN/NO DATA cases communicate both state and missing
  value clearly.
- The real Bar Pro settings menu and top/bottom settings captures are readable
  and scroll to the final options successfully.

The main visual quality appears appropriate for a beta. The current blocker is
the reliability of the evidence sequence:

- `031_dial_op-style-arc.png` is byte-identical to the preceding Needle/default
  frame and visibly still shows the needle. The Arc page was not reached.
- Dark-theme `st-crit` and `st-nosource` are byte-identical to `st-warn` and
  visibly retain the WARN frame.

The runner already retries unchanged pages in the Track 2 layout loop, but the
Track 1 and first theme loops capture and press `PageDown` without equivalent
advance verification. A pixel-only retry is not sufficient by itself because
some consecutive catalog cases are intentionally identical. The robust fix is
to expose or verify a deterministic current-case/page identity, retry the key
event until that identity advances, and then capture.

## Findings and disposition

| ID   | Severity                      | Finding                                                                                                                                                                                                                                     | Disposition                                                                                                                                                          |
| ---- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| V-01 | Blocker                       | Track 1/theme navigation can drop `PageDown`, creating false visual evidence.                                                                                                                                                               | Fix the harness, rerun all captures, require zero **unexpected** duplicate groups, and manually recheck Arc/CRIT/NO SOURCE.                                          |
| P-01 | Closed                        | Commit `a10e264992` changes only `imgui.ini` and is unrelated to the widget feature.                                                                                                                                                        | Excluded from both official PR branches.                                                                                                                             |
| P-02 | Closed                        | Against `upstream/main`, the branch is 23 commits behind/70 ahead with 921 changed files; upstream has no matching `WIDGETS` tree.                                                                                                          | Target confirmed: widget payload in `edgetx-sdcard` #289; simulator support in `edgetx` #7646.                                                                        |
| H-01 | High                          | No physical color-radio smoke test was run. EdgeTX 2.11 behavior is contract-tested but not visually exercised here.                                                                                                                        | Test cold boot, registration, settings persistence, telemetry loss/recovery, theme changes and SD packaging on at least one radio; ideally test both 2.11 and 2.12+. |
| C-01 | Medium                        | Eight rich-source cases remain documented simulator skips: structured CELLS, timer control and one descending-history orchestration case.                                                                                                   | Retain as explicit beta limitations or add native injection/orchestration before final release.                                                                      |
| C-02 | Medium                        | Synthetic catalog zone names map to the nearest real simulator layout; for example the nominal 60×60 case is captured in a larger real zone. Pure geometry tests cover the synthetic size, but the screenshot is not native 60×60 evidence. | Add a real layout/viewport that supplies the target zone or label the capture mapping more prominently.                                                              |
| P-03 | Closed                        | Simulator-only support should remain independently reviewable from the widget payload.                                                                                                                                                     | Submitted separately as the opt-in Widget Studio simulator PR `EdgeTX/edgetx` #7646.                                                                                 |
| R-01 | Low/watch                     | Derived source metadata resolution retries once per second for 30 attempts, then latches missing. This is a deliberate bound, not a reproduced defect.                                                                                      | Ask beta users to report sensors that first appear after a long delay; reconsider the latch only if real radios reproduce it.                                        |
| D-01 | Closed                        | README test/capture counts and committed option sheets were stale (210/272/216–222-era values).                                                                                                                                             | Updated READMEs and regenerated stock/dark/high-contrast sheets from the current 229-scene catalog.                                                                  |

## Branch and PR scope

At review time, against the fork's `origin/main` (`d585d9f983`), the branch is
0 behind and 3 commits ahead. The diff is 462 files, 3,765 insertions and 858
deletions. The commits are:

```text
a10e264992 feat(imgui): add initial configuration for Debug window
2f225b1e10 feat(gaugepro): complete visual feedback phases
bc65342ab6 Improve GaugePro runtime and visual validation
```

Most of the changed files are widget code, catalogs and generated visual
evidence, but the unrelated ImGui commit should not be part of this PR. The
four simulator C++ files account for 62 insertions and 4 deletions and deserve
their own reviewable scope.

Against `EdgeTX/edgetx` `upstream/main` (`2cc978470e`), the branch history and
repository content are materially different: 23 behind, 70 ahead, 921 files,
131,234 insertions and 4 deletions. Therefore this branch is not suitable for
a direct upstream PR as-is, regardless of widget test health.

### Post-review split

That conclusion was acted on without rewriting the integration branch:

- the canonical SD overlay was prepared in a clean `edgetx-sdcard` branch and
  opened as draft PR #289 with one focused commit and 23 payload/documentation
  files;
- the development-only simulator feature was prepared from official
  `EdgeTX/edgetx` `main` and opened as draft PR #7646 with one focused commit
  and 13 implementation/documentation files; and
- neither PR contains `imgui.ini`, the legacy combined widget, generated
  visual evidence, or unrelated formatter changes.

## First-beta recommendation

After the release blockers are closed, publish this as an explicitly limited
beta rather than a final/stable release. Keep radio alarms/failsafes as the
authoritative safety layer, ask users to back up their SD/model configuration,
and actively request reports from different radios, EdgeTX versions, themes,
layouts and telemetry sources.

A useful beta report should contain:

```text
Radio model:
EdgeTX version:
Widget: DialPro / BarPro
Telemetry source and unit:
Layout and zone:
Theme:
Non-default options:
Expected behavior:
Actual behavior:
Screenshot/video/log:
Requested feature, option or improvement:
```

## PR exit checklist

- [ ] Add deterministic page-advance verification to Track 1 and theme
      capture loops.
- [ ] Rerun `python run.py all`; require zero unexpected duplicate groups.
- [ ] Manually verify the corrected Arc, dark CRIT and dark NO SOURCE frames.
- [ ] Run a physical color-radio smoke test and record radio/firmware details.
- [x] Exclude the unrelated `imgui.ini` commit from the official PRs.
- [x] Submit simulator automation separately from the widget SD payload.
- [x] Confirm the official targets and prepare minimal one-commit branches.
- [x] Rerun the 309 Lua tests, static analysis, resource gates, simulator build,
      install check and settings probe after branch cleanup.
- [ ] Rerun or otherwise resolve the Widget Studio PR's artifact-cleanup-only
      packaging failure.
- [ ] Update this verdict and the visual-run summary before requesting review.

Current status: **official split complete; both PRs correctly open as drafts;
widget runtime is a beta candidate, but the drafts are not ready to promote to
stable or mark ready for final review until the remaining gates are resolved**.
