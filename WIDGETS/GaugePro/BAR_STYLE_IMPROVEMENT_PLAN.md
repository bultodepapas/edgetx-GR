# Gauge Pro v2 — Ambitious Bar Experience Plan

**Document version:** 2.0 — personalization mandate and grilling review integrated
**Date:** 2026-08-09
**Branch:** feat/gauge-v2
**Analysis baseline:** `d46102e26634cadd069e7d44d8a887e421957ee0`
**Scope:** Gauge Pro Bar style only. The dial/clock style is the quality reference and is not being redesigned.

---

## 1. The soul of this work

Gauge Pro is not trying to be another serviceable telemetry bar. A basic rectangle could communicate a percentage, but that would miss the purpose of the project.

The bar must be:

1. **Useful** — flight information is understood correctly and quickly.
2. **Beautiful** — the widget feels deliberate, modern, polished, and enjoyable to look at.
3. **Customizable** — the user can make it belong to their radio, theme, model, and personal taste.

These are not three optional layers. Functionality is the admission requirement, beauty is the quality bar, and personalization is part of the HTX identity.

The target experience is a modern 2026 radio-control instrument:

- rich without becoming crowded;
- animated without becoming distracting;
- colorful without relying on color alone;
- configurable without forcing every user to become a designer;
- theme-aware without confusing HTX interface colors with telemetry severity;
- attractive in a tiny top-bar slot, a short telemetry strip, a square zone, a tall zone, and a full-screen layout.

The bar should feel like the dial's sibling: the same confidence, information hierarchy, and attention to detail, expressed on a linear axis.

> A pilot must be able to read the value, understand its position and severity, and notice a meaningful change at a glance—while still enjoying the instrument every time the radio is used.

---

## 2. Product outcome

Gauge Pro v2 will provide a bar system, not a single hard-coded bar.

The system will combine:

- an excellent classic default;
- useful appearance presets;
- independent user overrides;
- multiple meaningful bar faces;
- adaptive layouts for every HTX widget-zone family;
- classic, theme-adaptive, and custom color palettes;
- thoughtful motion and state feedback;
- retained-mode LVGL rendering with strict object and instruction budgets.

The default remains universally understandable:

- normal: green;
- warning: amber/yellow;
- critical: red;
- data text and surrounding surfaces: active HTX theme roles;
- face: continuous precision rail;
- thickness: automatic medium;
- motion: refined but calm;
- contrast assistance: automatic.

No existing model should need to be reconfigured to receive a substantially better bar.

---

## 3. Verified repository and firmware facts

This plan is based on the current Gauge Pro implementation and the HTX/EdgeTX code in this repository.

### 3.1 Gauge Pro baseline

- The current widget already has a strong telemetry engine: sources, scale presets, ascending and descending ranges, smoothing, hysteresis, availability, alerts, battery conversion, cell handling, min/max history, and state badges.
- The dial has the visual maturity the bar must reach.
- The current bar is retained-mode and inexpensive, but visually reads as a generic rounded progress bar.
- At the canonical 300 × 70 scene, the current bar uses nine visible objects.
- The current automated baseline passes 38 unit tests and 143 lifecycle/smoke tests.
- The measured bar refresh is approximately 810 Lua instructions, about 4% of the 20,000-instruction test budget.
- The dial's revised worst audited scene uses 33 objects. Rich bar faces may approach that budget, but must not grow without a measured reason.
- The current descending-scale history logic maps both ghost and min markers to history.min. The high historical extreme can disappear. This is a correctness defect and is fixed before cosmetic expansion.

### 3.2 Option contract

- Gauge Pro currently declares 24 positional options.
- HTX/EdgeTX 2.11 stores the first 10 widget options.
- HTX/EdgeTX 2.12+ stores up to 50 widget options.
- Existing option positions and types are a model-data contract. They may not be reordered, removed, or type-changed.
- New options must be appended.
- The extended option budget is therefore 26 slots.
- The settings UI does not provide reliable conditional field hiding. The design must remain understandable when all appended fields are visible.

### 3.3 Theme contract

The firmware theme manager applies theme-defined colors and may also apply background images. The Lua API exposes theme roles through COLOR_THEME values and resolves them through lcd.getColor.

The important roles include:

- PRIMARY1 and PRIMARY2 for primary/inverse ink;
- SECONDARY1, SECONDARY2, and SECONDARY3 for chrome and surfaces;
- FOCUS, EDIT, and ACTIVE for interaction state;
- WARNING for UI warning treatment;
- DISABLED for muted state.

These are interface roles, not a complete telemetry-severity vocabulary. In particular:

- there is no dedicated CRITICAL theme role;
- ACTIVE is not guaranteed to mean “safe” or “green”;
- WARNING can be visually close to red;
- a theme author may choose combinations optimized for controls rather than telemetry rails;
- a wallpaper or layout-owned panel means the exact pixel below a transparent widget is not always knowable.

Therefore, semantic telemetry colors and HTX surface colors must be resolved as two related but separate systems.

### 3.4 Widget-zone contract

The repository contains 16 normal layout templates plus the full-screen app-mode variant, 17 layout files in total:

- 1 × 1, 1 × 2, 1 × 3, 1 × 4, and 1 × 6;
- 2 × 1, 2 × 2, 2 × 3, and 2 × 4;
- 1 + 2, 1 + 3, 1 + 4, 2 + 1, 2 + 3, 4 + 2, and 4 + 2B;
- 1 × 1 app mode.

Their zones use full, half, third, quarter, and sixth fractions of the available widget area. The final pixel size also changes with top bar, flight mode, trims, sliders, screen scale, and target radio.

Top-bar widgets form a separate micro-height family. Their base width is 70 or 74 scaled pixels, and adjacent top-bar slots can be merged.

The existing scaling contract uses LCD_SCALE values for 320, 480, and 800-pixel display families. The bar must be tested against actual resolved rectangles, not only nominal layout names.

### 3.5 LVGL/Lua feasibility

- Rectangles and horizontal/vertical lines make continuous, block, tick, and stepped faces practical.
- Filled triangles are available, so a hexagonal segment can be composed from a center rectangle plus two static end triangles.
- A high segment count of three-object hexagons would be wasteful. Hex count must be capped responsively.
- The Lua wrapper does not currently provide a simple native, runtime-configurable gradient rectangle.
- The portable v2 solution is a gapless sequence of cached color slices that appears continuous at normal viewing distance.
- A future native LVGL gradient binding may be investigated, but the bar cannot require a custom firmware extension to function.
- Every face must build objects once and update properties. No object creation or deletion is allowed in the per-frame refresh path.

### 3.6 Actual Gauge Pro runtime flow

Gauge Pro already has a disciplined lifecycle. The bar work must extend it rather than create a second widget architecture.

| Lifecycle stage | Existing implementation | Contract for the bar redesign |
|---|---|---|
| Radio startup | main.lua declares options and registers the widget; it does not load the implementation | Keep main.lua data-only. Do not load palette tables, face code, or preview assets at radio startup |
| First instance | main.lua memoizes app.lua; app.lua loads 12 modules once per widget path and shares them across instances | Add the minimum new modules to the existing shared module table |
| create | app.create allocates per-instance source, data, history, smoothing, alert, UI, and frame state | Add bar-style state inside the widget table; never store instance state in shared modules |
| update | options are parsed, source metadata is resolved, effective ranges/precision/text are derived, layout is calculated, and structural changes rebuild LVGL | Resolve visual preset, palette mode, face, axis, and responsive geometry here |
| refresh | reset switch, telemetry, one deferred reconfiguration latch, alerts, and renderer update run in that order | Keep telemetry and alerts authoritative; visual motion runs only after raw state is known |
| paint | app.painter selects bar.lua for a bar layout and renderer.lua for a dial | Keep this single dispatch point. Bar faces are internal strategies of bar.lua |

Important lifecycle lessons:

- A source can resolve after widget creation. app.refresh detects the source generation change and reconfigures once.
- Battery cell count can become known after the first valid reading. That also triggers a one-shot reconfiguration.
- Only one expensive reconfiguration latch is handled in a refresh, protecting the 20,000-instruction callback ceiling.
- A structural signature controls whether lvgl.clear and a rebuild occur.
- Non-structural edits update existing objects and flush queued properties without rebuilding.
- No background callback is used because the firmware calls it only while the widget is off-screen.

The new bar system must preserve all six behaviors.

### 3.7 What the data engine already solves

The redesign does not need new telemetry semantics. The current code already provides:

- source resolution and metadata caching;
- bounded late-source retry: once per second for up to 30 attempts;
- timers identified by source family rather than ambiguous names;
- telemetry availability states: unset, invalid/unavailable, valid, stale, and disconnected;
- rejection and recovery from NaN and positive/negative infinity;
- cell-table aggregation as lowest, total, or average;
- Li-Po and Li-Ion percentage curves;
- latched pack cell count;
- source-aware scale presets for RSSI, dBm, RQly, SNR, battery, temperature, RPM, current, capacity, fuel, throttle, altitude, speed, distance, satellites, and vibration;
- high-is-good and low-is-good state ranges;
- descending scale support;
- automatic repair when both thresholds lie outside the effective scale;
- two-percent hysteresis that degrades immediately and recovers only outside the deadband;
- radio-owned min/max sibling history when trustworthy, with local fallback tracking;
- alert delay, switch gating, repeat timing, tone, vibration, and brownout re-arming.

The bar is a view over this model. Face code may consume normalized values and semantic state; it may not duplicate source reading, range construction, battery logic, hysteresis, history collection, or alert decisions.

### 3.8 Existing bar implementation: exact anatomy

The current bar is compact and reliable:

- one theme-derived neutral track rectangle;
- one active fill rectangle whose width follows the smoothed value;
- threshold lines for every internal range boundary except Static mode;
- one peak-hold ghost line;
- one additional minimum-history line;
- value and optional unit;
- source name when height is at least 46 scaled pixels;
- state badge when width is at least 120 scaled pixels;
- critical pulse on the active fill;
- shared theme-aware badge ink and value/unit anchoring from renderer.lua.

At 300 × 70, nine objects are normally visible. The bar builds threshold marks after the fill so they remain visible on top of it.

The current responsive bar layout already contains a valuable five-rung degradation ladder:

1. full state pill and preferred bar thickness;
2. full pill with a reduced bar;
3. minimally padded pill;
4. bare pill with outline only;
5. no state row as the last resort.

It also reserves marker overhang and badge outline in the vertical budget, clamps very short bars inside their zone, fits value/unit from a widest sample, and uses LCD_SCALE-aware geometry. These behaviors are hard-won and must become the compact fallback for every new face.

### 3.9 Current bar limitations found in code

The visual redesign should target these concrete gaps:

| Current behavior | Consequence | Required change |
|---|---|---|
| bar.lua is horizontal-only | Tall zones cannot become first-class linear instruments | Introduce an orientation-neutral axis model and vertical layouts |
| The body is always one rounded fill over one track | Every use case reads like a generic progress bar | Add face strategies while retaining shared telemetry/state layers |
| Rail, Threshold, and Sections build the same bar structure | Three user-facing modes are visually almost identical on the bar | Implement real permanent rails and semantic section bands for every face |
| Gradient changes the single fill to one color at the current value | It is a value-dependent color, not a spatial continuous gradient | Add prebuilt gapless gradient slices or face segments across the scale |
| There is no exact position head | Discrete faces would lose precise position | Add optional cap, dot, line, or needle head driven by normalized value |
| showMinMaxText and showScale are forced false | The bar ignores “Markers + text” and cannot show scale ends | Add responsive history text and scale/threshold annotation policies |
| Only one explicit history marker is built | Bar history is not symmetrical with the dial | Build both min and max markers when requested |
| On a descending scale, ghost and min marker both land on history.min | history.max is not represented | Keep peak ghost direction-aware and make explicit min/max markers independent |
| State-badge eligibility depends on width only | A narrow vertical bar can lose textual state despite ample height | Make badge policy axis- and region-aware |
| Bar radius always equals half its thickness | Users cannot obtain square or chamfered identities | Resolve end shape per face and thickness |
| Existing fixed gradient cache is keyed only by ramp step | It cannot safely represent multiple custom palettes | Key bounded gradient caches by palette signature and quantized step |
| Badge ink cache is keyed only by fill | A live theme switch can reuse an ink choice calculated for the previous theme | Include resolved theme ink colors in the cache signature or clear it on theme change |

### 3.10 Existing renderer capabilities to reuse

The dial renderer already exposes the correct shared primitives:

- setProp queues only changed properties;
- flush emits at most one lvgl.set per dirty object;
- colorKey separates Static, Threshold, Rail, Gradient, Sections, muted, and timer-warning behavior;
- stateKey keeps semantic state independent from visual color distribution;
- stateText produces NO SOURCE, NO LINK, STALE, NO DATA, WARN, and CRIT;
- updateChip sizes a pill to its text, chooses contrasting theme ink, and preserves WARN/CRIT when informational badges are disabled;
- applyStateInk separates status color from data text;
- anchorUnit keeps the visible value-plus-unit group stable without growing the shared width cache;
- updatePulse provides the existing 1 Hz critical signal;
- updateSourceLabels repaints non-structural label/unit edits;
- persistent point buffers support allocation-free moving lines.

Bar v2 should continue calling these helpers where their behavior is shared. Palette-aware overloads are preferable to copied implementations.

### 3.11 Existing test and visualization infrastructure

The project already has more than a unit-test suite:

- tests/run_tests.lua covers pure geometry, ranges, hysteresis, presets, battery math, option parsing, formatting, fonts, and smoothing;
- tests/smoke_test.lua validates option contracts, LVGL lifecycle, object stability, color semantics, layout containment, state badges, telemetry failure/recovery, history, alerts, late sources, allocation traps, and code-review regressions;
- tests/mock_env.lua validates legal LVGL properties and supports rectangle, line, hline, vline, triangle, arc, circle, and label objects;
- dev/scenes.lua owns a reusable visual scenario catalog;
- dev/svgkit.lua renders the retained object tree to SVG and reports clipping/wrapping;
- dev/gallery.lua produces light/dark visual galleries and coverage manifests;
- dev/collide.lua detects geometric overlaps;
- dev/census.lua counts visible objects;
- dev/instructions.lua probes callback headroom;
- dev/measure_frames.lua measures per-frame instructions, allocations, and moving-line calls.

The current verified baseline is:

| Probe | Result |
|---|---:|
| Pure unit tests | 38 passed, 0 failed |
| Lifecycle/smoke tests | 143 passed, 0 failed |
| Default bar, 300 × 70 | 9 visible objects |
| Default bar, 300 × 60 changing frame | approximately 810 instructions, 4% of the firmware limit |
| Default bar structural update/build probe | approximately 3,800 instructions, 81% headroom |
| Worst current dial callback | approximately 10,200 instructions, 49% headroom |
| Stable-frame allocation probe | approximately 310 B/frame harness/runtime baseline |
| Advancing dial history overhead | approximately 339 B/frame above the plateau baseline |

The present scene catalog uses a hand-authored size matrix. Bar v2 should extend it with the generated firmware-layout atlas described later, not replace the gallery pipeline.

### 3.12 Design lessons learned from the finished dial

The dial is the reference because its implementation already demonstrates the project's visual laws:

1. **Status and data are different channels.** Arcs, rails, thresholds, badge, and pulse communicate state; value, unit, source, and history text prioritize legibility.
2. **Permanent context matters.** Rail and Sections modes show where warning/critical regions live before the value reaches them.
3. **The pointer is neutral and precise.** Its job is position, not severity. The bar head should follow the same principle unless a preset deliberately chooses otherwise.
4. **Paint order replaces expensive clipping.** Moving geometry is created before opaque labels/badges, so the UI naturally occludes it.
5. **Layout owns every physical overhang.** Marker extensions, badge outlines, text baselines, and font boxes are budgeted before objects are built.
6. **Objects are retained; truth changes properties.** The dial never rebuilds because a value moved.
7. **Responsive degradation is explicit.** Detail is removed in a known order rather than disappearing through clipping.
8. **A color mode must change spatial meaning.** Dial Rail, Gradient, and Sections are visually distinct because they reorganize reference color, not merely recolor one arc.
9. **History is a first-class information layer.** Ghost, min, and max have separate semantics.
10. **Beauty survives a disabled effect.** Even without pulse or a needle, hierarchy and state remain understandable.

Bar v2 should translate these laws to a line, not imitate the dial's circular geometry.

### 3.13 Pre-existing hygiene that affects this plan

These are not reasons to redesign unrelated subsystems, but they must be handled before trusting new bar evidence:

- tests/mock_env.lua currently assigns the same 48-pixel height to the 0x600 and 0x700 font flags. Responsive typography tests cannot distinguish the real XXL/LXL candidates until the mock reflects the firmware order.
- telemetry.cleanName removes every leading byte above 127, which can damage a legitimate UTF-8 source name. New label-placement tests should include non-ASCII names after this is bounded to the actual firmware quirk.
- dev/sync-sd.ps1 has a hard-coded runtime module list. It must include bar_style.lua and bar_faces.lua.
- dev/sync-sd.ps1 does not clear stale compiled .luac files, so a radio can continue running old code after a source deployment.
- dev/scenes.lua still contains notes saying some battery/accent/history defects are broken even though the expanded test suite now proves them fixed. Stale captions must be removed before the new gallery is treated as review evidence.
- Scale low/high, warning, and critical are integer VALUE options because of the firmware widget-option type. Bar v2 must document this limitation and must not reinterpret those frozen slots as fixed-point values.

---

## 4. Self-answered grilling review

The grilling skill was requested, and the user explicitly asked the plan to answer the questions rather than pause for an interview. The decision tree below records those answers as product commitments.

### 4.1 Root decision: what are we building?

**Question:** Is this a better progress bar, or a first-class customizable instrument system?

**Answer:** A first-class customizable instrument system. A polished default is necessary, but a single visual treatment would contradict HTX's personalization philosophy.

### 4.2 Usefulness branch

**Question:** What information must survive every visual preset?

**Answer:** Current value, current state, normalized position, threshold direction, unavailable/stale state, and safety badges. History, labels, units, scale marks, and threshold marks adapt to available space.

**Question:** May beauty change telemetry truth?

**Answer:** No. Alert/state calculations always use the raw validated value. Visual smoothing may animate the presentation, but never delay a state transition, alarm, stale state, or critical badge.

**Question:** Does a centered RC control belong in the same system?

**Answer:** Yes, as a semantic zero-origin mode introduced after the telemetry default is stable. It is useful for sticks, channels, trims, and signed outputs. “Center” is not an arbitrary visual midpoint; it is numeric zero.

### 4.3 Beauty branch

**Question:** What makes the bar feel current in 2026?

**Answer:** Excellent proportions, responsive typography, layered depth, perceptually smooth color transitions, precise markers, restrained highlights, and short purposeful animations. Fake gloss, heavy shadows, and decorative motion do not qualify.

**Question:** How many visual representations are justified?

**Answer:** Five production faces plus one optional RC face are justified because each creates a meaningfully different reading pattern:

1. continuous rail;
2. square/soft blocks;
3. hex segments;
4. fine ticks;
5. stepped signal bars;
6. centered dual rail for signed RC sources.

Faces that differ only through decoration are presets, not new renderers.

### 4.4 Customization branch

**Question:** How do beginners and power users both succeed?

**Answer:** Preset plus override resolution. A preset chooses a coherent bundle. Every advanced geometry choice begins with Auto, which inherits the preset. Users can change one thing—such as thickness—without rebuilding the design manually.

**Question:** Should the settings be intentionally minimal?

**Answer:** No. Personalization is a product requirement. The settings should be substantial but structured, named clearly, and limited to controls with visible value.

**Question:** Should all 26 remaining slots be consumed?

**Answer:** No. The plan uses 20 appended slots and reserves six positions for future discoveries. Ambition does not justify exhausting the compatibility budget.

### 4.5 Color and theme branch

**Question:** What is the default palette?

**Answer:** Classic severity: green, amber/yellow, and red. It is the most immediate and internationally familiar status scale.

**Question:** Does classic mode still integrate with the HTX theme?

**Answer:** Yes. Classic mode fixes the semantic status colors but takes text, tracks, borders, muted states, badge ink, and optional panels from the active theme.

**Question:** Can users choose purple/yellow or any other combination?

**Answer:** Yes. A custom three-color palette exposes normal, warning, and critical color pickers. A custom two-color mode uses user endpoints and derives the middle transition.

**Question:** What does Theme Adaptive mean?

**Answer:** The active theme supplies normal/accent and warning candidates plus every surrounding surface. Critical remains a safe red fallback because the firmware has no critical role. Contrast and color-distance checks decide whether structural assistance is needed.

**Question:** May the widget silently replace a user's chosen custom colors?

**Answer:** No. Contrast assistance adds a theme-aware outline, head, badge, or grounding panel. It never rewrites the stored color or secretly changes the requested palette.

### 4.6 Layout branch

**Question:** Is “responsive” satisfied by wide, square, and tall examples?

**Answer:** No. The validation atlas covers every unique zone rectangle generated by the 16 standard layouts, the app-mode layout, and the top bar across supported screen scales and decoration combinations.

**Question:** Should every face render at every size?

**Answer:** Every selected face must degrade safely, but not every tiny zone can show its richest form. Responsive rules lower segment counts, remove low-priority labels, simplify end caps, and preserve the chosen face's identity. If a requested face cannot remain legible, it falls back to its defined compact variant and reports that behavior in documentation.

### 4.7 Motion branch

**Question:** Is animation always enabled?

**Answer:** No. Motion has Off, Essential, Refined, and Expressive profiles. Refined is the default. Safety communication remains clear even when motion is Off.

**Question:** Can animation run continuously for decoration?

**Answer:** Only in the optional Expressive profile, only while the widget is visible, and only within the instruction budget. The normal experience animates changes and states, not empty time.

### 4.8 Compatibility branch

**Question:** What happens on 2.11, where new settings are unavailable?

**Answer:** The responsive classic preset becomes the automatic experience. The bar remains complete and attractive; 2.12+ adds personalization rather than basic correctness.

**Question:** What quality gates can block a face or effect?

**Answer:** Legibility, color-independent state recognition, object count, refresh instructions, allocation stability, and behavior across the complete zone atlas. A beautiful prototype that fails one of these gates remains experimental.

---

## 5. Experience architecture

The final visual style is resolved in layers:

1. **Preset** supplies a coherent starting configuration.
2. **User overrides** replace only the requested preset decisions.
3. **Responsive profile** adapts detail and count to the actual zone.
4. **Palette resolver** separates semantic state colors from theme surfaces.
5. **Contrast assistant** adds structure when the resolved combination needs help.
6. **State engine** applies normal, warning, critical, muted, stale, and unavailable behavior.
7. **Motion profile** describes how changes are presented.

The resolver is deterministic. The same options, theme colors, source metadata, and zone produce the same result.

### 5.1 Precedence

The precedence order is:

user override > preset value > source-aware default > responsive default > safe fallback.

For example:

- Preset Hex Telemetry requests medium thickness and eight hexes.
- The user changes Thickness to Thin.
- A micro zone reduces the segment count to six.
- The final result is a thin six-hex compact variant.

The user keeps control without being allowed to create clipped or unreadable geometry.

### 5.2 Auto is a real feature

Auto is not a placeholder. It means:

- inherit from the selected preset;
- use sensor semantics when helpful;
- use zone geometry to choose detail;
- respect the active theme;
- remain inside the performance budget.

Every advanced CHOICE option should put Auto first unless the setting represents an explicit mode such as Palette.

---

## 6. Color and theme system

### 6.1 Three independent color layers

The palette engine separates:

| Layer | Purpose | Default source |
|---|---|---|
| Semantic status | normal, warning, critical | classic fixed palette |
| Instrument surfaces | track, border, panel, inactive segments, history | active HTX theme |
| Data ink | value, unit, name, scale labels, badge ink | active HTX theme with contrast selection |

Changing a semantic palette should not make the typography stop belonging to the theme. Changing the HTX theme should not erase the meaning of classic severity colors.

The new palette options are bar appearance controls. They must not silently recolor the already-approved dial. Shared renderer helpers receive an optional resolved bar palette; their existing no-palette path stays pixel-identical for Needle and Arc styles.

### 6.2 Palette modes

#### Classic Severity — default

- normal: the existing Normal colour option, default #209058;
- warning: #c86000;
- critical: #ff0000;
- all text/chrome/surfaces: theme-derived.

These are the current calibrated Gauge Pro colors and remain the universal default.

#### Theme Adaptive

- normal candidate: COLOR_THEME_ACTIVE;
- warning candidate: COLOR_THEME_WARNING;
- critical: fixed red fallback;
- track/panel/border/text: theme roles;
- contrast assistant: always evaluated.

Theme Adaptive intentionally follows the user's active HTX identity more strongly. It does not pretend that UI roles provide a perfect severity triad.

If ACTIVE and WARNING are too close in hue/luminance, Theme Adaptive keeps the authored theme colors but strengthens the redundant head, threshold, and badge treatment. It does not manufacture a hidden replacement palette.

#### Custom Three

- user-selected normal color through the existing Normal colour option;
- user-selected warning color;
- user-selected critical color;
- theme surfaces remain the default;
- optional custom track and panel colors are available.

Purple/yellow, blue/orange, monochrome, model-specific liveries, and high-contrast personal palettes are all valid.

#### Custom Two

- normal and critical endpoints are user-selected;
- warning is generated as a luminance-aware midpoint;
- the continuous face can interpolate across the entire rail;
- state labels and marker shapes preserve discrete severity.

This makes duo palettes such as purple/yellow easy without requiring three manual selections.

### 6.3 Existing Colour mode remains an independent axis

The existing slot-8 Colour mode is preserved. It decides how the selected palette is distributed; it does not choose the palette or the face.

| Existing mode | Bar behavior |
|---|---|
| Static | active geometry keeps the existing Normal colour; the state badge still reports truth |
| Threshold | the active portion takes the current semantic state color |
| Rail | Threshold behavior plus permanent warning/critical reference zones |
| Gradient | the active geometry samples the resolved palette across threshold positions |
| Sections | the reference track is divided into semantic state bands |

This produces three composable appearance axes:

- **Bar face:** Continuous, Blocks, Hex, Ticks, Steps, or Dual rail;
- **Palette:** Auto/preset, Classic, Theme Adaptive, Custom Three, or Custom Two;
- **Colour mode:** Static, Threshold, Rail, Gradient, or Sections.

Presets do not overwrite the stored Colour mode because the existing option has no Auto value and the widget cannot know whether its value was user-selected. The default Rail mode already produces the intended Classic Rail experience; users can deliberately change it to Gradient or Sections for any preset.

The existing Normal colour option remains the normal-state custom color. Classic uses its current value with green as the default, preserving existing personalized models. Custom Three combines it with the new warning and critical pickers. Custom Two combines it with the custom critical endpoint.

### 6.4 Gradient rules

- Gradient interpolation is cached by palette signature.
- The portable implementation uses 8–24 gapless slices, selected by rendered length and the remaining whole-face object budget.
- Classic Severity reuses the current calibrated critical → warning → normal constant-luminance ramp.
- Theme/custom ramps preserve the user's exact anchor colors and use gamma-aware interpolation for generated intermediate slices; contrast assistance adds structure rather than pulling custom anchors into the classic luminance window.
- Adjacent slices have no visible gap.
- Threshold positions remain explicit even when the underlying gradient already changes color.
- Critical state never becomes a vague end of a rainbow; its label and marker remain discrete.

An R&D spike may expose native LVGL gradient descriptors to Lua. Adoption requires a measurable object/instruction improvement and a portable segmented fallback. If 24 slices still show unacceptable banding in an 800-pixel large zone, the plan does not relabel visible steps as “continuous”: native support becomes the preferred large-zone path while standard firmware keeps the bounded fallback.

### 6.5 Contrast assistance

Contrast modes:

- **Auto** — default; adds only what is needed.
- **Off** — honors the palette exactly, while WARN/CRIT labels remain mandatory.
- **Strong** — uses a persistent grounding surface and stronger outlines.

Auto can:

- outline the active fill with theme ink;
- use a contrasting position head;
- strengthen threshold marks;
- choose PRIMARY1 or PRIMARY2 for badge ink;
- add a low-opacity theme panel when a wallpaper or custom layout surface is uncertain.

Targets:

- active status geometry: at least 3:1 against a controlled adjacent surface in Auto/Strong;
- ordinary value/label text: at least 4.5:1 where the resolved theme pair permits measurement;
- large state text: at least 3:1, with the higher ratio preferred;
- warning/critical differentiation: a redundant text/shape channel regardless of measured color distance.

Auto does not:

- edit saved colors;
- silently convert purple to green;
- remove user-selected gradients;
- use color as the only warning signal.

### 6.6 Color-independent meaning

Warning and critical remain distinguishable through:

- WARN and CRIT text;
- different marker shapes or head treatment;
- threshold location;
- optional pulse profile;
- segment activation pattern;
- stronger critical outline.

The status badge cannot be disabled for warning or critical. Informational badges may still follow the existing Info badges option.

---

## 7. Bar face catalog

Every face shares the same data, state, threshold, history, palette, label, and motion contracts.

### 7.1 Continuous Precision Rail

The flagship and default face.

- smooth capsule, square, or chamfered ends;
- active fill with an exact position head;
- optional gapless gradient slices;
- permanent threshold context;
- min/max history marker;
- best general-purpose telemetry face.

Compact form: a thinner rail with a side value and reduced annotations.

### 7.2 Blocks

Discrete square or softly rounded cells.

- ideal for batteries, percentages, capacity, and link quality;
- active cells use semantic or gradient color;
- inactive cells remain theme-derived;
- current partial cell may use opacity rather than misleading full activation.

Compact form: fewer cells with a minimum two-pixel gap.

### 7.3 Hex Segments

A technical honeycomb/avionics treatment.

- each horizontal hex is built from a center rectangle and two static triangles;
- segment count is capped at 10;
- suitable for battery, fuel, link, and model-themed dashboards;
- the current hex can receive a precise head highlight.

Compact form: six true hexes when the points remain crisp; otherwise an explicit six-block compact fallback. The renderer must not claim a one-object chamfer primitive the Lua binding does not expose.

### 7.4 Fine Ticks

A rail composed of many small lines.

- ideal for RSSI, RQly, control position, and fast-changing telemetry;
- 12–28 ticks depending on available length;
- major ticks can indicate thresholds;
- current position receives a brighter or taller tick.

Compact form: 8–12 ticks, no minor hierarchy.

### 7.5 Stepped Signal

Discrete bars with increasing height.

- familiar signal-strength reading;
- especially useful for link quality, RF power, and percentages;
- state colors can progress across steps;
- numeric value remains available when space allows.

Compact form: five steps.

### 7.6 Centered Dual Rail

Signed, zero-origin RC representation.

- fills left/right or down/up from numeric zero;
- suited to sticks, channels, trims, GVars, and signed outputs;
- zero notch is persistent;
- positive and negative sides can share a palette or use a custom duo.

This face is introduced after horizontal telemetry behavior and descending scales are fully validated.

---

## 8. Useful preset catalog

Presets are purposeful starting points, not decorative skins.

| Preset | Face | Palette | Geometry | Motion | Best use |
|---|---|---|---|---|---|
| Auto Source | source-semantic | Classic | responsive | Refined | opt-in automatic face choice from signal/battery/temperature/control semantics |
| Classic Rail | Continuous | Classic | medium, round | Refined | universal telemetry default |
| Theme Clean | Continuous | Theme Adaptive | slim, soft | Essential | strongly theme-integrated dashboards |
| Hex Telemetry | Hex | Classic | 8 cells, medium gap | Refined | battery, fuel, link |
| Status Blocks | Blocks | Classic | 10 cells, square | Essential | percentages and discrete capacity |
| Signal Ticks | Fine Ticks | Theme Adaptive | 20 ticks | Refined | RSSI, RQly, RF values |
| RC Center | Centered Dual Rail | Theme/custom duo | medium, zero origin | Refined | sticks, outputs, trims |
| Minimal Line | Continuous | Theme Adaptive | thin, no panel | Off/Essential | dense screens and top bar |
| Bold Data | Continuous | Classic | thick, value inside | Refined | large zones and primary flight values |

Preset behavior:

- Classic Rail remains the stored default; Auto Source is opt-in so an existing model never changes face because a source name was reclassified;
- Auto Source may use a stable sensor-semantic hint, but it never changes ranges, thresholds, alerts, or data transforms;
- selecting a preset does not overwrite unrelated stored fields;
- Auto overrides inherit from the preset;
- an explicit override wins;
- preset thumbnails are generated in light and dark themes for documentation;
- each preset has a compact variant;
- presets must pass the same performance and legibility gates as the default.

---

## 9. Configuration plan

### 9.1 Core principles

- Existing slots 1–24 remain byte-for-byte compatible.
- New settings are appended only.
- Labels remain short enough for the radio settings dialog.
- Visual options use Auto to inherit from the preset.
- Color fields are always stored, but are used only by modes that require them.
- Settings are grouped through ordering and clear Bar/Palette/Surface wording because dynamic hiding and section headers cannot be assumed.
- New labels remain unindented. The existing settings contract reserves two-space indentation for direct alert sub-options.
- The implementation stops at slot 44, reserving 45–50.

### 9.2 Phase-one personalization options

These establish the essential visual system.

| Slot | Key | User label | Type | Choices/default |
|---:|---|---|---|---|
| 25 | BarPreset | Bar preset | CHOICE | Auto, Classic, Theme, Hex, Blocks, Ticks, RC center, Minimal, Bold data; default 2 = Classic |
| 26 | BarFace | Bar face | CHOICE | Auto, Continuous, Blocks, Hex, Ticks, Steps, Dual rail; default 1 = Auto |
| 27 | BarDir | Bar direction | CHOICE | Auto, Horizontal, Vertical; default 1 = Auto |
| 28 | BarOrigin | Bar origin | CHOICE | Auto, Scale low, Zero; default 1 = Auto |
| 29 | BarSize | Bar thickness | CHOICE | Auto, Thin, Medium, Thick, Maximum; default 1 = Auto |
| 30 | BarEnds | Bar ends | CHOICE | Auto, Round, Square, Chamfer; default 1 = Auto |
| 31 | Segments | Bar segments | CHOICE | Auto, 6, 8, 10, 12, 16, 24; default 1 = Auto |
| 32 | SegGap | Segment gap | CHOICE | Auto, Tight, Normal, Wide; default 1 = Auto |
| 33 | Palette | Palette | CHOICE | Auto, Classic, Theme adaptive, Custom 3, Custom 2; default 1 = Auto |
| 34 | WarnClr | Warning colour | COLOR | #c86000 |
| 35 | CritClr | Critical colour | COLOR | #ff0000 |
| 36 | TrackClr | Track colour | COLOR | COLOR_THEME_SECONDARY1; used only by Custom colors |
| 37 | Surface | Surface | CHOICE | Auto, Transparent, Theme panel, Custom colors; default 1 = Auto |
| 38 | PanelClr | Panel colour | COLOR | COLOR_THEME_SECONDARY3; used only by Custom colors |
| 39 | Contrast | Contrast assist | CHOICE | Auto, Off, Strong; default 1 = Auto |

### 9.3 Advanced presentation options

These ship only after the core settings screen is tested on radio and Companion.

| Slot | Key | User label | Type | Choices/default |
|---:|---|---|---|---|
| 40 | Motion | Motion | CHOICE | Auto, Off, Essential, Refined, Expressive; default 1 = Auto |
| 41 | BarHead | Position head | CHOICE | Auto, None, Cap, Dot, Line, Needle; default 1 = Auto |
| 42 | ScaleMarks | Scale marks | CHOICE | Auto, Off, Thresholds, Ends, Full; default 1 = Auto |
| 43 | ValuePos | Value position | CHOICE | Auto, Above, Inside, End, Off; default 1 = Auto |
| 44 | LabelPos | Label position | CHOICE | Auto, Above, Below, Inside, Off; default 1 = Auto |

Slots 45–50 remain reserved. They are not consumed by speculative glow, shadow, radius, opacity, motion-speed duplication, or per-layer controls until real user testing proves the need.

The existing slot-16 Damping slider already controls the frame-rate-independent exponential smoothing used by both the needle and the current bar fill. Its user label should be safely renamed from “Needle damping” to “Gauge damping”; its key, position, type, default, and 0–9 range stay unchanged. Motion controls which transitions/effects exist. Gauge damping controls how quickly the value geometry follows its target.

### 9.4 2.11 behavior

Because 2.11 exposes only the first 10 widget options, none of the extended personalization fields are available:

- Classic Rail is automatic;
- direction and information density are responsive;
- normal color uses the calibrated classic green because the extended Normal colour field is unavailable;
- the full classic green/amber/red severity model remains;
- the bar remains polished, animated, and theme-integrated;
- no correctness or essential safety feature depends on extended options.

### 9.5 Interaction with the existing Style option

The existing slot-7 Style option remains the sole top-level renderer selector:

- Auto keeps the current compatibility rule: use Bar only when width/height is greater than 2.6; otherwise use the dial.
- Bar always enters the new bar system.
- Needle and Arc remain dial renderers and ignore bar-only appearance fields.
- Selecting a Bar preset does not secretly override Style.
- Bar options can be stored while a dial is active and take effect later if the user changes Style or moves the widget into an Auto-bar zone.

This protects the approved dial and prevents a newly appended setting from changing an existing model's renderer.

### 9.6 Option applicability

Because the firmware settings dialog cannot hide fields conditionally, documentation and resolver behavior must be explicit:

| Option | Applies to | When it is intentionally ignored |
|---|---|---|
| Bar face/direction/origin/thickness | every bar | all dial styles |
| Bar ends | Continuous and Blocks | Hex/Ticks/Steps use their own geometry; Dual Rail follows its face default |
| Bar segments | Blocks, Hex, Ticks, Steps, and portable Gradient slice density | Continuous solid; responsive/object caps can lower the requested count |
| Segment gap | Blocks, Hex, Ticks, Steps | Continuous solid/gradient stays gapless |
| Palette | every bar status layer | dial styles |
| Warning colour | Custom Three | Classic, Theme Adaptive, and Custom Two, whose warning midpoint is derived |
| Critical colour | Custom Three and the second Custom Two endpoint | Classic and Theme Adaptive |
| Existing Normal colour | Classic normal, Static, Custom Three, Custom Two endpoint | Theme Adaptive |
| Track/Panel colour | Surface = Custom colors | Auto, Transparent, Theme panel |
| Contrast assist | every bar | never; Off is an explicit behavior |
| Motion | every bar | Auto inherits preset |
| Position head | every face | None |
| Scale marks | shared overlay | Off |
| Value/Label position | shared information layout | individual items can still be responsively removed only when they do not fit |

An ignored option never changes telemetry truth and never causes a rebuild merely because its stored value changed while the active face cannot use it.

---

## 10. Responsive layout system

### 10.1 Geometry is based on the actual zone

The resolver uses:

- width and height;
- aspect ratio;
- LCD_SCALE;
- measured text size;
- selected face and direction;
- label/value placement;
- requested thickness and segment count;
- source range and zero position.

It must not special-case radio model names.

### 10.2 Responsive families

| Family | Typical use | Required behavior |
|---|---|---|
| Top-bar micro | one or merged top-bar slots | thin compact face, value-first, no clipping |
| Short strip | full/half width at quarter or sixth height | horizontal rail, side/inside value, reduced labels |
| Compact cell | half width at third/quarter height | simplified face, 6–12 segments |
| Standard landscape | full/half width at half height | complete horizontal instrument |
| Square | balanced width/height | horizontal default; vertical if selected |
| Tall/narrow | half width at full height | vertical Auto candidate |
| Large/full | 1 × 1 and app mode | full annotations, richer gradient/segment detail |

### 10.3 Information priority

When space becomes constrained, remove information in this order:

1. minor scale marks;
2. min/max text;
3. source label;
4. unit as a separate label;
5. decorative edge treatment.

Never remove:

- current value when it can fit legibly;
- current position representation;
- WARN/CRIT state text;
- unavailable/stale truth;
- critical threshold meaning.

### 10.4 Zone atlas

Create a generated zone atlas that records every unique rectangle produced by:

- all 16 standard layouts;
- app mode;
- top bar at one and multiple slot widths;
- 320, 480, and 800-pixel display scales;
- top bar on/off;
- trims, sliders, and flight mode combinations that alter the widget region.

The atlas becomes test data. A layout template is not considered supported until every unique resulting geometry belongs to a tested responsive family.

### 10.5 Existing breakpoints and migration

The current layout engine already defines:

- micro when min(width, height) is below 64 × LCD_SCALE;
- compact below 105 × LCD_SCALE;
- normal below 180 × LCD_SCALE;
- large at or above 180 × LCD_SCALE;
- horizontal orientation above a 1.4 aspect ratio;
- vertical orientation below 0.8;
- balanced between those values;
- Auto bar selection above a 2.6 aspect ratio.

The current visual catalog includes 60 × 60, 80 × 60, 100 × 100, 128 × 96, 160 × 160, 200 × 160, 200 × 200, 260 × 220, 300 × 150, 120 × 220, 100 × 260, and 480 × 272, plus bar-specific 300 × 44, 160 × 44, 300 × 60, and 300 × 70 scenes.

Migration rules:

- keep the four size-mode thresholds until the generated layout atlas proves a defect;
- keep the 2.6 Auto-style threshold to prevent existing models switching renderer;
- reuse micro/compact/normal/large as information-density inputs;
- use the 0.8 orientation threshold only after the widget is already in Bar style;
- add atlas-derived subprofiles for top-bar micro and short-strip layouts without changing dial classification.

---

## 11. Motion and feedback language

Motion exists to explain change.

### 11.1 Motion profiles

#### Off

- no pulse, color tween, activation cascade, or decorative animation;
- position geometry still follows the existing Gauge damping setting;
- users who want truly immediate position changes set Gauge damping to 0;
- warnings remain explicit through color, marker, and text.

#### Essential

- existing frame-rate-independent position damping;
- immediate semantic state transition;
- stale/no-data fade;
- existing 1 Hz critical pulse.

#### Refined — default

- critically damped fill/head motion with no overshoot;
- 150–220 ms state-color transition using a bounded, quantized transition palette;
- newly activated segment settles from a brief highlight;
- history marker moves precisely without bouncing;
- critical pulse remains calm and periodic.

#### Expressive

- refined behavior plus a short activation cascade or gradient sweep;
- never a permanent high-frequency shimmer;
- disabled when the widget is not visible;
- automatically reduced in micro zones or when frame budget is tight.

### 11.2 Motion safety

- State and alert logic use the raw value.
- Audible/haptic Alerts remain independent from the visual Motion option.
- Visual interpolation is capped so the displayed position cannot trail materially.
- Critical and unavailable states appear immediately.
- No animation moves scale endpoints or thresholds.
- No spring overshoot implies a value the sensor never reported.
- Motion is delta-time based and stable across refresh rates.
- Motion never creates a cache entry per frame; all transition colors and opacities are precomputed or quantized.

---

## 12. Technical architecture

### 12.1 Module responsibilities

| Area | Responsibility |
|---|---|
| main.lua | append-only option declarations and defaults |
| options.lua | generic typed parsing and compatibility defaults |
| app.lua | lifecycle, effective configuration, structural rebuild decision |
| presets.lua | existing sensor scale/threshold semantics; optional stable source-kind hints |
| bar_style.lua | visual preset/Auto resolution, bar palette, surface and compact-fallback decisions |
| theme.lua | theme tokens, RGB/luminance/contrast utilities, signature-keyed palette interpolation caches |
| geometry.lua | normalized values plus orientation-neutral bar-axis helpers |
| layout.lua | responsive family, regions, typography, direction, information density |
| renderer.lua | shared delta-write, state text/chip, value ink, anchoring, pulse, and flush helpers |
| bar.lua | bar orchestration, retained common layers, text/state/history updates, face dispatch |
| bar_faces.lua | build/update contracts for Continuous, Blocks, Hex, Ticks, Steps, Dual Rail |
| smoothing.lua | existing frame-rate-independent value-geometry damping |
| dev/scenes.lua | complete preset, palette, state, orientation, and zone-atlas scenes |

One consolidated bar_faces.lua is preferred initially so first use does not multiply script loads. It may be split only if profiling proves the shared load/memory tradeoff beneficial.

### 12.2 Face contract

Every face implements:

- supports(profile, config);
- estimateObjects(profile, config);
- build(widget, geometry, style);
- update(widget, objects, renderState);
- applyPalette(widget, objects, palette);
- setVisible(objects, visible).

Build runs only when the face or geometry signature changes. Refresh changes properties on retained references.

Binding rules inherited from the current renderer:

- scalar properties use renderer.setProp and one renderer.flush per frame;
- mutable line point buffers bypass setProp and use a persistent parameter wrapper with direct lvgl.set, because the property cache compares tables by identity;
- triangles receive exactly three point pairs and only properties supported by the simple-object binding;
- arc thickness/rounding and other build-time-only properties belong in the structural signature;
- no face may invent a property that tests/mock_env.lua rejects;
- labels are fixed boxes with LVGL alignment; live value measurement uses the non-memoizing path.

### 12.3 Shared render state

Faces receive one normalized structure containing:

- raw and smoothed normalized value;
- current semantic state;
- threshold positions;
- direction and origin;
- min/max history positions;
- availability/stale state;
- resolved semantic colors;
- resolved surface/ink colors;
- motion phase;
- information-density flags.

This prevents each face from reimplementing telemetry truth.

### 12.4 Object and instruction budgets

| Face | Target object range | Hard ceiling |
|---|---:|---:|
| Continuous solid | 12–18 | 24 |
| Continuous gradient | 20–38 | 38 |
| Blocks | 16–32 | 38 |
| Hex | 22–35 | 40 |
| Ticks | 18–34 | 40 |
| Steps | 12–24 | 32 |
| Dual rail | 16–28 | 36 |

Global gates:

- zero object creation/deletion during normal refresh;
- default preset below 1,200 Lua instructions per stable frame;
- every production face below 2,000 instructions on an ordinary value-changing refresh;
- warning/critical/muted transitions below 6,000 instructions;
- a structural bar configure/rebuild below 10,000 instructions;
- every callback remains below the firmware's hard 20,000-instruction limit;
- no cache growth under continuously changing values or colors;
- no face-owned table allocation in its ordinary update path; measure total allocation relative to the existing approximately 310 B/frame harness/runtime baseline;
- no face exceeds 40 visible objects without an explicit architecture review.

### 12.5 Exact module change map

| File | Existing strength | Planned work |
|---|---|---|
| main.lua | data-only boot path, version-gated option builder, shared app loader | rename only the Damping label; append slots 25–44; keep every existing key/type/position and avoid implementation imports |
| options.lua | generic typed parser already handles appended definitions | no production redesign expected; extend parser/default tests for the new choices and colors |
| app.lua | authoritative configure/apply/rebuild lifecycle | load bar_style and bar_faces once per path; resolve widget.barVisual and widget.barPalette during configure; keep at most one deferred reconfiguration per refresh |
| presets.lua | sensor scale and battery semantics | keep it a sensor-semantic module; optionally add stable semantic kind tags such as signal, battery, temperature, capacity, and control, never appearance bundles |
| bar_style.lua — new | not present | own appearance presets, Auto inheritance, palette resolution, surface/contrast decisions, compact fallbacks, and structural/non-structural signatures |
| theme.lua | color tokens, text metrics, RGB decoding, luminance, badge ink, calibrated gradient | add contrast-ratio/color-distance helpers; accept optional palette anchors; key ink/gradient caches by theme and palette signatures |
| geometry.lua | normalized range mapping and reusable point buffers | add orientation-neutral axis, span, segment-bound, and marker-point helpers; preserve descending-scale behavior |
| layout.lua | proven dial fitting and robust short-bar degradation ladder | split bar layout into shared information regions plus horizontal/vertical body geometry; resolve thickness, direction, face detail, head, marks, and compact state badge |
| renderer.lua | shared retained-property queue and semantic state helpers | preserve dial output; allow bar-specific palette resolution without copying stateText, updateChip, stateKey, anchorUnit, pulse, or flush |
| bar.lua | reliable horizontal two-rectangle renderer | become the bar orchestrator: common surface, labels, chip, history, threshold annotations, face dispatch, palette/motion application |
| bar_faces.lua — new | not present | build and update Continuous, Blocks, Hex, Ticks, Steps, and Dual Rail bodies through one retained interface |
| smoothing.lua | frame-rate-independent geometry damping already used by dial and bar | reuse unchanged where possible; Motion does not add a second speed control |
| tests and dev tools | strong mock, regression, SVG, gallery, collision, census, instruction, and allocation probes | add option tail, face cross-product, palette/theme switch, axis/origin, atlas, motion, object, instruction, and allocation coverage |

The existing presets.lua and the new bar_style.lua intentionally have different jobs:

- sensor preset: what the data means and which range/thresholds are sensible;
- appearance preset: how a bar should look when the user selects a visual starting point.

### 12.6 Effective visual configuration

app.configure resolves the stored options into one per-widget visual structure. Face code consumes only this structure and the normalized render state.

The resolved structure contains:

- preset key and source-semantic hint;
- face and compact face variant;
- horizontal/vertical direction;
- scale-low or numeric-zero origin;
- resolved physical thickness;
- round, square, or chamfer end treatment;
- effective segment count and gap;
- palette mode and palette signature;
- normal, warning, critical, track, panel, border, history, value, and label colors;
- surface and contrast-assistance strategy;
- motion profile;
- head type;
- scale-mark policy;
- value and label placement;
- flags explaining any responsive downgrade.

The last item is important for debugging. A requested 24-hex bar that becomes six chamfered cells in a top-bar zone is expected responsive behavior, not a silent rendering error. Tests and gallery captions should be able to report the effective result.

### 12.7 Orientation-neutral axis contract

All body faces use one axis descriptor:

- orientation;
- start coordinate;
- drawable length;
- cross-axis start and thickness;
- growth sign;
- normalized scale-low position;
- normalized zero position when zero lies inside the range;
- current raw and smoothed positions;
- warning/critical threshold positions;
- min/max/peak history positions.

Mapping rules:

- geometry.normalize remains the only value-to-0..1 mapping and continues to support Min greater than Max.
- Horizontal Scale low grows from left to right.
- Vertical Scale low grows from bottom to top by default.
- Explicit descending scales mirror through normalize; face code does not swap their authored endpoints.
- Zero origin uses geometry.normalize(0, min, max), not the geometric center.
- If zero lies outside the range, Auto falls back to Scale low; an explicit Zero request clamps the origin to the nearest scale end and exposes that downgrade to tests/gallery facts.
- Dual Rail measures positive and negative spans independently around the zero coordinate, so asymmetric ranges such as -30..100 remain truthful.
- Thresholds, history, head, segments, and scale labels all call the same axis mapping.

Auto direction:

- tall/narrow zones with width/height below 0.8 use vertical;
- balanced and landscape zones remain horizontal for compatibility;
- an explicit direction always wins if the selected responsive family can contain it.

### 12.8 Structural signature and update rules

Add to the structural signature when a change alters object count, object kind, or build-time-only LVGL properties:

- face and compact variant;
- direction and origin geometry;
- effective thickness and end shape;
- segment count and gap;
- surface object policy;
- head object type;
- scale/history text object presence;
- value/name placement;
- zone dimensions and relevant fonts;
- existing color mode when it changes reference-band object structure.

Keep out of the structural signature when existing objects can be updated:

- raw value and state;
- palette colors;
- theme-role RGB values;
- custom track/panel colors;
- opacity and contrast level when required objects are prebuilt;
- motion phase;
- history positions;
- label text;
- Damping value.

Palette or theme changes should recolor in place. Face, count, orientation, or build-time rounding changes rebuild once.

Theme-change handling requires a verified firmware behavior:

1. Test whether a live theme change invokes widget update.
2. If it does, resolve the new theme signature in app.update.
3. If it does not, poll a minimal theme signature no more than once per second while visible.
4. Recolor only when resolved PRIMARY1, PRIMARY2, SECONDARY roles, ACTIVE, or WARNING actually change.

### 12.9 Common bar paint order

Every face uses this z-order:

1. optional grounding panel;
2. casing/border;
3. neutral track or inactive segments;
4. permanent Rail/Sections reference colors;
5. active fill or active segments;
6. history ghost;
7. threshold and min/max marks;
8. exact position head;
9. value, unit, name, and scale text;
10. state badge edge, fill, and label.

This preserves two existing lessons:

- threshold references paint above active fill;
- opaque text/badges paint after moving geometry and safely occlude it.

### 12.10 Face build and update behavior

#### Continuous

Build:

- panel/casing/track;
- optional permanent semantic bands;
- solid active fill or 8–24 gapless gradient slices, capped by 38 minus the common-layer object estimate;
- one exact partial slice/fill cap;
- head and common overlays.

Update:

- solid mode changes one span;
- gradient mode changes only newly crossed slice visibility/opacity plus one partial slice;
- palette edits recolor the bounded slice array once;
- no slice is created as the value moves.

#### Blocks

Build:

- 6–24 inactive cell rectangles;
- active representation using recolor/opacity on the same retained cells where supported by the binding;
- common overlays and exact head.

Update:

- calculate active whole-cell count and partial fraction;
- touch only cells whose active state changed;
- use the head and digital value for exact position;
- never claim a fully active final cell for a small partial value.

#### Hex

Build:

- 6–10 cells;
- each true hex uses one rectangle plus two triangles;
- if triangle seams fail at the target scale, use the documented block compact fallback rather than an unsupported fake chamfer.

Update:

- recolor/opacity only cells crossing state;
- head supplies exact position;
- triangle point tables are static after build.

#### Fine Ticks

Build:

- 8–28 hline/vline or thin rectangle ticks;
- major tick identity at scale ends and thresholds;
- optional taller current-position tick.

Update:

- change active/inactive opacity for crossed ticks;
- move one retained current head;
- avoid dashed-line properties unless verified on the exact LVGL object type.

#### Steps

Build:

- 5–10 retained rectangles with increasing cross-axis size;
- baseline aligned for horizontal signal form or side aligned for vertical form.

Update:

- activate whole steps;
- use head/value for precision;
- retain warning/critical bands even when the source is currently normal in Rail/Sections modes.

#### Dual Rail

Build:

- two neutral spans around zero;
- two active fills or segment arrays;
- permanent zero notch;
- one signed position head.

Update:

- hide/collapse the inactive sign side without deleting it;
- grow only from numeric zero toward the normalized value;
- keep state thresholds based on the source's real high-is-good/low-is-good semantics rather than assuming distance from center is bad.

### 12.11 Face-independent Colour mode implementation

Every face element owns a normalized interval or center position. The color-distribution resolver supplies:

| Mode | Reference layer | Active layer |
|---|---|---|
| Static | theme-neutral track | existing Normal colour regardless of semantic state |
| Threshold | theme-neutral track plus explicit threshold marks | one resolved current-state color |
| Rail | permanent warning/critical zones at reduced opacity | one resolved current-state color in the foreground |
| Gradient | threshold-aligned spatial gradient across the scale | spatial color at each active slice/segment |
| Sections | complete normal/warning/critical reference bands | active elements retain their semantic band color |

Muted/unavailable behavior dims every colored reference and active layer together, preserving the existing contract that a NO LINK widget cannot leave a saturated red band as its brightest object.

### 12.12 History model for the new bar

Keep three concepts separate:

- **min marker:** exact recorded minimum;
- **max marker:** exact recorded maximum;
- **peak ghost:** the furthest value reached along the authored sweep direction, independent of the Min/max marks option.

The current bar uses the ghost plus one minimum marker to approximate two extremes. That happens to cover ascending scales but duplicates history.min on descending scales. Bar v2 builds both explicit markers when requested and keeps the ghost visually distinct through opacity, length, or shape.

All three:

- reuse persistent point/parameter tables;
- hide immediately when history resets;
- support horizontal and vertical axes;
- use transformed display units, never incompatible raw sibling units;
- remain independent from value damping.

### 12.13 Compact state policy

The existing full badge remains the preferred state treatment. When the zone cannot fit it:

- WARN becomes a compact W badge;
- CRIT becomes a compact C badge with the stronger critical edge;
- stale/disconnected/unavailable rely on muted geometry and a dash/short text only when it fits;
- color is never the sole warning/critical distinction;
- the full digital value remains higher priority than the source name.

The compact state vocabulary must be tested at one-slot top-bar width and at every LCD scale.

---

## 13. Ambitious phased roadmap

Each phase has subphases and an exit gate. Later visual richness does not bypass an earlier correctness gate.

### Phase 0 — Product and feasibility foundation

**Status: COMPLETE (2026-08-09).** The measured results, fixes, commands, and
deferred owners are recorded in [PHASE0_REPORT.md](PHASE0_REPORT.md); the
source-derived geometry is in [PHASE0_ZONE_ATLAS.md](PHASE0_ZONE_ATLAS.md).
The complete 79-scene visual and stress rerun is recorded in
[PHASE0_VALIDATION_REPORT.md](PHASE0_VALIDATION_REPORT.md).
Phase 0 changed no option slots and introduced no production face.

#### 0.1 Freeze the philosophy

- Commit Useful, Beautiful, Customizable as acceptance criteria.
- Record the preset-plus-override model.
- Record classic severity as the default.
- Record the separation of semantic colors and theme surfaces.

#### 0.2 Capture the baseline

- Preserve light/dark renders for all existing bar scenes.
- Record object counts and refresh instructions.
- Record the current option contract and frozen-slot fixtures.
- Add a reproducible descending-scale history failure.

#### 0.3 Build the zone atlas

- Enumerate all layout templates and resolved zone rectangles.
- Include top bar and decoration permutations.
- Cluster rectangles into responsive families.

#### 0.4 Prototype risky primitives

- benchmark gapless gradient slices at 12, 20, 24, and 32 objects;
- verify static triangle hexes at all LCD scales;
- test vertical text/value arrangements;
- test theme switching and wallpaper grounding;
- decide whether a native gradient binding deserves a separate proposal.

#### 0.5 Make the evidence trustworthy

- correct the mock's largest-font metrics against fonts.h;
- add a UTF-8 source-name regression before changing cleanName;
- remove stale “still broken” notes from dev/scenes.lua;
- update dev/sync-sd.ps1 for the new modules and delete stale .luac files before copying;
- document the frozen integer limitation of manual scale/threshold options.

**Exit gate:** every proposed face has a feasible retained-mode construction and an explicit object budget, and the font/gallery/deployment evidence is trustworthy.

**Gate result: PASS.** The current worst bar reserves 10 shared objects. The
measured totals are Continuous 14/24, spatial Gradient 34/38, Blocks 26/38,
Hex 40/40, Ticks 34/40, Steps 20/32, and Dual Rail 18/36. Twenty-four
gapless gradient slices are the portable cap; 32 slices were rejected at 42
total objects. Ten true three-object hexes pass at every LCD scale. The atlas
parses all 17 layout sources and classifies 6,570 exact rectangles across the
three display families and all meaningful decoration branches. The full test
and evidence record is linked above.

### Phase 1 — Personalization architecture

**Status: COMPLETE (2026-08-09).** Slots 25–39, immutable preset/override
resolution, all four palette modes, bounded theme-aware color caches, and the
retained face interface are implemented. The complete evidence and decisions
are recorded in [`PHASE1_REPORT.md`](PHASE1_REPORT.md). All 85 pre-existing
per-scene SVGs are byte-identical in both stock and dark themes; only the nine
new palette scenes were added. Future face/direction/geometry choices resolve
now and use an explicit Continuous fallback until their scheduled drawing
phases.

#### 1.1 Append the configuration schema

- add slots 25–39 behind the 2.12+ capacity guard;
- change the frozen-slot ratchet from “exactly 24” to “the first 24 exactly match,” then freeze the new 25–39 tail separately;
- keep every key at 10 characters or fewer and every translated label at 20 characters or fewer;
- preserve the existing 1-based CHOICE/zero-means-default parser contract;
- parse every Auto choice deterministically;
- keep slots 1–24 unchanged.

#### 1.2 Implement preset resolution

- add bar_style.lua and define appearance presets as data;
- keep presets.lua authoritative for sensor ranges; expose only stable sensor-semantic hints if Auto Source needs them;
- resolve user overrides without mutating stored options;
- add configuration-signature tests;
- document compact preset variants.

#### 1.3 Implement the palette engine

- add Classic, Theme Adaptive, Custom Three, and Custom Two;
- resolve active theme roles at runtime;
- cache palette interpolation;
- include palette anchors and resolved theme ink roles in every color-cache signature;
- add contrast and color-distance analysis;
- preserve exact user colors.

#### 1.4 Define the face interface

- separate shared telemetry state from face drawing;
- centralize thresholds, history, labels, badges, and stale state;
- add optional palette arguments to shared renderer helpers while pinning the dial's current path;
- prohibit per-face alert logic.

**Exit gate:** configuration, palette, and face contracts pass unit tests without changing the current default render.

### Phase 2 — Perfect the flagship default

#### 2.1 Correctness first

- build independent min and max bar markers and add a failing-first descending-scale test where ghost/min/max occupy the correct authored positions;
- verify low-is-good and high-is-good mapping;
- verify zero-crossing ranges;
- verify threshold ordering and out-of-range values.

#### 2.2 Continuous Precision Rail

- redesign casing, track, active fill, head, thresholds, and history;
- retain the existing five-rung short-bar degradation ladder and marker-overhang containment;
- add thickness and end-shape resolution;
- preserve a clear digital value hierarchy;
- ensure normal/warn/crit remain understandable without animation.

#### 2.3 Theme-integrated surfaces

- implement transparent, theme panel, and custom panel surfaces;
- implement Auto grounding for unknown backgrounds;
- verify stock light, dark, and high-contrast themes.

#### 2.4 Responsive default

- complete micro, short, compact, standard, tall, and large variants;
- ensure Auto direction does not surprise existing wide-zone users;
- validate all zone-atlas families.

**Exit gate:** Classic Rail is visibly at dial quality, works on 2.11, and passes every current regression test.

### Phase 3 — Color freedom

#### 3.1 Custom palettes

- wire normal, warning, critical, track, and panel color pickers;
- test purple/yellow, blue/orange, monochrome, pastel, and high-saturation palettes;
- verify exact persistence across radio and Companion.

#### 3.2 Theme Adaptive

- re-resolve on active theme changes;
- use active/warning candidates honestly;
- retain fixed critical fallback;
- invalidate badge-ink and gradient decisions when the theme signature changes;
- apply contrast assistance without recoloring.

#### 3.3 Continuous gradients

- build the gapless slice renderer;
- calibrate slice count per physical length;
- add luminance-aware interpolation;
- retain explicit thresholds and state labels.

#### 3.4 Contrast assistance

- add outline/head/panel strategies;
- define Auto decision tests;
- provide Strong mode;
- verify warnings with simulated color-vision deficiencies.

**Exit gate:** every palette mode is readable across theme/background fixtures, and custom colors remain user-authored.

### Phase 4 — Multiple visual faces and presets

#### 4.1 Blocks

- implement square and soft variants;
- implement partial-cell truth;
- validate 6–24 cells.

#### 4.2 Hex

- implement rectangle-plus-triangle cells;
- cap counts responsively;
- verify seams and chamfers at 320/480/800 scales.

#### 4.3 Fine Ticks

- implement major/minor tick hierarchy;
- align threshold ticks;
- verify fast-changing sources.

#### 4.4 Stepped Signal

- implement increasing-height steps;
- specialize source-aware defaults for RSSI/RQly-style values;
- retain numeric readability.

#### 4.5 Preset polish

- finish Classic, Theme, Hex, Blocks, Ticks, Minimal, and Bold Data presets;
- finish the opt-in Auto Source semantic mapping;
- generate documentation renders;
- run cross-preset consistency review;
- render every production face under all five existing Colour modes and reject visually collapsed modes.

**Exit gate:** each face adds a useful reading model, not merely a novelty shape, and remains under its object budget.

### Phase 5 — Orientation and RC-control depth

#### 5.1 Vertical bars

- implement bottom-to-top and top-to-bottom geometry;
- adapt labels and history;
- reuse the same axis mapping for thresholds, head, gradient slices, and markers;
- validate tall/narrow zones and manual direction override.

#### 5.2 Zero-origin behavior

- normalize negative and positive spans correctly;
- make the zero notch permanent;
- handle asymmetric ranges such as -30 to +100.

#### 5.3 Centered Dual Rail

- implement signed left/right and down/up fill;
- add RC Center preset;
- validate sticks, channels, trims, outputs, and GVars.

#### 5.4 Advanced presentation slots

- add slots 40–44 only after radio settings-screen usability review;
- rename the existing Damping label to Gauge damping without changing its wire contract;
- validate value/name placement with every orientation;
- retain six option slots for future work.

**Exit gate:** vertical and centered modes communicate real source semantics and never imply a false midpoint.

### Phase 6 — Motion and micro-interactions

#### 6.1 Motion profiles

- implement Off, Essential, Refined, and Expressive;
- reuse smoothing.lua and the existing Damping value for position movement;
- use raw state with visually smoothed position;
- pause optional motion when hidden.

#### 6.2 State transitions

- add bounded color transition;
- add segment activation settle;
- add stale/no-data fade;
- refine critical pulse.

#### 6.3 Performance tuning

- measure stable and changing frames for every face;
- reduce writes with set-if-changed;
- cap dynamic effects by responsive family;
- eliminate allocation growth.

**Exit gate:** Refined motion makes change easier to understand and every face remains below 10% of the instruction budget.

### Phase 7 — Complete validation

#### 7.1 Automated correctness

- extend unit tests for palette resolution, preset precedence, geometry, origins, descending ranges, gradients, and contrast decisions;
- freeze the original 24-slot prefix and the new tail through slot 44;
- add Colour mode × face tests for all 30 combinations;
- add theme-signature cache invalidation and dial-no-visual-diff tests;
- run lifecycle tests for create/update/resize/theme change/delete/recreate;
- test unavailable, stale, warning, critical, and recovery transitions.

#### 7.2 Visual regression

- render every preset in classic, theme-adaptive, and representative custom palettes;
- reuse dev/scenes.lua, svgkit.lua, gallery.lua, and collide.lua rather than creating a second preview system;
- render normal, warning, critical, stale, and unavailable states;
- render every responsive family in light and dark themes;
- compare object census and SVG structure.

#### 7.3 Hardware and Companion

- test 2.11 fallback;
- test 2.12+ options on radio and Companion;
- verify color persistence and labels;
- verify whether live theme changes invoke update; enable the bounded visible-time signature poll only if necessary;
- verify touch/non-touch settings screens;
- verify multiple Gauge Pro instances with different palettes.

#### 7.4 Flight-readability review

- confirm one-glance value/state recognition;
- confirm WARN/CRIT without color;
- confirm no motion distracts during active flight;
- confirm micro zones remain useful;
- confirm custom presets still look intentional.

**Exit gate:** no P0/P1 defect, no option migration regression, no clipping in the zone atlas, and no production face over budget.

### Phase 8 — Documentation and release

#### 8.1 User documentation

- explain preset plus override behavior;
- explain Classic, Theme Adaptive, Custom Three, and Custom Two;
- show how to create purple/yellow and other palettes;
- explain thickness, segment, face, direction, surface, and motion choices;
- document compact fallbacks.

#### 8.2 Visual gallery

- provide light and dark images for each preset;
- include small, wide, square, tall, and full-screen examples;
- include normal/warning/critical state comparisons;
- include three tasteful custom-theme examples.

#### 8.3 Migration and release notes

- state that slots 1–24 are unchanged;
- state that 2.11 receives the improved classic default;
- state that 2.12+ receives advanced personalization;
- describe performance limits and any face-specific compact behavior.

**Exit gate:** a new user can choose a preset in seconds, and a power user can understand every override without reading source code.

---

## 14. Validation matrix

At minimum, the scenario generator covers:

### State

- normal;
- exact warning threshold;
- warning;
- exact critical threshold;
- critical;
- recovering through hysteresis;
- unavailable;
- stale;
- no source.

### Scale

- high-is-good;
- low-is-good;
- descending manual scale;
- negative-to-positive;
- asymmetric zero range;
- clamped below/above endpoints;
- equal/invalid endpoint recovery.

### Appearance

- every face;
- every preset;
- thin, medium, thick, and maximum;
- round, square, and chamfer;
- 6, 8, 10, 12, 16, and 24 segments where supported;
- horizontal and vertical;
- scale-low and zero origin.

### Palette

- Classic Severity;
- Theme Adaptive;
- Custom Three purple/yellow/magenta;
- Custom Three blue/orange/red;
- Custom Two;
- low-contrast custom colors with Auto, Off, and Strong assistance;
- light, dark, and high-contrast themes;
- plain and image backgrounds.

### Zone

- every unique rectangle from the generated zone atlas;
- one-slot and merged top bar;
- 320, 480, and 800-pixel display families;
- label/unit extremes;
- long and negative numeric values.

---

## 15. Acceptance criteria

### Useful

- Value, state, position, and data availability are correct in every face.
- Descending and zero-origin scales map correctly.
- WARN and CRIT remain understandable without color.
- No animation delays safety state.
- Compact variants keep the most important information.

### Beautiful

- Classic Rail reaches the visual maturity of the dial.
- Every preset has intentional hierarchy and spacing.
- Gradients are visually continuous at normal viewing distance.
- Motion is smooth, short, and meaningful.
- No face uses clipping, accidental seams, weak contrast, or decorative clutter.

### Customizable

- Users can choose preset, face, direction, origin, thickness, ends, segment count/gap, palette, status colors, track, panel, contrast, motion, head, scale marks, and text positions.
- Classic, theme-adaptive, purple/yellow, and other custom palettes are first-class.
- Explicit overrides win over presets.
- Auto always produces a coherent result.
- 2.11 remains attractive without extended settings.

### Engineering

- Existing option slots remain compatible.
- All current tests continue to pass.
- New unit, lifecycle, visual, and zone-atlas tests pass.
- No normal refresh creates or deletes LVGL objects.
- Every production face remains below 2,000 instructions per frame and its object ceiling.
- Long-running variable-value tests show no cache or allocation growth.

---

## 16. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Many options overwhelm users | presets first, Auto overrides, ordered groups, concise labels, radio/Companion usability gate |
| Custom colors become unreadable | Auto/Strong structural contrast; never silently alter stored colors |
| Theme roles are mistaken for severity semantics | separate semantic and surface resolvers; fixed critical fallback |
| Gradient costs too many objects | responsive slice count, caching, hard ceiling, native-gradient R&D only if valuable |
| Hex faces explode object count | three-object construction capped at 10 segments; compact chamfer fallback |
| Animation hides truth | raw state drives alerts/badges; bounded, non-overshooting visual interpolation |
| Tiny zones lose face identity | explicit compact variant per face and documented fallback |
| New options break saved models | append-only slots, frozen-slot tests, 2.12+ guard |
| Settings screen becomes too long | ship slots 40–44 only after usability review; reserve 45–50 |
| Rich faces hurt multi-widget screens | per-face instruction/object gates plus four-instance stress scenes |
| Wallpaper defeats transparent contrast | Auto grounding panel or outline based on surface mode |

---

## 17. Definition of done

The bar improvement is complete when:

1. Classic Rail is the best default bar Gauge Pro has shipped.
2. It belongs visually inside light, dark, high-contrast, custom-color, and image-backed HTX themes.
3. A beginner can choose a good preset immediately.
4. A power user can build a thin purple/yellow tick rail, a thick classic gradient, a hex battery meter, or a centered RC bar without editing Lua.
5. Every supported zone produces an intentional composition.
6. Motion improves comprehension and never compromises telemetry truth.
7. The implementation remains compatible, retained-mode, bounded, and testable.
8. The bar feels as carefully designed as the dial while establishing its own flexible linear identity.

That is the standard: **Useful. Beautiful. Customizable.**
