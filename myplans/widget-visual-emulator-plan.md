# EdgeTX Widget Studio — Visual Radio Emulator Plan

**Document version:** 0.2 (integrates the grilled decision record from the 0.1 review)
**Status:** Senior-dev plan validated against the local repo (`bultodepapas/edgetx-GR`, branch `feat/gauge-v2`, EdgeTX 3.0) and the design-review interview
**Target:** A scriptable, pixel-accurate, computer-based visual emulator of the EdgeTX color-LCD radio, purpose-built for developing Lua/LVGL widgets (Gauge Pro is the reference workload), for other visual improvements, and — at contract level, without a heavy platform — for other developers.
**Date:** August 10, 2026

---

# 1. Purpose

Developing a color-LCD widget today means choosing between two inadequate loops:

| Loop | What it proves | What it hides |
|---|---|---|
| Pure-Lua mock + SVG gallery (`WIDGETS/GaugePro/tests/mock_env.lua`, `dev/svgkit.lua`, `dev/shots.lua`, `dev/gallery.lua`, Playwright rasterization) | Logic, option handling, state, geometry, binding contract | Real LVGL layout, real fonts/metrics, real theme compositing, real rendering |
| Manual runs in Companion Simulator or the web simulator | Pixel-true output | Automation. Every scenario is a hand sequence of clicks |

The goal of this plan is a third loop that has neither gap: **a visual, code-driven emulator of the radio** on the computer that

1. renders with the **actual firmware** (real LVGL, real Lua binding, real fonts, real themes) so pixels are truthful;
2. is **scriptable** — a scenario manifest drives zones, option sets, sources, telemetry, themes, and resolutions without touching the radio UI;
3. produces **artifacts** — PNG screenshots, a gallery, and pixel-diffs against golden images — for review and CI;
4. **hot-reloads** widget files so a code edit is visible in seconds;
5. covers **multiple radio geometries** (320×240 … 800×480) from the single authoritative `hw_defs` source.

Scope reading (from the design review): the tool is a **developer sibling of Companion Simulator** — automation for any visual work in the fork (widgets, themes, screens), not a widget-only proofing script. It is **generic by contract**: any widget that implements the standard registration contract runs through it without per-widget code. This is the "useful to other developers" property, priced so it never becomes a platform (no package manager, no plugin ecosystem, no binary distribution pipeline in scope).

This is a planning deliverable. No implementation code is written yet.

---

# 2. Research — what already exists (internet + this repo)

Everything below was verified against the local tree or the linked upstream sources.

| # | Source | What it is | Verdict for this plan |
|---|---|---|---|
| 1 | `radio/src/targets/simu` (in-repo) | The **actual firmware compiled for a PC** (the `simu` target). Two outputs: native `simu` (SDL2 + Dear ImGui + ImGuiKnobs + stb) and `wasi-module` (`edgetx-<flavour>-simulator.wasm`, reactor model, WASI). CMake preset `simu` → `build/simu`. Native build is a documented Windows path (`docs/building/windows.md`: `ninja -C native simulator`, SDL2 dependency). | **The engine.** Pixel-accurate by construction: it runs the same LVGL, the same Lua binding, the same themes/fonts the radio runs. |
| 2 | `web/` (in-repo) | **EdgeTX Web Simulator** source: WASM + WASI threads, OPFS-backed synchronous filesystem, WebGL LCD renderer (RGB565 / 4-bit / 1-bit), radios generated from `radio/src/boards/hw_defs` via `node web/scripts/gen-radios-json.js`. | Secondary surface. Browser workspace for preview/share; constrained by COOP/COEP and `SharedArrayBuffer`. |
| 3 | `companion/src/simulation/` (in-repo) | Companion's Qt simulator embedding (native + WASM via `simulatorinterface.cpp` / `wasmsimulatorinterface.cpp`), plus telemetry simulators (`telemetrysimu`). | Reference for how the simu is embedded and driven; not automatable as-is. |
| 4 | `jurgelenas/edgetx-cli` (GitHub, GPL-3.0, Rust) | Community "package manager, **simulator**, and development environment for EdgeTX Lua applications": `dev simulator --radio … --headless --screenshot result.png --script test.lua` with a Lua scripting API (`key.press`, `touch.tap`, `switch()`, `analog()`, `channel.get`, `screenshot()`, `reload()`), live-sync into the simulator SD card. | **Proof the approach is viable and wanted.** We reuse its scripting surface as the reference design and its headless-screenshot trick as validation — but do not adopt the tool (Rust/GPL-3.0, own simu build pipeline, out-of-tree control). |
| 5 | `WIDGETS/GaugePro/` tooling (in-repo) | High-fidelity pure-Lua harness: `tests/mock_env.lua` (LVGL binding mock with per-object property allow-lists, `pts` validation, real RGB565 math, real theme palette), `dev/scenes.lua` (scenario catalog), `dev/svgkit.lua` (SVG emitter), `dev/shots.lua`/`dev/gallery.lua` (rendering), Playwright rasterization, zone atlas (`PHASE0_ZONE_ATLAS.md`). | Keep unchanged for **unit-logic** tests and as the **scenario catalog source**. Its SVG output is the fast-feedback approximation; the new tool is the pixel-truth layer. |

Key upstream facts (verified in this repo):
- `radio/src/targets/simu/simulib.h:169` — `WASM_IMPORT(simuLcdNotify)()` is the **frame-ready callback**; in the native `simu` it is currently a no-op (`sdl_simu.cpp:876`). This is the exact hook for deterministic screenshot capture.
- `radio/src/targets/simu/display.cpp:101` `refreshDisplay()` copies the LCD framebuffer into an SDL texture each frame; the framebuffer itself is real firmware state (RGB565 for color LCD).
- `simufatfs` maps a **host directory** as the SD card (`--storage`/`--settings` args in `arg_parser`), so "installing" a widget is a filesystem copy, and hot-reload is a file watch + reload signal.
- **No sim-only Lua module exists in this fork** (no `LROT_BEGIN(simu…)` anywhere in `radio/src`). A `simu` Lua namespace guarded by `#if defined(SIMU)` must be added — this is the enabler for telemetry/switch/analog injection and for arming capture.
- **No host→simu com channel exists either.** `arg_parser` supports only `--width/--height/--storage/--settings`; there is no `SIMU_AUX`/`SIMU_COM_PORT` in this fork. The driver's command channel must therefore be added (see §4.1).
- `radio/src/targets/simu/simulib.cpp:701` — `simuSendTelemetry()` is already `WASM_EXPORT`ed for host-side telemetry injection (used by the WASM/web path). It does not cover sensor *registration*; the new Lua module will.
- The Lua/LVGL widget contract is documented and verified in `WIDGETS/GaugePro/PLAN.md` §3.3: arc `endAngle`, line `pts` as function, label `text` as function, `lvgl.build/set`, `LCD_SCALE` (0.8 / 1.0 / 1.375), theme colors, the 200-instruction refresh budget, `MAX_WIDGET_OPTIONS 50`.

---

# 3. Decision

## 3.1 Chosen approach: **Widget Studio** — a harness on the real simulator engine

Build a widget-development harness layered on the **native `simu` binary** as the primary engine, with the in-repo `web/` simulator as a secondary browser surface. The pure-Lua mock stays as the unit-logic layer. **Do not write a new emulator or renderer.**

The stack, top to bottom:

```
 ┌────────────────────────────────────────────────────────────┐
 │ Host driver  tools/widget-studio/                          │
 │  ws build | ws introspect | ws run | ws gallery |          │
 │  ws diff | ws golden | ws watch                            │
 │  (Python; boots simu headless, steers scenarios over pipe  │
 │   or file queue, collects PNGs, pixel-diffs, gallery,      │
 │   exit codes)                                              │
 └───────────────┬────────────────────────────────────────────┘
                 │ host dir = SD card (simufatfs)
                 │ fast path: stdin/pipe channel (new)
                 │ fallback: file-based command queue
 ┌───────────────▼────────────────────────────────────────────┐
 │ SD-card harness  SCRIPTS/TOOLS/WidgetStudio/*.lua          │
 │  reads studio.yml (auto-generated if absent)               │
 │  runs each case: zone+options+sources+theme, arms capture, │
 │  advances frames, writes /SCREENSHOTS/<case>.png + report  │
 └───────────────┬────────────────────────────────────────────┘
                 │ simu Lua module (new, #if SIMU): setTelemetry
                 │   (registers real sensors), setSwitch,
                 │   setAnalog, armCapture, reloadWidget, getTick
 ┌───────────────▼────────────────────────────────────────────┐
 │ Engine: native simu for a flavour (tx16s first)            │
 │  real firmware: LVGL + Lua binding + fonts + themes        │
 │  simuLcdNotify() implemented → deterministic PNG capture    │
 └────────────────────────────────────────────────────────────┘
```

## 3.2 Why this over the alternatives

| Alternative | Rejected because |
|---|---|
| **Write a new renderer** (canvas/SVG reimplementation of LVGL, or driving LVGL.js) | Duplicates LVGL semantics, fonts, themes, and the binding — the exact things that diverge. Massive cost for guaranteed drift. The whole point of §2 facts is that the firmware sim already renders truthfully. |
| **Extend only the web simulator** as primary | COOP/COEP + `SharedArrayBuffer` constraints, browser lifecycle, no local CI process control, slower iteration than a native headless binary. Keep it as the secondary/shareable surface. |
| **Adopt `edgetx-cli`** | GPL-3.0 Rust tool with its own simu build pipeline. Two toolchains to maintain and an external dependency we cannot steer; its scripting API is a design reference, not a runtime dependency. |
| **Only improve the SVG/mock loop** | It cannot become pixel-accurate without reimplementing LVGL layout/typography (see first row). It remains the fast logic layer, which is its correct role. |

## 3.3 Decision record (design-review interview, Aug 10 2026)

| # | Decision | Resolution |
|---|---|---|
| Q1 | Tool scope | **Full developer-simulator sibling** — widgets, themes, screens; automation for any visual work in the fork. |
| Q2 | Primary surface | **Native `simu` primary**; in-repo `web/` simulator is the secondary/nice-to-have surface. |
| Q3 | Firmware-change appetite | **Accept simu-target-only hooks** (`simu` Lua module + capture + steering), all behind `-DWIDGET_STUDIO=ON` (default OFF, `#if defined(SIMU)`). |
| Q4 | Host→simu command channel | **Both**: stdin/pipe fast channel (primary) **and** file-based command queue (fallback). |
| Q5 | Driver language | **Python 3** (repo precedent in `tools/`). |
| Q6 | Golden/parity source | **Self-frozen goldens** (first honest simu PNGs) + **one-time Companion Simulator calibration**; hardware spot-check when available. |
| Q7 | Coverage first | **tx16s @ 480×272 + 800×480** before breadth across radios. |
| Q8 | Browser workspace | **Nice-to-have** (phase 5 stretch), not a shaping requirement. |
| Q9 | Usable by others | **Generic-by-contract** (see §3.4); priced to avoid a platform (no package manager / plugin ecosystem / binary distribution pipeline). |
| Q11 | Genericity packaging | **Contract-driven CLI + auto-generated `studio.yml` + documented schema + README quickstart + a second demo widget** proving it is not Gauge Pro-specific. |
| Q12 | Telemetry fidelity | **Register real sensors** through the actual sensor registry, then set values — `getValue`/`getSourceValue`/`getFieldInfo` and table sources (`CELLS`, `-`/`+` siblings) behave exactly as on radio. |

## 3.4 Scope decisions

- **In scope:** native-simu capture + sim-only Lua module + steering channel; `studio.yml` schema and auto-generation; the SD-card harness; the Python driver (build/introspect/run/gallery/diff/golden/watch); golden-image pipeline for color LCD; genericity proof (contract-driven runner + demo widget); browser workspace (phase 5); Gauge Pro as the reference integration.
- **Out of scope:** monochrome targets; changing the Lua/LVGL binding; touching release firmware (all new firmware-side code is `#if defined(SIMU)` and a CMake option, default OFF); editing `hw_defs`; the Companion Qt app; a plugin ecosystem; prebuilt binary distribution (kept as a documented *future* path only).
- **Version target:** this fork (EdgeTX 3.0). Same compatibility guard philosophy as Gauge Pro: the harness only claims to work where the simu exists.

---

# 4. System design

## 4.1 Firmware-side additions (simu target only)

All of these are small, build-option-guarded, and cannot leak into radio firmware builds.

| Addition | Location (proposed) | Behavior |
|---|---|---|
| `simuDumpLcd(const char* path)` | `radio/src/targets/simu/simulcd.cpp` | Writes the current LCD framebuffer as RGB565→RGB888 PNG (stb_image_write, already vendored under `thirdparty/stb`). |
| Implement `simuLcdNotify()` (arm/disarm) | `radio/src/targets/simu/simulcd.cpp` + flag in `simulib.h` | When a capture is armed, the **next frame-ready callback** dumps the PNG and disarms. Deterministic screenshots instead of racing `refreshDisplay`. |
| Lua module `simu` (`#if defined(SIMU)`) | `radio/src/lua/api_simu.cpp` (new) | `simu.setTelemetry(idOrName, value)` — **registers the sensor in the real sensor registry** (with name, unit, precision) and sets its value so `getValue`/`getSourceValue`/`getFieldInfo` and `CELLS` aggregation work exactly as on radio; `simu.setSwitch(name, -1/0/1)`; `simu.setAnalog(name, 0–4096)`; `simu.armCapture(path)`; `simu.reloadWidget()`; `simu.getTick()`. Exposed only when built for the simu target; absent on hardware. |
| Host steering channel (primary: pipe) | `arg_parser` (+ a reader in the simu frame loop) | `--pipe <path>` (named pipe / stdin): the driver pushes commands (`scenario`, `reload`, `armCapture`, `exit`), consumed each frame. Simu-only, no change to the Lua binding. |
| Host steering channel (fallback: file queue) | harness-side polling | If no pipe is available, the Lua harness polls a `commands` file on the SD tree. Both channels are implemented behind the same command vocabulary so the driver is agnostic. |
| CMake option | `radio/src/targets/simu/CMakeLists.txt` | `option(WIDGET_STUDIO "Widget Studio dev hooks" OFF)` — gates the module, capture, and steering code. |

The `simu` Lua module is the enabler that `edgetx-cli` scripts get through its own harness; putting it on the real firmware state (real telemetry table, real sensor registry) is what makes injection truthful (Q12).

## 4.2 SD-card harness (`SCRIPTS/TOOLS/WidgetStudio/`)

Pure Lua — works on the radio and in the simu, needs no firmware knowledge beyond the public Lua API.

- `main.lua` — the tool entry: reads `studio.yml`, walks the scenario list, and for each case:
  1. applies zone + options (via the widget's own registration contract — same mechanism the radio uses; **any** standard-contract widget runs unchanged, satisfying Q9),
  2. injects sources/telemetry through the `simu` module (sensor-registered values; degrades gracefully when the module is absent),
  3. switches theme (`lcd`/`theme` APIs),
  4. arms capture and advances a few frames,
  5. writes `/SCREENSHOTS/<case>.png` and appends `{case, zone, options, theme, tickCost}` to `/SCREENSHOTS/report.json`.
- `studio.yml` — scenario manifest; **auto-generated by the driver when absent** (Q11): default zone matrix from the zone atlas, each of the widget's declared options at default/min/max, a small set of synthetic sources (voltage, temp, RSSI). Per-widget overrides (Gauge Pro generates its from `dev/scenes.lua` so the new loop and the SVG loop cannot disagree on coverage):
  ```yaml
  flavour: tx16s
  theme: [stock, dark, highcontrast]
  zones: [[60,60],[128,96],[200,160],[300,150],[480,272]]  # from zone atlas
  cases:
    - name: ne-pos50
      zone: [200,160]
      options: { Style: Needle, Min: 0, Max: 100 }
      telemetry: { "Batt": 50 }
    - name: st-crit
      zone: [480,272]
      options: { ColorMode: Threshold, Warn: 20, Critical: 10 }
      telemetry: { "Batt": 5 }
  ```
- Model/screen setup is **host-generated**: the driver writes a static `RADIO/radio.yml` (and settings) per flavour with a screen containing the widget zone matrix, generated from `hw_defs` + the zone atlas. This avoids depending on runtime model-editing Lua APIs we do not control.

## 4.3 Host driver (`tools/widget-studio/`)

Python 3 (repo already ships Python tooling in `tools/`; no new language toolchain).

| Command | Behavior |
|---|---|
| `ws build [--flavour tx16s]` | CMake preset `simu` + `-DWIDGET_STUDIO=ON`; local native build. |
| `ws introspect --widget <dir>` | Reads the widget's registration contract and options; emits a default `studio.yml` (Q11 auto-generation). |
| `ws run [--flavour tx16s] [--widget <dir>] [--only ne-pos50]` | Assembles a temp SD tree (widget + harness + generated `radio.yml` + `studio.yml`), boots `simu` with `SDL_VIDEODRIVER=dummy`, steers over the pipe (falling back to the file queue), collects PNGs + `report.json`. |
| `ws gallery` | Renders an HTML gallery from the PNGs (mirrors Gauge Pro's existing gallery concept). |
| `ws diff --golden dir` | Pixel-diff each PNG against the golden set (RGB565 channel thresholds; per-case tolerance). |
| `ws golden` | (Re)baselines goldens after a reviewed change (Q6 self-freezing). |
| `ws watch` | Watches the widget source dir; on change, copies into the SD tree, triggers `reloadWidget()`, re-arms capture → **live preview loop**. |

The same command vocabulary serves the pipe and the file queue, so the driver never needs to know which channel is live (Q4c).

## 4.4 Browser workspace (secondary, phase 5)

Extend `web/` with a "Widget Studio" panel that installs a widget folder into OPFS (the filesystem proxy already supports sync file I/O), injects the same `WidgetStudio` harness, and exports canvas frames as PNG via the existing `LcdRenderer`. Shareable, no-install previews; same scenario catalog. Kept deliberately thin — it must never shape the core architecture (Q8).

---

# 5. Phases and verification gates

Each phase ends with a hard gate. Nothing in a later phase starts before its gate passes.

| # | Phase | Scope | Gate |
|---|---|---|---|
| 0 | Plan + baseline | This document; confirm `simu` preset builds on Windows (`docs/building/windows.md`) | Document builds; risks updated |
| 1 | Engine hooks spike | `simuDumpLcd`, `simuLcdNotify` arm/disarm, `simu` Lua module, pipe channel, all behind `WIDGET_STUDIO`; boot Gauge Pro inside simu SD tree; dump a PNG | **PASSED 2026-08-10** (manual spike, tx16smk3 @ 480×320, hand-authored `MODELS/model1.yml`, no `tools/widget-studio/` driver yet). PNGs of a real Gauge Pro instance in Needle/Arc/Bar styles with a live `TX_VOLTAGE` source, auto-scaled range and peak tracking, rendered by the actual firmware (LVGL + Lua binding). Pipe steering round-trips `key`/`capture`/`reset` commands. See §9a. |
| 2 | Harness + genericity core | `studio.yml` schema + `ws introspect` auto-generation, `WidgetStudio/main.lua`, host `radio.yml` generator, scenario runner, file-queue fallback | Full Gauge Pro catalog (from `dev/scenes.lua`) rendered by real firmware; ≥ 95 % cases match the SVG loop's layout within tolerance; **a second demo widget runs with zero per-widget code**; valid `report.json` |
| 3 | Driver + goldens | `ws run/gallery/diff/golden`, 3 themes × 2 resolutions golden baseline, exit codes for CI | Gauge Pro acceptance scenarios (dark/stock/high-contrast) pass on 480×272 and 800×480; full catalog runtime under a budgeted CI time |
| 4 | Hot reload | `ws watch` live-preview loop | Edit `geometry.lua` → fresh screenshot visible in < 2 s, unattended |
| 5 | Browser workspace | `web/` Widget Studio panel (OPFS install + canvas PNG export) | Same catalog renders and exports in Chrome via the web simulator |
| 6 | Harden + docs | Capture timing under load, error taxonomy, README quickstart (schema + demo widget), Gauge Pro CI wiring | Full pipeline green in CI; a new developer can run `ws run --widget <any-dir>` from the README |

# 6. Test matrix and acceptance criteria

Adapted from Gauge Pro's existing matrix so the new loop inherits its rigor:

- **Resolutions (phase 3):** 480×272 and 800×480 on tx16s; broader matrix after phase 3.
- **Layouts:** smallest widget cell → fullscreen, from the zone atlas.
- **Sources:** stick, channel, timer, TX battery, RSSI, voltage, temp, `CELLS` table aggregation (sensor-registered, Q12), invalid source, disconnected telemetry source.
- **Values:** below/at/above min and max, warn/critical boundaries, min==max, inverted config, negatives, decimals.
- **Dynamic:** rapid/noisy/step values, source change, range change, telemetry loss/recovery, resize, theme switch.
- **Performance:** four simultaneous Gauge Pro instances; per-case tick cost in `report.json`; refresh-budget compliance (200 instructions) measured through the simu.
- **Genericity:** the demo widget exercises each option type the contract supports; `ws introspect` output for it needs no hand-editing to run.

Acceptance criteria:

1. `ws run` reproduces every scenario in the catalog as a PNG with no manual steps.
2. Pixel parity with Companion Simulator within documented per-channel tolerance on the reference cases.
3. The `simu` Lua module and steering hooks are absent from release firmware builds (`WIDGET_STUDIO=OFF` default; no symbol reachable without it).
4. Hot reload round-trip < 2 s for a file edit.
5. Golden diffs are the authoritative "did it change" signal; baselines change only by explicit `ws golden` after review.
6. CI-compatible exit codes (0 = all cases within tolerance; nonzero with a diff report otherwise).
7. Any standard-contract widget runs via `ws run --widget <dir>` with only an auto-generated `studio.yml`.

# 7. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Screenshot races the frame (dumps stale buffer) | High | Arm/disarm on `simuLcdNotify()` (the frame-ready callback), not a wall-clock delay; dump on notify. |
| Steering channel becomes the slow/undocumented part | Medium | Two implementations behind one command vocabulary (Q4c); pipe is the fast path, file queue is a tested fallback; both verified in phase 1/2. |
| Native simu on Windows toolchain friction (SDL2/ImGui fetch) | Medium | Phase-1 gate is explicitly a Windows build check; fallback is the WASM module + a Node runner reusing the same harness (web path). |
| Runtime model/screen editing exceeds what Lua can do | Medium | Host generates a static `radio.yml` per flavour from `hw_defs`; harness never edits the model, only options + sources + theme. |
| Genericity claims exceed the demo coverage (Q9/Q11 creep) | Medium | The contract-driven runner + one demo widget is the hard ceiling for this plan; anything beyond (packaging, binary distribution) is a documented future path, not a phase. |
| Telemetry injection diverges from real sensor semantics | Medium | `simu.setTelemetry` registers real sensors and writes the real telemetry table (Q12); verify against `getValue`/`getSourceValue` behavior documented in Gauge Pro's `telemetry.lua`. |
| The sim-only Lua module expands into "firmware feature" scope | Medium | Strict `#if defined(SIMU)` + `WIDGET_STUDIO` option, OFF by default; module surface frozen in phase 1 and reviewed. |
| Golden-image maintenance burden | Low | Tolerance policy + explicit rebaseline command + gallery diffs for human review. |

# 8. Open questions

1. Is Companion Simulator the correct one-time calibration source, or should the calibration pair also include the web simulator's LCD renderer (three-way parity once)? (Phase 3 decision.)
2. Does the web simulator's OPFS support multi-file folder upload for a widget tree, or does phase 5 need a zip/install UX? (Phase 5 spike.)
3. Which sensor unit/precision metadata should the auto-generated synthetic sources carry so `getFieldInfo`-driven widgets (like Gauge Pro's presets) see realistic data? (Phase 2 spike.)

# 9. Immediate next step

Phase 1 spike on `feat/gauge-v2` (or a `feat/widget-studio` sibling): build the `simu` preset on Windows with `-DWIDGET_STUDIO=ON`, add `simuDumpLcd` + the armed `simuLcdNotify` hook + the minimal `simu` Lua module + the pipe channel, install `WIDGETS/GaugePro` into a simu SD tree, and produce the first PNG over a piped command. That single artifact validates every downstream assumption (capture determinism, sensor injection, steering, build path) before the harness and driver are built.

# 9a. Phase 1 spike report (2026-08-10)

Ran the spike manually (no `tools/widget-studio/` driver yet — a Bash loop played the role of the host driver, writing to `--pipe` directly). Three real defects surfaced and were fixed in the engine hooks; all are firmware-side, `WIDGET_STUDIO`-gated, and covered by rebuilding + re-running the spike:

1. **Pipe channel replayed every command on every frame, forever.** `pollPipeCommands()` re-read the whole `--pipe` file from byte 0 on every poll and never truncated it, so every line ever written was redispatched at ~60 Hz for the rest of the process's life — a `reset` command would have stop/started the simulator every frame, and a `key` press/release pair would fire back-to-back every frame instead of registering as one press. Fixed by tracking a monotonic read offset (append-only file, reader seeks from where it left off, resyncs if the file shrinks) instead of truncating — avoids both the replay bug and a truncate/append race with the driver. `radio/src/targets/simu/sdl_simu.cpp`.
2. **No touch-steering command**, even though the configured flavour (TX16SMK3) is `HARDWARE_TOUCH`, not rotary-nav — the only flavour tested is touch-driven and the pipe vocabulary had no way to drive it. Added `touch <x> <y>` / `touchup`, wired to the existing (already-WASM-exported) `simuTouchDown`/`simuTouchUp`. Not yet exercised against a real touch UI flow (this spike drove the model via a hand-authored YAML instead — see below); still needed for Phase 2's UI-driven scenarios. `radio/src/targets/simu/sdl_simu.cpp`.
3. **`armCapture` hung forever against a static screen.** Capture only fires on the next `simuLcdNotify` (LVGL flush) callback; an idle screen with no pending animation never flushes again, so a capture armed after the UI settled would wait indefinitely. Fixed by having `simuCaptureArm` also raise a force-redraw request that `LvglWrapper::run()` (simu+`WIDGET_STUDIO` only) consumes and resolves via `lv_obj_invalidate(lv_scr_act())` before the next `lv_timer_handler()`, guaranteeing the armed capture always gets a frame. `radio/src/targets/simu/simulib.{h,cpp}`, `radio/src/gui/colorlcd/LvglWrapper.cpp`.

Also confirmed empirically (not previously documented): on `raiseAlert`-driven boot dialogs (`STORAGE WARNING`, first-run format), only `KEY_ENTER` clicks the dialog's default action button — the `alertCancel()` shortcut keys (`SYS`/`MDL`/`PGUP`/`PGDN`/`TELE`) are a separate path for `WARNING_TYPE_ALERT`-only dismissal and don't apply here. A driver scripting first-run needs `KEY_ENTER` presses, not an arbitrary key. `touch` was verified independently too: tapping the same dialog's button region (`touch x y` + `touchup`) produces `TE_PRESSED`/`TE_RELEASED`/`CLICKED` and dismisses it, so touch-driven scenarios don't depend on keys at all on this flavour.

A fourth defect surfaced only when checking this work against the *rest* of the build, not the spike itself: `simulib.cpp`'s `captureDump()` carried its own `STB_IMAGE_WRITE_IMPLEMENTATION`. That file is part of the `simu_drivers` object library, which is also linked into `gtests-radio` and `wasi-module` — and `radio/src/tests/lcd_480x272.cpp` already carries its own `STB_IMAGE_WRITE_IMPLEMENTATION` for test golden images. The two collided the moment `WIDGET_STUDIO=ON` and `tests-radio` were built together (multiple-definition link error) — latent since the option was introduced, invisible until something actually built the test target in that configuration. Fixed by moving the PNG encoder into a new `radio/src/targets/simu/simu_capture.cpp`, added only to the `simu` executable's own sources (not `simu_drivers`), which installs itself into `simulib.cpp` via a small function-pointer hook (`simuSetCaptureDumpFn`) instead of `simulib.cpp` owning the stb include directly. Verified: `simu` and `tests-radio` now both build against `WIDGET_STUDIO=ON` without symbol collisions (`tests-radio`'s link still fails on an unrelated, pre-existing `-lasan` gap in this MinGW toolchain — confirmed via `git blame` to predate this work by months, not a regression from Widget Studio).

**What's still hand-rolled, not yet built:** there is no `tools/widget-studio/` driver and no `SCRIPTS/TOOLS/WidgetStudio/` SD harness (§4.2–4.3, Phase 2). This spike placed Gauge Pro on-screen by hand-authoring `MODELS/model1.yml` directly (a `Layout1x1` screen, one zone, `widgetName: GaugePro`) rather than through `studio.yml` + a generated `radio.yml`, and drove option variants by editing the zone's `widgetData.options[]` array by hand between `reset` commands. This is viable because the firmware round-trips the real schema (confirmed via a first boot + save: 44 positional option slots, typed `Source`/`Signed`/`Unsigned`/`Bool`/`Color`/`String` matching Gauge Pro's `DEFS` order 1:1) — but it is exactly the by-hand work Phase 2's `ws introspect`/host `radio.yml` generator is meant to automate. Confirmed working by hand: `Source: TX_VOLTAGE` (a real always-available internal source) drives a live needle/arc/bar with correctly auto-scaled range and peak min/max tracking; `Style` (option slot 6, 1-based: 1=Auto, 2=Needle, 3=Arc, 4=Bar) reliably switches rendering mode. A raw stored value of `0` on a freshly hand-authored zone is **not** resolved to the widget's declared `DEFS` default (e.g. `Min`/`Max` read back as the literal `0` I wrote, not Gauge Pro's compiled defaults of 0/100) — default application appears to happen at settings-dialog-write time, not at load time, so `studio.yml`-generated model files will need to write real values for every option Gauge Pro declares, not just the ones a scenario cares about.
