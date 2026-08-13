# Gauge Dial Pro + Gauge Bar Pro — Beta and Pre-PR Review

Review date: **2026-08-13**

Prepared PR branch: `feat/gauge-pro-beta`

Reviewed source commit: `a10e264992ee815876085d99b26619eca5317da2`

## Executive verdict

**The widget runtime is a strong beta candidate, but the branch is not yet
ready for a clean pull request.**

The production Lua implementation passed all 309 automated tests, static
analysis, callback and memory gates, geometry checks, motion checks, package
installation, the C++ simulator build, and the real Bar Pro settings-form
probe. Representative valid simulator captures show good containment,
hierarchy, status readability and stock/dark-theme adaptation.

Two release gates and one scoping decision remain open:

1. The visual harness occasionally drops `PageDown`, so the fresh evidence set
   contains stale frames for Arc, dark CRIT and dark NO SOURCE. This is an
   evidence-integrity blocker, not a confirmed widget-runtime failure.
2. No physical color-radio test was available. The 2.11 option contract is
   automated, but the current visual evidence is from the development
   simulator path rather than a 2.11 radio.
3. The simulator-only C++ support should be separated or explicitly justified
   in the PR scope.

For a controlled first beta, close the visual-evidence blocker, run a physical
radio smoke test, and publish the beta caveats and feedback template already
added to the READMEs. The prepared PR branch already excludes the unrelated
`imgui.ini` commit. A direct PR to the upstream `EdgeTX/edgetx` repository
still needs additional branch/packaging work described below.

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

The full simulator run is recorded in
[`visual-kit/RUN_SUMMARY.md`](visual-kit/RUN_SUMMARY.md). The run is fully fresh
(277 fresh, 0 retained), so the warnings cannot be dismissed as old evidence.

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
| P-01 | Closed                        | Commit `a10e264992` changes only `imgui.ini` and is unrelated to the widget feature.                                                                                                                                                        | The clean `feat/gauge-pro-beta` PR branch excludes it.                                                                                                               |
| P-02 | Blocker if targeting upstream | Against `upstream/main`, the branch is 23 commits behind/70 ahead with 921 changed files; upstream has no matching `WIDGETS` tree.                                                                                                          | Confirm the intended target and distribution model, then rebase/cherry-pick into a minimal branch or package the widgets separately.                                 |
| H-01 | High                          | No physical color-radio smoke test was run. EdgeTX 2.11 behavior is contract-tested but not visually exercised here.                                                                                                                        | Test cold boot, registration, settings persistence, telemetry loss/recovery, theme changes and SD packaging on at least one radio; ideally test both 2.11 and 2.12+. |
| C-01 | Medium                        | Eight rich-source cases remain documented simulator skips: structured CELLS, timer control and one descending-history orchestration case.                                                                                                   | Retain as explicit beta limitations or add native injection/orchestration before final release.                                                                      |
| C-02 | Medium                        | Synthetic catalog zone names map to the nearest real simulator layout; for example the nominal 60×60 case is captured in a larger real zone. Pure geometry tests cover the synthetic size, but the screenshot is not native 60×60 evidence. | Add a real layout/viewport that supplies the target zone or label the capture mapping more prominently.                                                              |
| P-03 | Medium                        | Four simulator/telemetry C++ files add 62 lines and remove 4 lines to support visual injection/link control.                                                                                                                                | Keep in a separate, well-explained commit or separate PR so product code and test-harness support are independently reviewable.                                      |
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
evidence. The four simulator C++ files account for 62 insertions and 4
deletions and deserve their own reviewable scope.

The prepared `feat/gauge-pro-beta` branch starts from `origin/main`,
cherry-picks only the two Gauge feature commits, and adds this review and beta
documentation. It does not contain `a10e264992` or `imgui.ini`. With the review
artifacts included, its current diff is 470 files, 4,147 insertions and 866
deletions against the fork's `origin/main`.

Against `EdgeTX/edgetx` `upstream/main` (`2cc978470e`), the branch history and
repository content are materially different: 23 behind, 70 ahead, 921 files,
131,234 insertions and 4 deletions. Therefore this branch is not suitable for
a direct upstream PR as-is, regardless of widget test health.

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
- [x] Remove or split the unrelated `imgui.ini` commit.
- [ ] Decide whether simulator C++ support belongs in this PR or a separate PR.
- [ ] Confirm whether the target is the fork, an SD-content repository, or
      upstream EdgeTX; prepare a minimal branch for that target.
- [ ] Rerun the 309 Lua tests, static analysis, resource gates, simulator build,
      install check and settings probe after branch cleanup.
- [ ] Update this verdict and the visual-run summary before requesting review.

Until those items are complete, the correct status is **runtime beta
candidate; pull request not ready**.
