# EdgeTX Color UI: Definitive Graphics Quality and Performance Implementation Plan

**Status:** implementation authority and sequencing baseline  
**Repository baseline:** `b706c4004` on `main`  
**Prepared:** 2026-07-22  
**Primary scope:** EdgeTX color-display radios, including HTX-class targets, the color LCD simulator, and the WebAssembly display path  
**Input guide:** `myplans/born.md` was reviewed as advisory material and is intentionally left unchanged.

This document is the implementation plan. If a later design note, ticket, or local optimization conflicts with it, this plan controls unless the architecture owners record a replacement decision with measurements and migration consequences.

The words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** describe requirements, recommendations, and optional work respectively.

---

## 1. Executive decision

The color UI must be improved by evolving the existing EdgeTX architecture, not by creating a second UI platform beside it and not by performing a screen-by-screen visual rewrite on top of the current foundations.

The correct order is:

1. Make target capabilities, measurements, reproducibility, and regression tests authoritative.
2. Establish UI ownership, lifetime, memory, and display-backend contracts.
3. Move from the unsupported EdgeTX LVGL 8.2 fork to a supported LVGL 9 stable line through a measured, isolated compatibility layer.
4. Correct each display pipeline according to its hardware presentation model.
5. Establish bounded state delivery and resource pipelines.
6. Build the design system and responsive component primitives on those foundations.
7. Migrate and optimize screens in value/risk waves.
8. Harden Lua, continuous performance testing, hardware-in-the-loop testing, and rollout.

This order deliberately postpones broad visual redesign. New themes, animation, and polished screen layouts created before the ownership, rendering, resource, and LVGL migration work would be expensive rework and would conceal rather than solve the dominant performance problems.

The implementation MUST preserve the existing proven assets:

- `Window`, `Page`, `PageGroup`, the controls library, and the screen hierarchy;
- `EdgeTxStyles`, `ThemeManager`, and existing theme compatibility;
- the simulator, WebAssembly renderer, and existing pixel-level LCD tests;
- legacy `BitmapBuffer` and Lua drawing compatibility while a stable replacement surface is developed;
- existing target-specific display drivers until their replacements reach hardware parity.

The implementation MUST replace or contain the following liabilities:

- private LVGL refresh-state access in target code;
- synchronous UI re-entry and waits that call rendering recursively;
- full-cache maintenance and full-frame assumptions where the backend does not require them;
- the PA01 display's busy-waited transfer path;
- unbounded or poorly owned subscriptions, resources, and transient allocations;
- synchronous SD decode/conversion on interaction-critical paths;
- screen polling that reformats or redraws unchanged data;
- compile-time layout scaling used as a substitute for component-level responsive layout;
- an unsupported LVGL foundation with a manually curated, difficult-to-audit source list.

---

## 2. Scope, invariants, and exclusions

### 2.1 In scope

- Graphical correctness, visual consistency, interaction latency, frame stability, memory behavior, and rendering throughput on color LCD targets.
- LTDC direct-framebuffer targets, rotated/legacy LTDC targets, and external-controller/serial display targets.
- LVGL integration, display presentation, cache coherency, DMA2D use, invalidation, frame pacing, fonts, images, themes, reusable components, and responsive layouts.
- State delivery from firmware subsystems to UI views, provided that flight-control ownership and timing are not changed.
- Lua widget scheduling and rendering boundaries.
- Simulator, WebAssembly, unit, golden-image, performance, soak, and hardware-in-the-loop tests needed to prove the work.
- Tooling and build changes that make UI output reproducible.

### 2.2 Non-negotiable system invariants

1. Mixer, input, RF, telemetry, audio, storage safety, and watchdog timing MUST take precedence over graphical work.
2. Only the UI execution context MAY mutate LVGL objects. Interrupts and other tasks MUST communicate through bounded, non-blocking handoff mechanisms.
3. A display flush is complete only when the backend no longer needs the render buffer. `lv_display_flush_ready` MUST express that fact, not merely that a transfer was submitted.
4. Cache-coherency operations MUST cover exact, cache-line-aligned memory ranges or a demonstrably faster safe alternative. They MUST NOT rely on undocumented incidental coherency.
5. Every queue, cache, pool, deferred operation, trace buffer, and Lua budget MUST have a fixed target-specific upper bound and an observable overflow policy.
6. No critical navigation path MAY synchronously load or decode arbitrary files from the SD card.
7. Visual changes MUST be testable at every supported resolution class and interaction mode.
8. A backend optimization MUST have a CPU fallback and MUST be selected by measured capability, not by MCU family name alone.

### 2.3 Explicit exclusions

- Monochrome UI redesign is not part of this program, except for shared code that must remain compatible.
- Flight model semantics, mixer algorithms, RF protocols, and persisted model formats are not to be redesigned.
- A general-purpose desktop-style reactive framework is not to be introduced.
- The program does not require all legacy Lua drawing APIs to become declarative.
- Animation is not a foundation. It is introduced only after frame pacing and input latency meet their gates.

---

## 3. Repository baseline and corrections to the advisory guide

The implementation must start from the repository that exists, not from a generic embedded-GUI model.

| Area | Current repository evidence | Required interpretation |
|---|---|---|
| LVGL | EdgeTX submodule on `release/v8.2`; sources are manually selected in `radio/src/gui/colorlcd/CMakeListsLVGL.txt` | Treat LVGL migration and fork-delta retirement as a foundation project, not a library toggle. |
| Pixel format | `LV_COLOR_DEPTH` is 16; framebuffers use RGB565-compatible `pixel_t` | Preserve RGB565 as the display/storage default. Use alpha formats only for bounded assets/layers. |
| Main LTDC pipeline | `radio/src/gui/colorlcd/lcd.cpp` allocates two full-screen SDRAM framebuffers and normally registers LVGL direct mode | Do not add a third generic double-buffer abstraction. Formalize ownership and presentation of the buffers already present. |
| H7/H7RS LTDC targets | Drivers swap LTDC addresses at vertical blank and commonly perform a whole D-cache clean | Measure and replace unnecessarily broad cache work; preserve VBlank-safe presentation. |
| Legacy rotated targets | Horus handling copies invalid areas and reads private LVGL refresh internals | Remove the private dependency before or during the LVGL 9 port. Use public invalidation/presentation contracts. |
| External-controller target | PA01 waits for frame mark and sends an area through a controller/DMA path | It needs asynchronous partial rendering and transfer scheduling, not the same policy as LTDC. |
| UI runtime | `LvglWrapper`, `MainWindow`, `Window`, controls, screens, themes, and widgets already form a C++ UI layer | Evolve this layer. Do not create a parallel `EdgeUI` hierarchy. |
| Notifications | `libui/messaging` provides synchronous callback delivery with simple lifetime handling | Harden it as a bounded UI notification mechanism; it is not yet a state model or a typed observer framework. |
| Lua | Widgets already have instruction limits and both `BitmapBuffer` and LVGL-facing APIs | Add time/memory/cadence/invalidation governance; do not claim Lua is unbounded or require an immediate API rewrite. |
| Assets | Built-in assets/fonts use generated/LZ4 paths; arbitrary bitmap loading uses STB and can decode to RGBA8888 before RGB565 conversion | Preserve the efficient built-in path and replace the blocking, high-peak-memory runtime path. |
| Tests | Exact PNG comparisons exist for LCD primitives at 480x272; some font tests are disabled because generation is not reproducible | Extend this infrastructure into full-screen and multi-target regression testing. Do not build a disconnected test system. |
| Layout | Compile-time orientation/scale macros and target-specific assets already support several geometries | Replace coarse scaling incrementally with layout classes and component constraints; retain macros until each migrated surface has parity. |

### 3.1 Concrete framebuffer cost

Two RGB565 full-screen buffers consume:

| Resolution | One buffer | Two buffers |
|---|---:|---:|
| 320 x 240 | 153,600 bytes | 307,200 bytes |
| 480 x 272 | 261,120 bytes | 522,240 bytes |
| 800 x 480 | 768,000 bytes | 1,536,000 bytes |

These values exclude alignment, LVGL heap, decoded images, temporary layers, caches, trace buffers, and Lua memory. Every target budget must account for the complete peak, not just static framebuffer symbols.

---

## 4. Target architecture

### 4.1 Architectural flow

```text
firmware producers / ISRs / tasks
              |
       bounded value capture
              v
     immutable UiSnapshot store  <---- UI commands ---- views/controllers
              |                                      |
    change versions + cadence                         v
              +------------------------------> reusable components
                                                      |
                                               public LVGL adapter
                                                      |
                                                DisplayBackend
                 +--------------------+---------------+------------------+
                 |                    |                                  |
          LTDC direct/VBlank   LTDC rotated/legacy         controller partial/DMA
                 |                    |                                  |
          framebuffer + cache   transform/copy policy           transfer state machine
```

The layers have strict responsibilities:

- Producers expose compact values or immutable snapshots; they never own UI objects.
- Presenters/controllers convert domain state into view state and emit explicit commands.
- Components own visual behavior and invalidate only when their effective state changes.
- The LVGL adapter contains version-specific calls and private compatibility details during migration.
- `DisplayBackend` owns render-buffer configuration, flush submission, cache policy, and presentation completion.
- Board drivers own registers, interrupts, clocks, DMA channels, and physical display sequencing.

### 4.2 Capability profiles, not broad performance tiers

The build MUST generate a compile-time `UiTargetCapabilities` record from board configuration and validated CMake data. A target is classified by presentation model and actual resources, not merely as F4 or H7.

Required fields:

```cpp
struct UiTargetCapabilities {
  uint16_t width;
  uint16_t height;
  PixelFormat pixelFormat;           // RGB565 initially
  PresentationMode presentation;     // LtdcDirect, LtdcRotated, ControllerPartial, Simulator
  BufferMode bufferMode;             // FullSingle, FullDouble, PartialSingle, PartialDouble
  uint32_t renderBufferBytes;
  uint32_t uiHeapBytes;
  uint32_t imageCacheBytes;
  uint32_t transientLayerBytes;
  uint16_t cacheLineBytes;
  uint16_t panelRefreshMilliHz;
  uint16_t transferAlignmentPixels;
  bool cacheableFramebuffer;
  bool hasDma2d;
  Dma2dOperations acceleratedOps;
  bool touch;
  bool rotary;
  MotionProfile motionProfile;
};
```

Initial backend families are:

1. **LTDC direct, full-frame, VBlank presentation.** Examples include current H7/H7RS color targets. The principal constraints are render bandwidth, SDRAM contention, cache maintenance, and buffer state.
2. **LTDC legacy/rotated.** Existing F4/Horus paths may require transform or dirty-region synchronization. The principal constraints are memory bandwidth, transform cost, private LVGL coupling, and lower CPU headroom.
3. **Controller partial transfer.** PA01-class displays have an explicit transfer window and transfer completion. The principal constraints are bus throughput, tear synchronization, DMA scheduling, and buffer height.
4. **Simulator/WebAssembly.** These provide deterministic functional testing and developer feedback but MUST NOT be used to infer target cache, bus, or DMA performance.

The profile is data, not a scattering of new preprocessor branches. Target-specific register operations remain in board drivers; policy decisions consume the capability record.

### 4.3 Ownership rules

- `UiRuntime` owns LVGL initialization, tick/timer service, input adapters, root windows, deferred deletion, and the snapshot-consumption cycle.
- `DisplayBackend` owns LVGL display registration and every render buffer from the time it is granted until LVGL is told the flush is complete.
- An LTDC presentation state machine owns explicit `Rendering`, `Queued`, `Scanning`, and `Free` states. State transitions occur only in the UI context or a narrowly defined ISR handoff.
- Image/font resources are referenced through handles. Views do not directly free shared decoder output.
- `Window` wrappers retain their current ownership model during migration, but deletion MUST be idempotent and subscriptions MUST be detached before the wrapped LVGL object can emit another callback.
- UI commands modify domain data through existing validated firmware APIs. Views do not mutate shared model structures directly.

---

## 5. Performance and quality contract

Absolute thresholds must be confirmed from Phase 1 measurements on reference hardware. Teams MUST NOT weaken a threshold merely because a regression becomes visible. Any adjustment requires an architecture decision record containing raw traces and the reason the original threshold was invalid.

### 5.1 Reference scenarios

Every scenario has a cold and warm variant where applicable:

1. Boot to usable main view.
2. Wake/backlight-on to first interactive frame.
3. Main-view steady telemetry with representative widgets.
4. Rapid page switching between two populated main views.
5. Open model selection, scroll 100 entries, select, and return.
6. Open a dense form, edit a value by touch and rotary, cancel, repeat, then commit.
7. Open telemetry/sensor list with live changes and scroll while updates arrive.
8. Open file/image browser containing oversized and malformed test assets.
9. Show, interact with, and dismiss a modal/keyboard/choice dialog.
10. Run representative first-party and third-party Lua widgets for 30 minutes.
11. Continuous navigation soak for 8 hours with language/theme changes.
12. Worst supported localization: long strings, CJK font path, and RTL where supported.

### 5.2 Metric definitions

The following measurements are mandatory:

- **Input-to-feedback latency:** hardware input timestamp to first presented pixel that acknowledges it.
- **View-open latency:** accepted navigation event to the first complete usable view; placeholders do not count when the primary control is unavailable.
- **Frame work time:** UI update, layout, LVGL render, cache maintenance, submission, and presentation wait recorded separately.
- **Deadline miss:** presentation not ready for the selected panel frame boundary.
- **Invalidation efficiency:** rendered pixels divided by screen pixels and rendered pixels divided by semantically changed pixels.
- **Transfer efficiency:** bytes transferred divided by minimum dirty-region bytes for controller displays.
- **Allocation behavior:** count, bytes, peak, fragmentation proxy, and failure by memory domain and scenario phase.
- **Resource latency:** queue, read, decode, conversion, upload/cache insertion, and cancellation times.
- **Lua cost:** instructions, wall time, allocation delta, invalidated pixels, and consecutive budget violations per widget.
- **Firmware safety:** maximum and percentile mixer/task latency, ISR duration, lost telemetry/input events, and watchdog margin while UI scenarios run.

### 5.3 Provisional release gates

These are initial requirements; Phase 1 converts them to board-specific budgets without making them less demanding than the measured baseline unless correctness requires it.

- Flight-critical task/ISR worst-case timing MUST NOT regress outside the existing accepted jitter envelope. A board owner must sign off on the captured evidence.
- Warm input feedback SHOULD be presented within 50 ms at p95 and 100 ms at p99 on all color targets.
- Warm opening of frequent lightweight views SHOULD complete within 100 ms at p95; complex views SHOULD complete within 200 ms at p95 or display an immediately interactive shell while noncritical content loads asynchronously.
- The p99 frame work time MUST remain inside the configured presentation budget during the main-view, list-scroll, and dense-form scenarios.
- No unbounded wait, file read, image decode, cache-wide clean, or heap-growth loop is permitted in the input-to-feedback path.
- Steady-state navigation and animation MUST reach a zero-allocation or fixed-pool behavior after caches are warm. Explicit bounded resource loads are exempt and separately measured.
- The final frame of every interaction MUST be correct even when intermediate frames are coalesced.
- Every supported resolution class, theme class, and required language class MUST pass its visual baseline.
- Repeated navigation and dialog creation/destruction MUST show no monotonic heap loss over the 8-hour soak.

Frame budgets are derived from actual panel timing. For example, a 30 Hz presentation boundary is 33.33 ms, but the UI is not entitled to consume that entire interval because other firmware work and safety margin remain. The final per-target budget must state both the panel interval and the maximum UI work allowance.

---

## 6. Dependency and release gates

```text
Phase 0 Baseline
    |
Phase 1 Observability + deterministic tests
    |
Phase 2 ownership/lifetime/memory/backend seams
    |
Phase 3 supported LVGL 9 foundation
    |
Phase 4 correct per-backend rendering and presentation
    |
    +--------> Phase 5 state delivery
    |                    |
    +--------> Phase 6 resources/fonts
                         |
                 Phase 7 design system/components
                         |
                 Phase 8 migration waves
                         |
                 Phase 9 Lua extension surface
                         |
                 Phase 10 continuous qualification
                         |
                 Phase 11 rollout and retirement
```

Phases 5 and 6 MAY proceed in parallel only after the Phase 4 contracts are stable. Screen migration MUST NOT begin before the Phase 3 LVGL API is established and the Phase 7 primitives used by that screen are accepted. Qualification work begins in Phase 1 and grows continuously; Phase 10 is when all gates become release-blocking.

---

## 7. Phase 0 — Program baseline and reproducibility

**Objective:** create an authoritative inventory and repeatable baseline before changing behavior.

### 0.1 Appoint owners and freeze terminology

Assign one owner for each of the following: UI runtime/LVGL, H7 LTDC, F4/rotated LTDC, controller-transfer displays, memory/cache, design system, resources/fonts, Lua, simulator/tests, and release qualification. One person may hold several roles; no work package may be ownerless.

Create architecture decision records for:

- supported LVGL line and fork policy;
- render-buffer strategy per backend;
- UI execution context and inter-task handoff;
- memory domains and allocator policy;
- resource cache policy;
- responsive layout classes;
- animation/motion policy.

Each record MUST include alternatives, measurements, affected targets, rollback path, and removal date for transitional code.

### 0.2 Build the target capability manifest

1. Enumerate every color target from target CMake, board definitions, and hardware JSON.
2. For each target record MCU, clock, SRAM, SDRAM/PSRAM, flash, display resolution, pixel clock/refresh, panel orientation, controller/bus, touch/input devices, DMA2D availability, cacheability, and current display driver.
3. Validate the record against hardware, not only macros. Record unknown values explicitly and assign measurement tasks.
4. Generate `UiTargetCapabilities` during the build and assert impossible combinations at compile time.
5. Add a host-readable capability dump to simulator/build artifacts so CI can prove which policy was compiled.

**Deliverables:** versioned capability source, generated header, human-readable matrix, and compile-time validation tests.

### 0.3 Make builds reproducible

1. Pin and initialize all submodules in CI, including the EdgeTX LVGL fork.
2. Record compiler, linker, asset-generator, font-converter, compression-tool, and Python/package versions.
3. Preserve map files, section sizes, compiler flags, capability dumps, and firmware hashes for benchmark builds.
4. Define `UI_BASELINE`, `UI_TRACE`, and production-equivalent benchmark configurations. Tracing MUST be removable or near-zero overhead when disabled.
5. Add a command that produces simulator binaries and reference-board firmware from a clean checkout without relying on developer-global tools.

### 0.4 Capture the LVGL fork delta

Fetch the exact EdgeTX LVGL submodule and compare it with its upstream base. Classify every patch as:

- already upstream in LVGL 9;
- still required but suitable for upstream contribution;
- EdgeTX-specific and isolated behind an adapter;
- obsolete;
- unknown, requiring a reproducer.

The output MUST identify any ABI/private-header assumptions and the exact callers in EdgeTX. No LVGL upgrade estimate is accepted without this inventory.

### 0.5 Select the reference hardware set

At minimum, qualification requires:

- one 800x480 LTDC H7/H7RS target;
- one 480x272 LTDC H7 target;
- one legacy F4/Horus rotated or synchronization-sensitive target;
- the 320x240 PA01 controller-transfer target;
- color LCD simulator and WebAssembly output.

If HTX hardware introduces a distinct controller, memory system, or orientation, it becomes an additional reference profile rather than being assumed equivalent to H7.

### Phase 0 exit gate

- Every shipping color target maps to exactly one validated backend/capability profile.
- Clean benchmark builds are reproducible and archived.
- LVGL fork delta is classified.
- Reference hardware is available to CI or to an accountable test owner.
- The existing firmware and UI baseline hashes, sizes, and raw scenario recordings are preserved.

---

## 8. Phase 1 — Observability and deterministic regression harness

**Objective:** make latency, rendering work, memory, and visual output observable before optimization.

### 1.1 Add a low-overhead trace system

Implement a fixed-size binary ring buffer. On target, use the DWT cycle counter or the most precise monotonic counter available. Trace writes MUST avoid formatting, file I/O, dynamic allocation, and locks that can block critical tasks.

Required events include:

- input sampled, input dispatched, UI state changed, first relevant invalidation;
- `lv_timer_handler` start/end and nested-call rejection;
- layout start/end; render start/end; flush submit; DMA start/end; VBlank queue/swap; flush ready;
- dirty rectangle count and union area;
- cache clean/invalidate start/end and byte count;
- screen constructor, first usable state, deletion, and deferred-trash drain;
- allocation/free by domain, high-water mark, and failure;
- SD read, decode, conversion, cache insert/evict/cancel;
- snapshot publish/consume, queue coalescing, and overflow;
- Lua widget start/end, instruction count, allocation delta, invalidation area, and budget action.

Use numeric event IDs and offline symbolization. A trace overflow increments a counter and retains the most recent complete records; it MUST NOT stall the UI.

### 1.2 Add metric aggregation

Build fixed-bucket histograms and high-water counters for p50, p95, p99, maximum, counts, and bytes. Do not calculate expensive percentiles in the hot path. Export raw traces and summary metrics through an existing diagnostic channel, simulator file, or developer menu.

Extend `UI_PERF_MONITOR` into a developer overlay that can show, at minimum:

- actual presented FPS and deadline misses;
- current/p95 UI work time;
- invalidated/rendered pixels;
- cache-maintenance bytes;
- framebuffer/backend state;
- UI heap current/peak and largest-allocation failure;
- resource queue/cache usage;
- Lua violations.

The overlay itself MUST be separately measured and disabled for release qualification runs.

### 1.3 Establish deterministic simulator scenarios

Create a scenario runner that injects timestamped keys, rotary steps, touch coordinates, telemetry/state fixtures, timer progression, theme/language, and SD fixture responses. It MUST:

- use a deterministic seed and clock;
- capture named checkpoints and final framebuffer images;
- record the active resolution/capability profile;
- detect leaked windows/resources/subscriptions;
- support headless execution;
- replay a failed run locally.

Build on `radio/src/tests/lcd_480x272.cpp` and existing screenshot helpers. Exact pixel comparison remains appropriate for primitives and deterministic generated assets. Full-view tests may use a tightly bounded perceptual/tolerance comparison only when exact output cannot be made portable; every tolerated difference must still produce a diff image.

### 1.4 Capture baseline performance

Run all Section 5 scenarios on the reference boards. Capture at least 30 runs for short interactions and long enough samples for stable p99 values. Include cold boot/cache, warm cache, worst supported language, default theme, one high-cost theme, representative Lua widgets, and concurrent telemetry/audio/storage activity.

Store:

- raw traces and environment/build identity;
- metric summaries;
- framebuffer checkpoints;
- flash/RAM/map deltas;
- profiler/logic-analyzer captures where transfer or VBlank timing is ambiguous;
- known anomalies with ownership.

### 1.5 Introduce staged CI gates

During instrumentation development, performance comparisons are informational. Once the same scenario is stable across five clean baseline runs:

1. fail on correctness, crash, leak, and visual mismatch immediately;
2. warn on more than 5% p95 or size regression;
3. require review on more than 10% regression or any p99 deadline regression;
4. make accepted target-specific absolute budgets blocking in Phase 10.

Noise bands MUST be derived from run variance. A percentage threshold is not a substitute for an absolute usability or safety threshold.

### Phase 1 exit gate

- Input-to-present, render, transfer, cache, memory, resource, and Lua costs can be separated in a trace.
- Reference scenarios run deterministically in simulator and reproducibly on hardware.
- Existing primitive golden tests still pass and at least four full-view checkpoints exist at each resolution class.
- Baseline traces and budgets are reviewed by firmware and board owners.
- No subsequent performance change may merge without before/after evidence.

---

## 9. Phase 2 — UI safety, lifetime, memory, and backend boundaries

**Objective:** establish correctness boundaries that all later optimization and visual work can rely on.

### 2.1 Enforce one UI execution context

1. Document the current caller graph for `LvglWrapper::run`, window creation/deletion, display flush completion, input adapters, messaging, and task/ISR callbacks.
2. Add debug assertions that LVGL object creation, mutation, deletion, invalidation, and timer handling run in the UI context.
3. Replace direct cross-task UI calls with bounded handoff records containing values or identifiers, never LVGL pointers.
4. ISRs may only acknowledge hardware, advance a small backend state, timestamp, and notify the UI/driver through an ISR-safe primitive.
5. Define overflow policy per channel: coalesce latest state, reject command with error, or drop noncritical diagnostic event. Silent unbounded growth is forbidden.

### 2.2 Remove recursive rendering and blocking UI waits

Audit `LvglWrapper` nested handling, `lv_refr_now`, modal `blockUntilClose` patterns, frame-mark waits, file reads, and any loop that pumps LVGL to simulate synchronicity.

Replace them with:

- asynchronous modal completion callbacks/futures whose continuation runs in the UI context;
- explicit screen lifecycle states (`Constructing`, `Interactive`, `Closing`, `Destroyed`);
- timer-driven or event-driven progress for long operations;
- transfer completion from DMA/interrupt events;
- a guard that records and rejects unintended nested `lv_timer_handler` calls in debug builds.

Temporary synchronous adapters MAY remain for unmigrated callers, but they MUST be outside render/input callbacks, measured, marked deprecated, and assigned a removal wave.

### 2.3 Define `DisplayBackend`

Extract the policy currently mixed through `lcd.cpp` and target callbacks into a narrow interface. The interface must represent the actual LVGL version in use through a separate adapter.

```cpp
class DisplayBackend {
 public:
  virtual DisplayConfiguration configuration() const = 0;
  virtual void initialize() = 0;
  virtual FlushSubmission submit(const Rect& area,
                                 PixelBuffer buffer,
                                 bool lastInCycle) = 0;
  virtual void service() = 0;
  virtual DisplayStatistics statistics() const = 0;
};
```

`submit` must declare whether completion is immediate or deferred. A deferred token is completed exactly once from the driver state machine. LVGL-specific `flush_ready` calls stay in the adapter, not board drivers.

Do not over-abstract register operations. The boundary exists to make buffer/presentation semantics testable and to stop screens/LVGL glue from knowing target interrupts.

### 2.4 Define memory domains

Publish a linker-verified memory map for:

- render buffers;
- LVGL heap;
- UI object/control allocation;
- DMA descriptors and transfer buffers;
- image cache and decoder scratch;
- font buffers/glyph cache;
- temporary layers;
- Lua heap/widget state;
- trace storage.

For each domain specify location, cacheability, DMA accessibility, alignment, owner, maximum size, allocator, failure policy, and metrics. Add link-time or startup assertions for alignment and non-overlap. Cache-line constants come from the target capability, never a magic local value.

Use fixed pools or arenas where lifetime is uniform and fragmentation risk is material. Do not replace every `malloc` mechanically; instrument first, then select domains. All allocation wrappers must preserve existing out-of-memory safety behavior and add source-domain accounting.

### 2.5 Harden object and subscription lifetime

Update `Window`/deferred deletion and `libui/messaging` in small, test-backed steps:

1. Introduce move-only subscription tokens or scoped connections that unsubscribe before owner destruction.
2. Make dispatch reentrancy-safe: unsubscribe/subscribe during delivery cannot invalidate iteration or call a destroyed receiver.
3. Separate immediate UI-local notifications from queued cross-context state handoffs.
4. Replace anonymous integer conventions with typed topics and typed payload structures where data is required.
5. Bound subscribers and queue entries; expose overflow and high-water metrics.
6. Ensure deferred deletion detaches input, timers, subscriptions, animations, and resource callbacks before destroying LVGL objects.
7. Add unit tests for self-unsubscribe, deleting another subscriber, nested publish, queued destruction, duplicate close, and overflow.

Do not enable LVGL 8's message module as a substitute. The project needs an ownership and state-delivery contract that survives the LVGL migration.

### Phase 2 exit gate

- Debug builds detect off-context LVGL calls and recursive handler entry.
- No reference scenario relies on a blocking display wait or recursive refresh.
- Display backends can be exercised with fake buffers/completion events in host tests.
- Memory domains and upper bounds are published for every reference target.
- Lifetime/reentrancy tests pass under sanitizers in host builds where supported.
- Existing screens remain visually and functionally equivalent.

---

## 10. Phase 3 — Supported LVGL foundation

**Objective:** establish a maintainable supported LVGL 9 base before large component or screen investment.

LVGL 8.2 is no longer supported upstream. The program MUST migrate to a supported LVGL 9 stable line. At the time of this plan, that means the pinned LVGL 9.5 patch line; at the Phase 3 start gate, select the newest stable LVGL 9 minor that is in active upstream support and has completed the spike below. Do not target `master` and do not freeze indefinitely on an unsupported intermediate release.

### 3.1 Build a version adapter before porting screens

Create a small `UiLvgl` integration module containing only:

- initialization and configuration;
- display creation, buffer registration, render mode, flush callback, and completion;
- input-device registration;
- tick/timer invocation;
- theme/style bootstrap;
- image/font decoder registration;
- invalidation/refresh diagnostic hooks;
- compatibility helpers whose semantics differ between v8 and v9.

Project screens and controls SHOULD continue using public LVGL APIs directly when they are stable and simple. The adapter is not a mirror of the whole LVGL API; it is a quarantine for porting-sensitive integration.

### 3.2 Remove private LVGL dependencies

Replace `_lv_refr_get_disp_refreshing`, direct access to invalid-area arrays, internal headers, and any other private symbols. For the legacy rotated pipeline, expose dirty regions through supported driver/render hooks or maintain synchronization inside the backend state machine.

Add a CI check that rejects newly included LVGL private headers or underscore-prefixed private symbols outside the temporary migration directory.

### 3.3 Execute the migration spike

Port the adapter, a minimal root window, one form, one scrolling list, one modal, one image, one theme, touch/rotary input, and all display backends to LVGL 9. Run them on:

- simulator at 320x240, 480x272, and 800x480;
- one direct LTDC board;
- the legacy rotated board;
- PA01 controller-transfer hardware.

Measure flash, static RAM, UI heap, render time, invalidation, image/font behavior, input behavior, and output pixels against the Phase 1 baselines. Record every fork patch and API adaptation.

The spike is time-boxed as an investigation, not as permission to abandon the migration. A deferral is allowed only for a demonstrated hard blocker such as an unresolvable target memory overflow or incorrect public-driver semantics. The blocker record must include a minimal reproducer, upstream issue/engagement, quantified fallback cost, and a sunset date. General porting effort is not a blocker.

### 3.4 Complete the LVGL 9 port

1. Pin the selected stable release by commit and retain a small, auditable EdgeTX fork only if required.
2. Reapply only classified, still-required patches; upstream generally useful fixes.
3. Update configuration intentionally. Do not copy the v8 configuration file wholesale. For every changed default, record flash/RAM/render consequences.
4. Convert display registration to v9 render modes. Use direct mode only for backends with full-screen buffers and correct synchronization. Use partial mode for controller-transfer backends.
5. Validate v9 direct-mode dirty-area synchronization; do not retain redundant manual copies without evidence.
6. Port image decoder/cache, filesystem, fonts, themes, input, timers, animations, layouts, and custom draw hooks.
7. Preserve RGB565 output and explicitly validate byte order, opacity, premultiplication expectations, chroma key behavior, and screenshot pixels.
8. Replace the manually fragile source list with a generated or centrally maintained manifest that can be diffed against the pinned LVGL build. Keep unused modules disabled to control footprint.
9. Compile third-party sources with deliberate optimization and warning policy. Exceptions must be local and documented.

### 3.5 Establish an upgrade cadence

- Track supported LVGL stable minors quarterly.
- Run the simulator/golden/performance suite against the next stable line on a non-release branch.
- Keep EdgeTX-specific patches small, documented, tested, and proposed upstream where appropriate.
- Do not combine an LVGL minor upgrade with broad visual changes in the same review series.

### Phase 3 exit gate

- All color targets build on the selected supported LVGL 9 line.
- Reference boards pass functional, pixel, memory, and safety regressions.
- No production target code reads private LVGL refresh internals.
- The EdgeTX patch set is classified and minimal.
- The source/configuration manifest is auditable and reproducible.
- Transitional v8 code has an explicit removal commit or has already been removed.

---

## 11. Phase 4 — Display-pipeline correctness and optimization

**Objective:** make buffer ownership, cache coherency, transfer, and presentation correct and optimal for each backend.

Do not implement a single universal “dirty rectangles + DMA2D + double buffering” policy. Those mechanisms have different costs and semantics on each display family.

### 4.1 Common measurement matrix

For every backend, benchmark:

- one versus two buffers where hardware permits;
- direct/full/partial render mode where meaningful;
- unioned dirty area versus bounded rectangle list;
- full-cache clean versus per-region clean;
- CPU versus DMA2D for fill, copy, RGB565 blend, and transform across size buckets;
- opaque versus alpha-heavy views;
- list scroll, modal open, theme background, and full-screen transition;
- concurrent SD, audio, telemetry, and Lua load.

Use crossover tables rather than assumptions. DMA setup and cache maintenance can make CPU operations faster for small regions.

### 4.2 LTDC direct/VBlank backend

Implement an explicit state machine:

1. LVGL renders only into a buffer in `Rendering` state.
2. On the final flush, clean required cache ranges, mark the buffer `Queued`, and request an LTDC shadow-register reload at VBlank.
3. The VBlank/line event moves the queued buffer to `Scanning`, releases the previous scanning buffer to `Free`, and records the presentation timestamp.
4. Only then is a buffer reusable. Flush completion semantics must match the LVGL render-mode contract; if LVGL needs the render buffer only until queuing, keep a separate present token so input-to-present metrics remain accurate.
5. At most one queued frame is retained. A newer complete frame MAY replace an older not-yet-scanned frame if LVGL ownership is preserved and the final state cannot be lost.

Cache work:

- Align start down and end up to cache-line boundaries.
- For a list of dirty regions, compare merged region byte cost plus call overhead with a full-frame clean using measured thresholds.
- Never clean unrelated address space with global `SCB_CleanDCache()` in the steady presentation path unless target evidence proves it is both safe and faster.
- Ensure the LTDC reads the same physical format and stride that LVGL wrote.
- Record cache-clean bytes and time per frame.

Validate with a high-speed camera or logic analyzer when software timestamps cannot prove tear-free VBlank switching.

### 4.3 Legacy rotated LTDC backend

1. Remove `std::vector` and any heap activity from flush/invalidation. Use a fixed-capacity rectangle set with deterministic merge/overflow-to-full-frame behavior.
2. Stop reading LVGL internal invalid-area storage.
3. Evaluate, in order:
   - native LVGL/display rotation supported by the selected public API;
   - LTDC/controller orientation configuration;
   - DMA2D-assisted transform if the hardware operation is actually supported;
   - bounded CPU/DMA copy of public dirty areas;
   - full-frame transform only as the measured fallback.
4. Keep front/back synchronization correct when only changed regions are rendered. The buffer about to become the next render target must contain an accurate copy of unchanged pixels.
5. Define overflow behavior: when the rectangle set exceeds capacity or transform alignment becomes unsafe, synchronize the full frame and increment a metric.
6. Test odd coordinates, one-pixel edges, clipping, overlapping rectangles, palette/alpha paths, and repeated partial updates.

### 4.4 PA01/controller-partial backend

The current frame-mark busy wait must be replaced with a non-blocking state machine.

1. Measure panel transfer rate, frame-mark/TE timing, command overhead, DMA maximum transfer, and safe address-window alignment.
2. Configure LVGL partial render buffers. Start with approximately one tenth of the screen as an experiment, then select line count from measured transfer and RAM tradeoffs.
3. Prefer two partial buffers if one can render while the other transfers without starving other DMA users; otherwise use a single buffer with explicit back-pressure.
4. `submit` sets the address window, aligns/cleans the buffer range, and queues transfer. It never spins on frame mark or DMA completion.
5. A TE/frame-mark interrupt opens the safe transfer window. DMA completion advances or finishes the transfer and eventually completes the LVGL flush.
6. Split a large dirty area into bounded stripes when required by bus/DMA constraints. Preserve pixel row stride and do not expose partially updated final frames as complete.
7. Coalesce overlapping rectangles, but never expand transfer area blindly when the extra bus bytes cost more than another command window.
8. Provide timeout/recovery: abort the transfer safely, reset the controller state if necessary, show a diagnostic counter, and preserve UI responsiveness.

Acceptance requires zero busy-wait time, correct flush ownership, no tearing under the reference camera test, and no lost input while a full-screen transfer is active.

### 4.5 DMA2D acceleration policy

DMA2D is an operation-specific engine, not a global performance switch.

1. Implement measured kernels for supported RGB565 fill, copy, conversion, and blend operations.
2. Integrate through the LVGL 9 draw-unit/backend extension point where possible; keep board initialization and interrupt handling separate.
3. Define source/destination formats, strides, alignment, opacity semantics, overlap restrictions, and cache operations in each kernel contract.
4. Use size/shape crossover thresholds from benchmarks. Small spans stay on CPU.
5. Submit asynchronously only when useful work can proceed safely; otherwise a synchronous wrapper may be faster and simpler.
6. Bound the command queue and arbitrate with other DMA users.
7. On error/timeout, reset the peripheral, increment diagnostics, and execute a correct CPU fallback.
8. Compare total elapsed time and system contention, not only DMA active time.

Do not enable an old LVGL DMA2D option without proving it supports the selected LVGL line, formats, cache model, and operation set.

### 4.6 Frame pacing and invalidation

- Derive presentation cadence from actual panel timing and UI workload.
- Separate state-update cadence from presentation cadence; telemetry may update at 20 Hz while static labels remain unchanged.
- Coalesce multiple state changes before a render cycle, but never delay direct input acknowledgement beyond the latency budget.
- Stop unconditional full-screen invalidation and screen-wide alpha where a component-local invalidation suffices.
- Use full refresh only for transitions or backends where measurement proves it cheaper.
- Disable or reduce expensive shadows, gradients, opacity layers, and large rounded clipping on profiles that miss budgets. Make this a semantic quality level, not scattered screen conditionals.
- Avoid an always-running timer when no visible component, animation, input, or queued operation needs service; preserve wake responsiveness.

### Phase 4 exit gate

- Each reference backend has a documented buffer/presentation state diagram and proof of flush ownership.
- No display path busy-waits for VBlank, frame mark, DMA, or file I/O.
- Cache maintenance is range-based or has measured justification for full-frame/global behavior.
- Dirty-region correctness passes randomized pixel tests and hardware tear tests.
- Backend p99 work time and firmware safety gates pass under concurrent load.
- CPU fallbacks pass the same output tests as accelerated paths.

---

## 12. Phase 5 — Bounded state delivery and presentation model

**Objective:** make UI work proportional to visible state changes, with clear read/write boundaries.

This phase does not introduce a heavyweight MVVM framework. It introduces compact snapshots, typed view state, presenters/controllers, and explicit commands where they remove unsafe coupling or repeated work.

### 5.1 Create immutable UI snapshots

Define small snapshot groups aligned to update rates and screen needs, for example:

- `UiInputSnapshot`;
- `UiModelSummarySnapshot`;
- `UiTelemetrySnapshot`;
- `UiRadioStatusSnapshot`;
- `UiModuleStatusSnapshot`;
- `UiStorageStatusSnapshot`.

Each snapshot contains plain values, stable identifiers, timestamps/validity, and a monotonically increasing version. It contains no LVGL objects, owning strings, filesystem handles, or mutable domain pointers.

Publication rules:

- Producers copy data at defined safe points.
- The UI reads a coherent published version without blocking the producer.
- Latest-value state is coalesced; event sequences that must not be lost use a separate bounded command/event queue.
- Expensive formatting and localization occur only when dependent values change.
- Snapshot cost, missed versions, queue overflow, and staleness are traced.

### 5.2 Introduce presenters/controllers incrementally

For each migrated screen:

1. Define a typed `ViewState` containing exactly what the view renders.
2. Implement a presenter/controller that maps snapshots to `ViewState`, compares with the previous state, and emits minimal property changes.
3. Route user intent through typed commands using existing validated model/radio APIs.
4. Keep transactional edit behavior explicit: begin, validate, preview if safe, commit, or cancel.
5. Unit-test mapping, formatting, invalid states, permission/availability, commit/cancel, and rapid updates without LVGL.

Views own focus, layout, and visuals. Presenters do not manipulate raw LVGL objects.

### 5.3 Replace unconditional polling

Audit `MainWindow::run`, `ViewMain::refreshWidgets`, `WidgetsContainer::refreshWidgets`, `DynamicText::checkEvents`, page checks, status bars, timers, and list rows.

Classify updates:

- **Immediate:** user feedback, alarms, modal state.
- **Fast periodic:** sticks, timers, rapidly changing telemetry; nominally 20–50 Hz only when visible.
- **Normal periodic:** ordinary telemetry/status; nominally 5–20 Hz.
- **Slow periodic:** storage, battery estimate, network/module metadata; nominally 1–5 Hz.
- **Event-only:** configuration text, labels, layout, theme, model identity.

These frequencies are starting ranges, not universal timers. Visible components subscribe to the minimum cadence they need. Hidden windows, background tabs, and occluded widgets suspend presentation work while their latest snapshot remains available.

`DynamicText` and equivalent controls MUST cache the formatted result and call LVGL setters only when the effective text/style changes.

### 5.4 Preserve command safety

- Domain mutation is never performed from a draw callback.
- Commands validate current model identity/version to prevent committing against stale state.
- Destructive or safety-sensitive edits keep existing confirmation and storage semantics.
- Long operations return progress/completion asynchronously.
- Rejected commands produce a visible, localized reason and trace event.

### Phase 5 exit gate

- Representative dashboard, form, list, and modal surfaces use typed view state.
- Their steady-state work is proportional to changed visible values.
- Snapshot publication cannot block flight-critical producers.
- Command mapping and commit/cancel behavior have host unit tests.
- No migrated view directly traverses mutable cross-task domain structures.

---

## 13. Phase 6 — Resource, image, and font pipeline

**Objective:** make assets deterministic, bounded, fast to display, and independent of synchronous SD decode.

### 6.1 Build a resource manifest

Every built-in image, icon, font, and theme resource MUST have generated metadata:

- stable resource ID and source path;
- dimensions and pixel/alpha format;
- compressed and decoded byte sizes;
- intended density/layout classes;
- required alignment and memory domain;
- cache class (`Permanent`, `Screen`, `Transient`, `Streamed`);
- fallback/placeholder;
- license/source attribution where applicable.

Validate the manifest during the build. Reject duplicate IDs, unsupported formats, oversized critical assets, missing variants, and accidental RGBA8888 assets where RGB565/ARGB4444/mask is sufficient.

### 6.2 Preprocess built-in assets

- Convert and scale built-in graphics at build time, not on the radio.
- Prefer RGB565 for opaque images, compact alpha/mask formats for icons, and ARGB4444 only when its quality/space tradeoff is accepted.
- Generate resolution/density variants only where scaling quality or runtime cost warrants them.
- Evaluate RGB565 banding and dithering offline per asset. Do not impose runtime dithering globally.
- Pack related small assets to reduce filesystem overhead only if lookup and update simplicity remain acceptable.
- Keep boot, error, core navigation, and recovery assets in firmware or guaranteed internal storage.

### 6.3 Replace synchronous arbitrary image loading

Create a bounded `ImageService` with request handles and generation tokens:

```cpp
ImageRequest request(ResourceKey key,
                     Size requestedSize,
                     ImagePriority priority,
                     ImageCompletion completion);
void cancel(ImageRequest request);
```

Required behavior:

1. Validate headers, dimensions, decoded-byte limit, format, and path before allocation.
2. Resolve the required display size before decode.
3. Read/decode outside the LVGL mutation path using an existing safe worker mechanism; only final handle delivery enters the UI context.
4. Prefer row/stripe decode or decoder-native downsampling. Do not decode a large image to full RGBA8888 merely to shrink and convert it.
5. Convert directly to the cache/display format when possible.
6. Show a deterministic placeholder immediately.
7. Cancel requests when the owning view closes or rebinds; generation tokens prevent late results from updating recycled rows.
8. Bound concurrent reads, decoder scratch, output bytes, and completion queue.
9. Handle SD removal, timeout, malformed input, allocation failure, and cancellation without a dangling callback.

If background decode cannot be made safe on a target, use a cooperative striped decoder with a strict per-frame time budget. Never perform an unbounded decode in one UI callback.

### 6.4 Replace item-count caching with byte budgets

The current small item-count image cache does not represent wildly different decoded costs. Introduce per-target byte budgets and LRU/segmented policy:

- permanent built-in resources are not evicted;
- current-screen resources have priority over prefetch;
- transient resources are evicted first;
- cache entries are reference-counted or lease-owned;
- eviction never frees a buffer still used by LVGL/DMA;
- cache hit/miss, bytes, decode cost saved, eviction reason, and admission rejection are measured.

Large one-shot images may bypass the cache. Prefetch only after the interactive frame and only when resource/IO budgets are idle.

### 6.5 Make font generation reproducible

1. Pin font sources, licenses, converter version, glyph lists, hinting/options, compression tool, and locale subsets.
2. Generate binary-identical outputs in CI and local clean builds.
3. Document fallback order for Latin, symbols, CJK, and RTL scripts.
4. Measure font buffer, glyph cache, decompression scratch, lookup, and render cost at each size.
5. Keep frequently used UI glyphs in fast accessible storage; load large locale subsets deliberately.
6. Add missing-glyph diagnostics in developer builds and a release test that scans localized strings against font coverage.
7. Re-enable font golden tests once generation is deterministic.

### Phase 6 exit gate

- Built-in assets and fonts are reproducible and manifest-validated.
- No reference interaction blocks on arbitrary SD image decode.
- Oversized/malformed image fixtures cannot exhaust or corrupt UI memory.
- Resource and cache memory stay inside per-target budgets through the soak test.
- Font golden tests and locale coverage tests pass.

---

## 14. Phase 7 — Design system, components, and responsive layout

**Objective:** create the visual and interaction primitives that make subsequent screen work fast, consistent, and maintainable.

Build on `EdgeTxStyles`, `ThemeManager`, `Window`, existing controls, and Page/PageGroup. New abstractions are accepted only when they remove duplicated behavior across at least two real surfaces or encode a system-wide requirement.

### 7.1 Define semantic design tokens

Tokens MUST describe meaning, not screen-specific colors:

- background/surface/elevated/overlay;
- primary/secondary text, disabled text, inverse text;
- accent, focus, selection, edit, success, warning, error, critical alarm;
- separator, outline, shadow where allowed;
- typography roles: title, section, body, value, label, caption, monospace/data;
- spacing scale, radii, border widths, elevation policy;
- minimum touch target, rotary focus inset, scrollbar/indicator sizes;
- motion duration/easing and reduced-motion substitutions.

Generate or centrally define tokens with theme overrides. Existing themes receive a compatibility mapping. Validate contrast on actual RGB565 quantized colors, not only desktop source values.

### 7.2 Define component contracts

Prioritize components that appear everywhere:

- application shell/status bar/header;
- section header and divider;
- button/icon button;
- list and recyclable list row;
- text/numeric field, choice field, toggle, slider;
- dialog, confirmation, choice sheet, keyboard;
- tab/page navigation;
- toast/banner/progress/empty/error/loading states;
- image/icon/resource view;
- graph/value/status primitives.

Every component specification includes:

- semantic purpose and non-goals;
- properties/events and ownership;
- touch, rotary, keyboard/simulator navigation;
- normal, focused, pressed, editing, selected, disabled, unavailable, warning, error, and loading states as applicable;
- minimum hit area and focus visibility;
- layout behavior at every class;
- localization/RTL behavior;
- invalidation behavior and expected allocation pattern;
- per-profile rendering restrictions;
- screenshot and interaction tests.

Do not accept a visually attractive component that cannot be operated completely with rotary/keys where the target requires it.

### 7.3 Replace coarse scaling with layout classes

Define layout from usable width/height, orientation, density, and input mode. Initial classes should cover:

- compact portrait around 320x240;
- standard landscape around 480x272;
- wide landscape around 800x480;
- any genuinely distinct HTX geometry proven by the capability matrix.

Use LVGL grid/flex and content constraints for new components. Breakpoints choose composition, column count, navigation pattern, and information density; they do not merely multiply every coordinate.

Migration rules:

- Existing `LAYOUT_SIZE`, `LAYOUT_SCALED`, `LAYOUT_ORIENTATION`, `NARROW_LAYOUT`, and hard coordinates remain until their owning screen is migrated.
- A migrated screen has one semantic layout with explicit breakpoint variations.
- Do not mix legacy absolute positioning and new responsive ownership within the same component subtree unless the boundary is documented.
- Text expansion, font ascent/descent, RTL mirroring, scrollbar space, safe edges, and touch targets participate in layout tests.

### 7.4 Establish visual-quality policy

- Prefer hierarchy, typography, spacing, and color over expensive decoration.
- Shadows, blur-like effects, opacity layers, gradients, and oversized rounded clipping require profile-specific performance evidence.
- Use iconography consistently and retain text where ambiguity affects safety.
- Define data-density rules for telemetry and configuration; do not hide critical values for visual minimalism.
- Establish reduced-motion behavior and disable nonessential continuous animations when battery/performance policy requires it.
- Use animation only for spatial continuity, state change, and acknowledgement. Decorative loops are forbidden on operational views.

### 7.5 Create a component gallery

Add a simulator/developer screen that renders every component state at each layout class, theme, input mode, and representative language. It becomes the primary review and golden-image surface for design-system changes.

### Phase 7 exit gate

- Semantic tokens and compatibility mappings render correctly on every reference profile.
- Core components pass touch, rotary, focus, localization, and screenshot tests.
- The component gallery covers all states and layout classes.
- Steady-state component gallery operation stays inside allocation/render budgets.
- New screen migration can use accepted primitives without local style duplication.

---

## 15. Phase 8 — Screen migration and high-return optimization waves

**Objective:** convert user-visible surfaces in an order that maximizes reuse and impact after foundations are stable.

Each wave starts with one representative vertical slice and ends only after hardware validation. Do not open dozens of partially migrated screens.

### 8.1 Pilot set

Migrate four surfaces first:

1. **Dynamic dashboard/main view:** proves snapshot cadence, widgets, theme background, and partial invalidation.
2. **Large model/file list:** proves recyclable rows, async resources, scrolling, focus, and controller-transfer behavior.
3. **Dense settings form:** proves typed view state, edit transactions, touch/rotary parity, localization, and responsive layout.
4. **Modal/choice/keyboard flow:** proves asynchronous lifecycle, focus restoration, overlay cost, and cancellation.

Do not select only easy screens. This pilot is intended to expose architecture gaps before broad adoption.

### 8.2 Wave A — Shared shell and interaction primitives

Migrate application shell, top/status regions, common headers, dialogs, forms, fields, choice lists, buttons, keyboards, loading/error states, and common navigation. Remove duplicate legacy variants only after all callers migrate.

Expected return: maximum consistency and reuse; every later screen becomes cheaper.

### 8.3 Wave B — Main views and model selection

Migrate main-view chrome, standard first-party widgets, view navigation, model selection, model summary, alarms, and high-frequency status indicators.

Requirements:

- visible-only cadence scheduling;
- per-widget budget/invalidation tracing;
- no full main-view redraw for a single changing value;
- immediate input acknowledgement under live telemetry;
- async thumbnails/backgrounds with built-in fallback;
- stable widget layout and focus after data updates.

Expected return: largest day-to-day perceived improvement.

### 8.4 Wave C — Large and live collections

Migrate telemetry/sensor lists, file browsers, model lists, logs/tools lists, and any table with repeated rows.

Use row recycling only after measurement shows construction/render cost or memory warrants it. A recyclable list MUST:

- allocate a fixed visible-row pool plus small overscan;
- bind rows by stable item ID and generation;
- cancel late image/data requests on rebind;
- preserve focus/selection by item ID, not row object;
- keep scroll position stable while live data changes;
- use fixed-height rows where possible; variable-height virtualization requires measured need and indexed heights;
- update only changed visible cells;
- provide correct empty/loading/error/end states.

### 8.5 Wave D — Model configuration and safety-sensitive editors

Migrate inputs, mixes, outputs, logical switches, special functions, curves, flight modes, timers, telemetry configuration, and related editors.

This wave follows the general UI because mistakes can alter aircraft behavior. It requires:

- explicit begin/preview/validate/commit/cancel transactions;
- unchanged persisted model semantics;
- unit tests for boundary values, unavailable sources, dependency changes, and cancel;
- clear dirty/unsaved state;
- no commit caused solely by focus movement unless existing behavior explicitly requires it;
- interaction replay against the legacy result where possible;
- board-owner and experienced-user review.

### 8.6 Wave E — Radio, module, maintenance, and tools

Migrate radio setup, hardware, module settings, trainer, storage, calibration, diagnostics, update/recovery, and developer tools. Recovery-critical screens must retain internal assets and work when SD/resources are unavailable.

### 8.7 Per-screen Definition of Done

A screen is migrated only when:

- it uses accepted tokens/components and typed state/commands;
- all layout classes, themes, required locales, and input modes pass;
- visual hierarchy is reviewed on physical displays, including RGB565 color and viewing angle;
- no interaction-critical synchronous I/O remains;
- allocations, render cost, invalidation, cache work, and input-to-present meet budgets;
- hidden/occluded behavior is suspended correctly;
- construction/destruction, modal interruptions, theme/language changes, SD removal, and model change are tested;
- screenshot, event replay, unit, and hardware evidence are attached;
- replaced legacy code and styles are removed in the same wave or assigned a dated removal ticket.

### Phase 8 exit gate

- All shipping color screens satisfy the per-screen Definition of Done.
- Legacy visual primitives have no remaining production callers or a documented compatibility obligation.
- Main-view, list, form, and modal scenarios meet p95/p99 budgets on every reference profile.
- User-visible behavior and persisted model semantics are release-reviewed.

---

## 16. Phase 9 — Lua and extension governance

**Objective:** preserve the value and compatibility of Lua while preventing one extension from destabilizing the UI.

### 9.1 Retain and measure existing APIs

Keep classic `BitmapBuffer` widgets and existing LVGL-facing Lua APIs during migration. Add per-widget metrics for instructions, wall time, memory delta, resource requests, invalidated pixels, and cadence. Existing instruction limits remain in force.

### 9.2 Add a multi-dimensional budget

Instruction count alone does not capture native calls, image work, allocation, or bus pressure. Define target-profile budgets for:

- maximum wall time per invocation;
- instructions per update/refresh;
- memory current/peak;
- resource/cache bytes;
- invalidated area and requested refresh cadence;
- consecutive and rolling-window violations.

Enforcement sequence:

1. record and show developer warning;
2. reduce refresh cadence and coalesce requests;
3. suspend the offending widget with a visible recoverable error;
4. allow explicit user retry or removal.

Never crash or starve the core UI because a widget exceeds budget.

### 9.3 Make widget scheduling visibility-aware

- Foreground refresh runs only when the widget is visible and its update interval or event requires it.
- Background execution uses a separately bounded budget and cannot invoke LVGL.
- Hidden widgets retain compact state but do not redraw.
- Widgets invalidate their own region; full-screen invalidation requires explicit privileged capability.
- Async resource callbacks use generation tokens and are canceled when a widget is deleted/reconfigured.

### 9.4 Offer a stable component API after Phase 7

Only after native components are stable, expose a versioned declarative subset for common labels, values, icons, lists, buttons, and layout. Include capability negotiation so scripts can degrade on older firmware or constrained profiles.

The new API must have:

- bounded object and memory counts;
- no raw LVGL pointer exposure;
- stable semantic tokens;
- explicit event and lifetime ownership;
- simulator tests and examples;
- a documented compatibility policy.

Legacy drawing remains available for specialized graphics unless measurement demonstrates an unacceptable system risk.

### Phase 9 exit gate

- A misbehaving widget cannot break input latency, exhaust UI memory, or cause unbounded redraw.
- Representative legacy widgets remain compatible.
- New component API, if shipped, is versioned and capability-tested.
- Lua soak scenarios pass on the most constrained supported color profile.

---

## 17. Phase 10 — Continuous visual, performance, and hardware qualification

**Objective:** convert the program's measurements into permanent release protection.

### 10.1 Visual matrix

For each accepted screen/component checkpoint, cover:

- 320x240 portrait/compact, 480x272 landscape, and 800x480 wide;
- default, light/high-contrast if supported, and representative custom theme;
- English, longest-string fixture, representative CJK, and RTL where the feature is supported;
- touch and rotary/key focus states;
- normal, disabled, unavailable, loading, empty, warning, error, and modal states;
- RGB565 exact output for primitives and deterministic assets.

Golden updates require a generated diff, reviewer explanation, and design-system approval when shared tokens/components change. A bulk “accept all” golden update is forbidden.

### 10.2 Functional and fuzz coverage

- deterministic event replay for primary workflows;
- randomized navigation with valid/invalid domain-state transitions;
- touch coordinates at edges, overlaps, and outside hit regions;
- rapid rotary/key repeat and simultaneous telemetry updates;
- repeated create/close/theme/language/model changes;
- malformed image/font/theme/resource inputs;
- SD insertion/removal during requests;
- display/DMA timeout and recovery injection;
- snapshot queue overflow/coalescing;
- Lua timeout, allocation failure, and late callback.

Run host sanitizers for simulator-compatible ownership code and target-specific fault injection for driver paths.

### 10.3 Performance gates

CI stores a time series keyed by target profile, scenario, compiler, and firmware commit. Gate:

- input-to-feedback p95/p99;
- view-open p95/p99;
- frame work and missed deadlines;
- cache-maintenance bytes/time;
- dirty/rendered/transferred pixels;
- allocation count/peak/fragmentation proxy;
- flash, static RAM, LVGL heap, resource cache, and stack high-water;
- Lua budget violations;
- critical task/ISR timing.

Simulator performance is a regression signal, not target proof. Hardware measurements control target acceptance.

### 10.4 Hardware-in-the-loop

Automate where feasible:

- firmware flash and capability verification;
- scripted key/rotary/touch stimulus;
- serial/trace extraction;
- framebuffer checksum or capture;
- logic-analyzer capture for LTDC reload, TE, DMA, and transfer boundaries;
- camera-based tear/animation inspection for reference builds;
- power sampling during idle, active UI, animation, and Lua load.

Retain a manual physical-display review checklist for viewing angle, brightness, contrast, touch feel, rotary focus visibility, and artifacts that screenshots cannot show.

### 10.5 Long-duration qualification

Run 8-hour navigation/resource/Lua soak and an overnight steady telemetry/main-view soak on each backend family. Fail on:

- monotonic memory loss;
- stuck buffer/backend state;
- missed flush completion;
- growing queue/cache beyond bounds;
- input starvation;
- watchdog reset or critical timing violation;
- accumulating image/font corruption;
- display recovery failure after injected timeout.

### Phase 10 exit gate

- Visual, functional, memory, size, latency, and firmware-safety gates block release.
- Every backend family runs in hardware qualification.
- Failure artifacts are reproducible from stored build identity and scenario seed.
- Accepted waivers have owners, expiry releases, and user impact.

---

## 18. Phase 11 — Controlled rollout and legacy retirement

**Objective:** ship incrementally without maintaining two permanent architectures.

### 11.1 Feature control

Use compile-time or persisted developer flags only at clean boundaries: backend implementation, LVGL migration test build, or whole screen migration. Do not branch every component between old and new behavior.

Flags MUST have:

- owner and removal release;
- compatible persisted data;
- trace/build identification;
- tested rollback path;
- no hidden production-only combination.

### 11.2 Rollout order

1. Simulator and developer builds.
2. Reference-board nightly builds.
3. Internal/experienced tester channel covering each backend family.
4. Opt-in preview release if required.
5. Default enablement after two stable qualification cycles.
6. Remove old path after rollback window and data compatibility review.

### 11.3 Documentation and handoff

Publish:

- architecture and ownership diagrams;
- target capability and memory tables;
- LVGL fork/upgrade policy;
- display backend state diagrams;
- design tokens and component contracts;
- resource/font generation guide;
- presenter/snapshot/command examples;
- Lua performance and compatibility guide;
- benchmark and golden-update instructions;
- triage runbook for display stalls, cache artifacts, image failures, and performance regressions.

### Phase 11 exit gate

- New architecture is the default on all supported color targets.
- Old backend/UI paths and expired flags are removed.
- No unsupported LVGL branch remains in shipping builds.
- Maintainers can reproduce, measure, diagnose, and extend the UI from published documentation.

---

## 19. Mandatory implementation sequence for tickets and reviews

Large phases must be decomposed into mergeable changes. The default order below minimizes review risk and preserves bisectability:

1. Capability inventory and build artifact identity.
2. Trace event IDs and no-op instrumentation API.
3. Input-to-present and render/flush instrumentation.
4. Memory/resource/Lua instrumentation.
5. Deterministic scenario runner and expanded existing golden helpers.
6. Reference baseline capture and provisional budgets.
7. UI-context assertions and cross-context handoff.
8. Subscription/lifetime hardening.
9. `DisplayBackend` extraction with unchanged behavior.
10. Buffer-state host tests and fake backends.
11. Memory-domain accounting and alignment assertions.
12. Remove recursive refresh and synchronous modal adapters from pilot flows.
13. LVGL fork audit and `UiLvgl` adapter.
14. LVGL 9 spike.
15. LVGL 9 port by subsystem, with visual parity after each subsystem.
16. Direct LTDC state/cache optimization.
17. Rotated LTDC public dirty-region implementation.
18. PA01 asynchronous partial-transfer implementation.
19. DMA2D measured kernels and optional activation.
20. Frame pacing/invalidation policy.
21. Snapshot publication and command boundary.
22. Pilot presenters and polling removal.
23. Resource manifest and reproducible fonts.
24. Async image service and byte-budget cache.
25. Semantic tokens and compatibility theme.
26. Core component gallery and layout classes.
27. Four pilot surface migrations.
28. Migration Waves A–E.
29. Lua governance and optional stable component API.
30. Full blocking CI/HIL gates.
31. Staged rollout, legacy removal, and documentation closeout.

Each pull request SHOULD change one contract or one vertically testable behavior. Backend changes MUST include before/after traces and pixel evidence. Visual migrations MUST not be combined with low-level display-driver changes.

---

## 20. Work-package template

Every implementation ticket must contain:

1. **Problem and user/system impact.** Name the scenario and target profiles.
2. **Prerequisites.** Link required prior phase gates and decisions.
3. **Current evidence.** Trace, screenshot, code path, memory map, or reproducer.
4. **Contract changed.** State ownership, API, buffer, timing, layout, or resource semantics.
5. **Implementation steps.** Include error, timeout, cancellation, and fallback behavior.
6. **Budgets.** Flash, RAM, heap, stack, CPU, cache bytes, transfer bytes, and latency as relevant.
7. **Test matrix.** Host, simulator, resolution, hardware, locale, theme, and input.
8. **Before/after evidence.** Raw artifacts, not only a verbal conclusion.
9. **Rollback.** How a faulty change is disabled or reverted without data loss.
10. **Legacy removal.** Code/flag removed now or an owned dated follow-up.

A ticket is not complete when the code compiles. It is complete when its contract, bounded failure behavior, tests, measurements, and migration consequences are proved.

---

## 21. Program-wide prohibitions

The following approaches are rejected unless a new architecture decision with measurements supersedes this document:

- A wholesale UI rewrite.
- A new parallel wrapper/component hierarchy that duplicates `Window`, controls, themes, and pages.
- Optimizing by MCU label alone instead of display/memory capability.
- Assuming two full buffers or dirty rectangles are optimal for every target.
- Enabling DMA2D globally without per-operation crossover data and cache analysis.
- Calling whole-cache maintenance from the steady display path without measured justification.
- Accessing LVGL private refresh structures from board code.
- Calling LVGL from ISR, telemetry, storage, mixer, Lua background, or resource worker contexts.
- Pumping LVGL recursively to make an asynchronous action appear synchronous.
- Busy-waiting on VBlank, TE/frame mark, DMA, storage, or decoder completion.
- Loading arbitrary SD assets synchronously during navigation or draw.
- Caching images by item count without a decoded-byte budget.
- Creating a timer per label/control or setting unchanged LVGL properties every tick.
- Treating proportional coordinate scaling as complete responsive design.
- Adding animation before the profile meets frame and input budgets without it.
- Replacing exact primitive tests with permissive visual tolerances.
- Accepting performance claims based only on simulator results.
- Leaving migration flags or compatibility paths without owner and removal date.

---

## 22. Risk register

| Risk | Consequence | Required mitigation |
|---|---|---|
| LVGL 9 increases flash/RAM on constrained F4 targets | Target may no longer fit or may regress latency | Audit modules/config, retain minimal source set, measure in spike, remove fork baggage, use target-specific optional features; accept deferral only with hard evidence and sunset. |
| EdgeTX fork behavior is not upstream | Subtle rendering/input regression | Classify every patch, build minimal reproducers, upstream fixes, isolate remaining delta. |
| Cache optimization introduces intermittent corruption | Rare visual artifacts or stale pixels | Alignment assertions, randomized dirty tests, stress concurrent DMA, hardware traces, safe full-frame fallback counter. |
| DMA2D contends with SDRAM or other DMA | Worse system latency despite faster kernel | Measure end-to-end contention, arbitrate, size thresholds, CPU fallback. |
| Async resource completion targets a deleted/recycled view | Use-after-free or wrong image | Scoped handles, cancellation, generation tokens, UI-context delivery, sanitizer/fuzz tests. |
| Snapshot copying is too large/frequent | Producer or UI timing regression | Partition by cadence, compact POD values, versioning/coalescing, measure publication cost. |
| Design system reduces information density | Operational usability regression | Physical-radio review, expert-user testing, density variants, preserve critical data hierarchy. |
| Golden tests become costly/noisy | Developers bypass tests | Reproducible fonts/assets, stable fixtures, component gallery, exact/tolerant policy, actionable diff artifacts. |
| Lua compatibility breaks | Ecosystem rejection | Keep legacy API, capability/version negotiation, representative script corpus, staged warnings. |
| Long-lived dual paths accumulate | Maintenance burden and inconsistent bugs | Whole-surface flags only, removal dates, parity gates, remove legacy code wave by wave. |
| Performance work harms critical firmware timing | Safety and reliability regression | Measure critical tasks in every hardware scenario; board/firmware owner approval is mandatory. |

---

## 23. Expected technical outcomes

When this plan is complete:

- EdgeTX color UI runs on a supported, maintainable LVGL 9 base with a small auditable integration surface.
- Every display family has correct, explicit buffer ownership, asynchronous presentation, and measured cache/DMA policy.
- Input response and frame stability are protected by hardware-derived budgets rather than subjective smoothness.
- Screens consume coherent bounded state and update only changed visible properties.
- Assets and fonts are deterministic; arbitrary resources load asynchronously within byte budgets.
- Shared semantic components provide consistent touch, rotary, focus, localization, theme, and responsive behavior.
- Lua remains compatible but cannot monopolize time, memory, invalidation, or resource bandwidth.
- Simulator, visual tests, performance traces, and hardware-in-the-loop runs make regressions reproducible and release-blocking.
- Future screens can be built quickly because layout, components, data delivery, resources, and rendering contracts are already correct.

---

## 24. Repository touchpoint map

This is a routing guide, not permission to place all new code in these files.

| Concern | Current touchpoints to inspect/evolve |
|---|---|
| LVGL configuration/build | `radio/src/gui/colorlcd/lv_conf.h`, `radio/src/gui/colorlcd/CMakeListsLVGL.txt`, `radio/src/thirdparty/lvgl` |
| Display registration/buffers | `radio/src/gui/colorlcd/lcd.cpp` and related headers |
| UI runtime/lifecycle | `radio/src/gui/colorlcd/LvglWrapper.*`, `radio/src/gui/colorlcd/libui/window.*`, `mainwindow.*`, page/control classes |
| Notifications | `radio/src/gui/colorlcd/libui/messaging.*` |
| LTDC drivers | `radio/src/boards/rm-h750/lcd_driver_480.cpp`, `lcd_driver_800.cpp`, H7S78/C14 and equivalent board drivers |
| Rotated legacy path | Horus/F4 target LCD driver and current invalid-area copy logic |
| Controller transfer | PA01 LCD driver/controller/DMA implementation |
| Themes/styles/layout | `radio/src/gui/colorlcd/etx_lv_theme.*`, `themes/`, `libui/`, screen layout macros |
| Widgets/Lua | `radio/src/gui/colorlcd/widgets/`, `radio/src/gui/colorlcd/lua/` and Lua instruction/memory integration |
| Assets/fonts | `radio/src/bitmaps/`, `radio/src/fonts/lvgl/`, bitmap buffer/STB/LZ4 loaders and generators |
| Tests | `radio/src/tests/lcd_480x272.cpp`, `radio/src/tests/colorlcd.cpp`, simulator tests/fixtures |
| Simulator/Web | `radio/src/targets/simu/`, `web/src/lib/lcd-renderer.ts` |
| Target capability sources | target/board CMake and hardware JSON definitions |

Before editing a touchpoint, use the codebase knowledge graph to identify callers and downstream dependencies. Literal/config/asset searches may use repository text search when graph coverage is insufficient.

---

## 25. Authoritative technical references

Repository code and measurements remain authoritative for EdgeTX behavior. The following upstream references constrain the implementation:

- [LVGL 8.2 display interface](https://docs.lvgl.io/8.2/porting/display.html) — documents the current direct/full/partial buffer expectations and the need to synchronize changed areas with two direct buffers.
- [LVGL 9 display interface](https://docs.lvgl.io/9.1/porting/display.html) — documents the v9 render modes and direct-buffer synchronization model used by the migration design.
- [LVGL repository and release policy](https://docs.lvgl.io/9.5/introduction/repo.html) — establishes supported release-line policy; v8.2 is unsupported.
- [LVGL upstream repository/releases](https://github.com/lvgl/lvgl) — source and stable release identity.
- [EdgeTX LVGL fork, release/v8.2](https://github.com/EdgeTX/lvgl/tree/release/v8.2) — current fork lineage to audit.
- [ST AN4839: STM32F7/H7 Level 1 cache](https://www.st.com/resource/en/application_note/an4839-level-1-cache-on-stm32f7-series-and-stm32h7-series-stmicroelectronics.pdf) — cache-line and DMA coherency requirements.
- [ST AN4861: STM32 LTDC](https://www.st.com/resource/en/application_note/an4861-lcdtft-display-controller-ltdc-on-stm32-mcus-stmicroelectronics.pdf) — LTDC timing, layers, framebuffer, and synchronization considerations.
- [EdgeTX releases](https://github.com/EdgeTX/edgetx/releases) — supported target/release context to revalidate at each rollout gate.

Documentation is not a performance result. Buffer count, cache policy, DMA thresholds, cadence, and memory budgets must be selected from EdgeTX hardware measurements under the scenarios in this plan.
