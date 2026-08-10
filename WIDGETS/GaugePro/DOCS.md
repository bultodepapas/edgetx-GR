# Gauge Pro — User & Technical Reference

**Version:** 1.1 (branch `feat/gauge-v2`)
**Target:** EdgeTX 2.11+ color radios (LVGL); developed against EdgeTX 3.0
**Language:** Lua (LVGL rendering path, no legacy `lcd` renderer)
**License:** GPLv2

---

## 1. Overview

Gauge Pro is a responsive analog-digital telemetry instrument for EdgeTX
color-LCD radios. It renders a dial with a threshold rail, an active progress
arc, a tapered needle, adaptive ticks, semantic normal/warning/critical
colouring, peak-hold history and a value readout — or, where a dial cannot
work, the same instrument as a linear bar.

It is the only widget in the EdgeTX ecosystem that draws with the **LVGL
retained-object API** (`lvgl.arc`, `lvgl.triangle`, `lvgl.line`): every other
gauge, including the community `GaugeRotary` it succeeds and the built-in C++
`Gauge`, paints with the legacy `lcd` API. That is why it scales to any screen
size from one folder with no per-resolution assets.

The widget works with any numeric source — telemetry sensors, timers, sticks,
channels, gvars, TX battery. The folder in this repository is the SD-card
payload; there is no build step.

## 2. Requirements

- EdgeTX **2.11 or later** (the LVGL Lua API). On older firmware the widget
  still registers and draws a "needs EdgeTX 2.11+" message instead of
  disappearing from the model.
- A color-LCD radio or the Companion Simulator.
- No dependencies beyond the firmware's standard Lua API.

## 3. Installation

1. Copy the `GaugePro` folder to the SD card's `WIDGETS/` directory, so the
   radio sees `/WIDGETS/GaugePro/main.lua`.
2. In Companion: place the folder inside the SD-card content structure, or
   copy it onto a real SD card.
3. Power the radio (or restart the Simulator) so the widget list refreshes.
4. On a main screen: **long-press** an empty widget slot → **Widgets** → add a
   widget → pick **Gauge Pro** → configure it.

## 4. Usage

### 4.1 Options

Option availability depends on the firmware, because the number of option
slots does:

| Firmware | Slots | Source |
|---|---|---|
| 2.11.x (radio **and** Companion) | 10 | `widgets_container.h` `MAX_WIDGET_OPTIONS 10` |
| 2.12+ / 3.0 | 50 | `datastructs_screen.h`; dynamic allocation since commit `5c96b1e15` |

The widget declares its **core ten** on every firmware, in fixed positions,
and appends the rest only when the firmware can store them. Options are never
inserted or reordered: widget option data is positional and typed, and a model
that travels between versions or through an older Companion must not have its
settings shifted.

**Core ten (all firmware):**

| Option | Type | Default | Meaning |
|---|---|---|---|
| **Source** | Source | *auto* | Telemetry sensor, timer, or local source. Defaults to the first available of RSSI, RQly, RxBt, Cels, TxBt (resolved by the firmware). |
| **Scale low** | Integer | 0 | The low end of the dial. Not a threshold — see **Warn level** below. |
| **Scale high** | Integer | 100 | The high end of the dial. |
| **Warn level** | Integer | 55 | Where the gauge turns amber. |
| **Critical level** | Integer | 35 | Where it turns red and starts pulsing. |
| **High = good** | Bool | On | Direction: higher is better (Off inverts the bands). |
| **Style** | Choice | Auto | Auto / Needle / Arc / Bar (see 4.4). |
| **Colour mode** | Choice | Rail | Static / Threshold / Rail / Gradient / Sections (see 4.5). |
| **Decimals** | Choice | Auto | Auto follows the sensor precision, or 0 / 1 / 2. |
| **Min/max marks** | Choice | Markers | The **recorded** peaks, marked on the scale: Off / Markers / Markers + text. Nothing to do with **Scale low/high**. |

**Appended on 2.12+:**

| Option | Type | Default | Meaning |
|---|---|---|---|
| **Normal colour** | Color | `#209058` | Native colour picker; overrides the normal-state colour (default green, the "all clear" colour — 4.3 explains why it is a fixed colour and not a theme role). Lets four gauges on one screen be colour-coded. A custom accent is used as given: the contrast guarantee in 4.3 covers the default, not your choice. |
| **Name override** | String | "" | Custom label ("PACK", "MOTOR"); empty uses the sensor name. |
| **Unit override** | String | "" | Custom unit; empty uses the sensor unit. |
| **Scale ends** | Choice | Auto | Where **Scale low/high** (and the two levels) come from: Auto takes a known-sensor preset, Manual always uses your values. |
| **Dial sweep** | Choice | 270° | 270° / 180° / 360°. |
| **Needle damping** | Slider | 4 | 0 = raw, 9 = heavy (see 6.6). |
| **Cell reading** | Choice | Lowest | How a `CELLS` table is reduced: Lowest / Total / Average. |
| **Volts as %** | Choice | Off | Off / Li-Po / Li-Ion — show state of charge instead of volts (see 4.8). |
| **Alerts** | Choice | Off | Off / Critical / Warning + critical (see 4.9). |
| **Alert switch** | Switch | none | Alerts only fire while this switch is on (e.g. armed). |
| **Startup delay (s)** | Integer | 4 | No alerts until the model has settled. The unit is in the label because a Lua widget cannot give a NumberEdit a suffix. |
| **Vibrate** | Bool | Off | Haptic pulse on critical. |
| **Reset min/max** | Switch | none | Clears the tracked history in flight. |
| **Info badges** | Bool | On | Hides the *informational* pills (`NO LINK`, `STALE`, `NO DATA`, `NO SOURCE`). **WARN and CRIT always show**, whatever this is set to — they are a safety signal, and colour alone does not reach every pilot (4.3). The row is reserved either way, so turning it off does not buy the value more space. |
| **Bar preset** | Choice | Classic | Auto Source / Classic / Theme / Hex / Blocks / Ticks / RC Center / Minimal / Bold Data. A coherent starting point; explicit overrides below win. |
| **Bar face** | Choice | Auto | Continuous / Blocks / Hex / Ticks / Steps / Dual Rail. Phase 1 freezes and resolves the contract; non-Continuous drawing lands in Phase 4 and currently uses an explicit Continuous fallback. |
| **Bar direction** | Choice | Auto | Horizontal / Vertical. Auto resolves tall zones vertically; vertical drawing lands in Phase 5. |
| **Bar origin** | Choice | Auto | Scale low / Zero. Zero-origin drawing lands in Phase 5. |
| **Bar thickness** | Choice | Auto | Thin / Medium / Thick / Maximum; inherits from the preset and is live on the Continuous Precision Rail. Large zones scale the physical rail up while short zones remain inside the proven degradation slot. |
| **Bar ends** | Choice | Auto | Round / Square / Chamfer; inherits from the preset. Chamfer uses real retained triangle tips, not a rounded approximation. |
| **Bar segments** | Choice | Auto | 6 / 8 / 10 / 12 / 16 / 24. Responsive and object ceilings may lower it; Hex is already capped at 10 by its 40-object budget. |
| **Segment gap** | Choice | Auto | Tight / Normal / Wide. Used by segmented faces. |
| **Palette** | Choice | Auto | Classic / Theme adaptive / Custom 3 / Custom 2. This is live on the current Continuous bar. |
| **Warning colour** | Color | `#c86000` | Exact Custom Three warning anchor. |
| **Critical colour** | Color | `#ff0000` | Exact Custom Three critical anchor and Custom Two endpoint. |
| **Track colour** | Color | theme `SECONDARY1` | Used when Surface = Custom colors; updates retained objects without rebuilding. |
| **Surface** | Choice | Auto | Transparent / Theme panel / Custom colors. Panels ground the complete instrument behind rail and text; micro zones downgrade to transparent. |
| **Panel colour** | Color | theme `SECONDARY3` | Exact custom panel color. Gauge Pro preserves it and chooses the better existing theme ink on top instead of recoloring it. |
| **Contrast assist** | Choice | Auto | Off / Strong. Auto measures contrast, ordinary color distance and simulated color-vision separation, then strengthens casing/head structure only when needed. Strong keeps the strongest local ground and marks. Neither mode replaces authored colors. |

Phase 1 froze slots 25–39 before every face was drawn. Phases 2–3 now ship the
Continuous Precision Rail, thickness/end geometry, panel surfaces, complete
bar history, live HTX theme re-resolution, structural contrast assistance and
the retained spatial Gradient. Future face, orientation and origin choices still resolve
deterministically, participate in signatures, report responsive downgrades and
fall back to Continuous until their scheduled phases; no resolver mutates the
stored option table.

Notes:

- Option **names** (the keys stored in the model) are ≤ 10 characters without
  spaces, a firmware convention. The friendly labels above are what the radio
  shows, and come from the `translate` callback.
- **Labels are display only.** The wire contract is (position, key, type), so
  a label can be reworded at any time without touching a saved model — which
  is why several were reworded in Tanda 8 to say what they actually do.
- They are also **budgeted**: the settings dialog is a two-column grid inside
  a dialog 80 % of the screen wide, so a label gets about 20 characters, and
  the firmware's label wraps rather than clipping. A pinned test enforces the
  budget, rejects duplicates, and allows the two-space indent only on the
  alert sub-options — indentation is the only grouping the firmware offers, so
  it has to mean exactly one thing.
- The two levels are clamped into [Scale low, Scale high].
- If Scale low > Scale high the scale is **mirrored**, not swapped: a
  descending scale works (0 at the right).

### 4.2 Scale: presets vs your values

With **Scale = Auto** (or on 2.11, where the option does not exist and the
range values are still at their defaults) a known-sensor profile supplies the
range:

| Sensor name(s) | Unit | Min | Max | Warn | Crit | Direction |
|---|---|---|---|---|---|---|
| RSSI, RSSI1–3 | dB | 0 | 100 | 55 | 35 | high-good |
| 1RSS, 2RSS, TRSS | dBm | −120 | 0 | −80 | −95 | high-good |
| RQly, TQly, VFR | % | 0 | 100 | 55 | 35 | high-good |
| SNR | dB | −20 | 20 | 2 | −5 | high-good |
| RxBt, Vbat, VFAS, Batt | V | 0 | 8.4 * | 3.7 | 3.5 | high-good |
| TxBat, tx-voltage | V | 6 | 8.4 | 6.8 | 6.4 | high-good |
| Cell, Cels | V | 3.0 | 4.2 | 3.7 | 3.5 | high-good |
| Tmp, T1/T2, TFET, TBEC | °C/°F | 0 | 120 | 70 | 90 | low-good |
| RPM, Hspd | rpm | 0 | 20000 | 16000 | 18000 | low-good |
| Curr | A | 0 | 100 | 70 | 85 | low-good |
| Capa | mAh | 0 | 5000 | 3500 | 4500 | low-good |
| Fuel, Bat% | % | 0 | 100 | 30 | 15 | high-good |
| Thr | % | 0 | 100 | 80 | 95 | low-good |
| Alt, GAlt | m | 0 | 400 | 300 | 380 | low-good |
| GSpd, ASpd | km/h | 0 | 150 | 120 | 140 | low-good |
| Dist | km | 0 | 1000 | 700 | 900 | low-good |
| Sats | — | 0 | 24 | 8 | 5 | high-good |
| Vibr | % | 0 | 100 | 40 | 60 | low-good |

\* Voltage sources marked as battery presets are **rescaled to the detected
pack** on the first reading: a 4S pack turns 0–8.4 V into 12.0–16.8 V (see
4.8). Matching is by normalized sensor name first, then by unit.

With **Scale = Manual** your four range values are always used.

### 4.3 States and colours

The widget separates two channels on purpose, and the split explains every
colour decision below:

| channel | what it is | coloured by |
|---|---|---|
| **status** | the arc, the rail / section bands, the threshold marks, the badge | the state colour |
| **data** | the value, unit, source name, min/max | the **theme's own text role** |

This is how instruments have always worked — an airspeed indicator has green,
amber and red arcs *on the dial face* and plain white numerals. Colour on the
scale is a signal you read at a glance; colour on the number only makes the
number harder to read. Before this split the state colour drove both, which is
how a role meant for a button background ended up as the primary readout's ink.

A value maps onto three bands (normal / warning / critical, ordered by the
direction option):

- **NORMAL** — a fixed green `#209058`, or your Accent option.
- **WARN** — a fixed amber `#c86000`, badge text "WARN".
- **CRIT** — a fixed red `#ff0000`, badge text "CRIT", and the value arc
  **pulses** at ~1 Hz so the state survives greyscale and colour blindness.
  Critical is also the one state that tints the value text.
- **No data** — everything dims to `COLOR_THEME_DISABLED`; the badge reads
  `NO LINK`, `STALE`, `NO DATA` or `NO SOURCE` (see 4.10), and the last known
  value stays on screen, dimmed.

**Why fixed colours and not theme roles.** EdgeTX's role vocabulary is a *UI*
vocabulary — `PRIMARY*` is text, `SECONDARY*` is chrome, `ACTIVE` is the
background of a checked control, `WARNING` is warning label text. It has no
notion of instrument state, so there is no "all clear" role to use, and the two
that look closest are traps: `COLOR_THEME_ACTIVE` is yellow on the stock theme
and scores **1.13 : 1** against the stock screen background — the normal state
used to be invisible on a stock radio — and `COLOR_THEME_WARNING` is *red*
there, 53 perceptual units from critical's red, so warning and critical were
the same colour to the eye.

A fixed colour has no theme author looking after it, so each of the three is
chosen to clear the 3 : 1 non-text contrast floor against **both** a light and
a dark background. That pins relative luminance into a window only 0.058 wide,
inside which 3.35 : 1 is the best any colour can achieve on both at once. All
three land within 0.05 of that optimum, at equal luminance, differing in hue
alone:

| state | colour | vs stock light | vs a dark theme |
|---|---|---|---|
| normal | `#209058` | 3.35 : 1 | 3.35 : 1 |
| warning | `#c86000` | 3.34 : 1 | 3.35 : 1 |
| critical | `#ff0000` | 3.39 : 1 | 3.30 : 1 |

**The badge is filled, not outlined.** The state colour is the pill's ground,
and the label takes whichever of the theme's two text roles contrasts with it
(read at runtime through `lcd.getColor`). That makes the badge *self-grounding*
— its contrast is between the fill and its own label, both of which the widget
controls — so it reads on a light theme, a dark theme, and a theme that ships a
`background.png` photograph alike, at 5.2–6.4 : 1. The previous outlined pill
put CRIT on a `SECONDARY2` fill at 2.91 : 1, below the floor, inside a pill
whose own fill measured 1.19 : 1 against the screen.

**Equal luminance means hue is the only separator**, and that is a deliberate
trade: it stops any one state shouting louder than another by accident, but it
means the non-colour channels are not decoration. A simulated deuteranope sees
this widget's warning and critical **25.6** perceptual units apart — inside the
~60 confusion threshold. What separates them for those users is the badge
*text* and the critical pulse, which is why **Info badges = Off can no longer
hide a WARN or CRIT badge** (4.1).

The **needle never changes colour**: it stays a fixed, theme-neutral tone
(`COLOR_THEME_PRIMARY1`) regardless of state or colour mode, so it stays
legible pointing across a green, amber or red band alike — only the arc,
badge and (where applicable) rail bands carry the state colour.

It also **never changes length**. Where the state chip lies on the needle's
path, the needle passes *behind* it: the chip is opaque and is created after
the needle, so LVGL — which paints children in creation order — occludes the
blade without anything having to be measured. This is the same creation-order
contract the value and name labels use to paint over the arcs. Earlier
versions shortened the blade instead, which left it at 13 % of its length at
mid-scale and made it visibly grow and shrink as it swept.

State changes are **hysteretic**: a worse state is adopted immediately, a
better one only once the value has cleared the threshold by 2 % of the range.
A value resting on a threshold therefore cannot flicker — and cannot
machine-gun the alerts.

The bar adds an independent **Palette** axis without recoloring the approved
dial. Classic keeps the measured green/amber/red defaults above. Theme
Adaptive uses the active HTX `ACTIVE` and `WARNING` roles plus a fixed critical
fallback. Custom Three uses the existing Normal colour plus exact warning and
critical pickers. Custom Two keeps the exact normal/critical endpoints and
derives a gamma-aware midpoint. Theme ink, track and surface roles remain
separate from severity, so custom status colors still belong to the active
HTX theme. If colors are close, the analyzer requests redundant structure; it
never silently substitutes a user's color.

### 4.4 Styles

- **Auto** — dial with a needle; no needle in micro zones; automatically a
  **bar** when the zone is more than 2.6× wider than tall.
- **Needle** — always draw the needle.
- **Arc** — never draw the needle; the progress arc alone shows the value.
- **Bar** — linear instrument: rounded track, threshold marks, fill, peak
  ghost, independent min/max marks, exact position head, value + unit, name
  and state. Thin/medium/thick/maximum and round/square/chamfer are real
  geometry choices.

### 4.5 Colour modes

The mode chooses how the **status** channel is coloured. It never changes the
data text, which always takes the theme's ink role (4.3) — critical excepted.

- **Static** — the arc keeps the accent colour whatever the value (the needle
  excepted - 4.3). The badge still follows the real state.
- **Threshold** — the arc takes the state colour.
- **Rail** *(default)* — as Threshold, plus a thin outer rail that permanently
  marks the warning and critical zones. The value arc keeps the foreground;
  the scale stays readable.
- **Gradient** — the arc interpolates critical → warning → normal across the
  **thresholds** (red at critical, green once inside the normal band). It ramps
  between the same three fixed colours as every other mode and holds the whole
  ramp at constant luminance, so every step clears 3 : 1 on both reference
  backgrounds (worst case 3.02 : 1). Hue varies; brightness does not. On the
  Continuous bar this is a spatial scale of 8–24 retained, gapless slices,
  calibrated by physical length and remaining 38-object budget. Classic uses
  the calibrated ramp; theme/custom ramps preserve exact anchors and use
  gamma-aware intermediate colors. The current partial slice and head remain
  exact, and threshold marks remain explicit above the gradient.
- **Sections** — the dial track is drawn as three arcs; the bar keeps all three
  bands permanently visible in a dedicated lower reference channel.

In every mode, when the data stops being live all the coloured elements — arc,
rail bands, section bands and the bar's threshold marks — drop to the same
muted opacity together, so a gauge announcing `NO LINK` never keeps a fully
saturated red reference band as the brightest thing on it.

In every mode the needle itself stays the fixed neutral tone described in 4.3.

### 4.6 Responsive layouts

Zone classification (thresholds scale with `lvgl.LCD_SCALE`, so "micro" is the
same physical size on every radio):

| Mode | min(w, h) | Behaviour |
|---|---|---|
| micro | < 64 px | Dial + value only. |
| compact | < 105 px | Adds the unit and state badge. |
| normal | < 180 px | Adds the source name. |
| large | ≥ 180 px | Adds scale end labels, minor ticks, optional min/max text. |

**Micro zones are an ambient display, not a diagnostic one.** There is no room
for a badge in a 60×60 dial, so state there is carried by the arc's colour and
— at critical — by its pulse, with no text channel at all. Warning and critical
are therefore distinguishable at that size only by hue and by the pulse, which
is a real limitation for a colour-blind pilot (4.3). Pick a micro zone for "is
it roughly where I expect", and give any reading you would act on at least a
compact zone.

Orientation: **horizontal** (w/h > 1.4) puts the dial left and the text right;
**vertical** (w/h < 0.8) puts the dial on top; **balanced** centres the dial
with the value inside it. Beyond w/h > 2.6 the bar style takes over.

Two rules keep the composition from drifting apart in the extremes:

- In a **vertical** zone the dial and its text are centred **as one group**,
  not pinned to the top. A tall, narrow zone caps the dial at the zone's
  width, so it cannot grow to fill the height; without this, 100×260 left
  70 px of air above the value and 72 px below — 55 % of the zone.
- The **source name** appears in a vertical zone whenever the text column has
  room for it, even when `mode` says otherwise. `mode` is classified on
  `min(w, h)`, so a 100×260 widget is judged by its narrow axis and came out
  *compact*, dropping its label on 260 px of height. Only the name is
  decided this way; everything else still follows `mode`.

Text rows below the value share whatever slack the zone has, rather than
sitting at a fixed 2 px apart with the remainder left unused at the bottom.
Inside the ring the min/max row is the exception — it stays tight under the
value, because the clear chord narrows with every pixel of descent and
"breathing room" there is bought with width the text needs.

**Containment guarantee.** Nothing the widget paints leaves its zone, at any
size and any `LCD_SCALE`. This is not only cosmetic: tick marks and history
marks are LVGL *lines*, and the binding reads their coordinates with
`luaL_checkunsigned` (`lua_lvgl_widget.cpp`), so a single negative coordinate
raises on the radio and the widget disables itself for the session. Below the
size where the ring's outer furniture fits, the layout gives up the furniture
rather than the widget — the ticks first, then the ring shrinks onto whatever
clearance is left; likewise the bar slides up rather than hang past the bottom
edge, and the state pill and unit label are clamped to the zone. The
guarantee is enforced by `R-1`/`R-4` in `tests/smoke_test.lua`, which sweep
the zone space rather than a list of named sizes.

The *designed* range is still 60×60 and up (the shot catalogue's floor);
smaller zones stay legal and inert rather than fatal.

### 4.7 History

For telemetry sensors the minimum and maximum come from the radio's own
`<sensor>-` and `<sensor>+` sources — the same values the rest of the UI
shows, and the ones cleared by the standard *Reset telemetry* function. For
sources without those siblings (sticks, channels, gvars) the widget tracks
them itself. Either way the history drives:

- two marker lines on the dial (hidden until data exists),
- a **peak-hold ghost** arc segment — deliberately INDEPENDENT of the
  Min/max option (Tanda 6 F-8): always created, visibility driven by the
  history data alone, so the dial and the bar share one ghost semantic,
- an optional `min … max` text row in large zones,
- and is cleared by a source change, a range change or the Reset switch.

### 4.8 Batteries

- **Cell reading** decides how a `CELLS` table is reduced. Default **Lowest**:
  the cell that sags first is the one that matters. Total gives pack voltage,
  Average the mean.
- **Pack detection**: for a voltage source with a battery preset the cell
  count is derived from the first reading (`floor(V / 4.35) + 1`) and latched
  — a pack sags under load, so re-deriving it later would step the scale down
  mid-flight. The scale is rebuilt once, to `cells × [3.0 … 4.2] V`.
- **Volts as %** turns the reading into state of charge on a 0–100 %
  scale using a Li-Po or Li-Ion discharge curve, with warning at 30 % and
  critical at 15 %. Voltage alone is a poor charge indicator; the curve makes
  the dial mean something.

### 4.9 Alerts

Alerts fire on a **transition** into a state, never continuously, and only
when: the startup delay has elapsed, the optional alert switch is on, and the
data is live. A held state re-alerts at most every 5 s. Critical plays a
two-tone alert and (optionally) a haptic pulse; warning plays a single tone.

### 4.10 No-data behaviour

| Availability | Meaning | Chip | Value display |
|---|---|---|---|
| `unset` | no source configured | NO SOURCE | `-` |
| `invalid` | source id does not resolve | NO DATA | last known, else `-` |
| `valid` | fresh, current data | — | live value |
| `stale` | sensor reported but is no longer current | STALE | last known |
| `disconnected` | telemetry link down (`getRSSI() == 0`) | NO LINK | last known |
| `unavailable` | no value at all (link alive) | NO DATA | last known |

A **non-finite** reading — `NaN`, `+inf`, `-inf` — is treated as
`unavailable`: an instrument must not pretend to know. That is a containment
rule as much as an honesty one. The three are contagious:
`geometry.normalize` maps `NaN` to `NaN` (neither comparison in `clamp()` is
true of it), `smoothing.step` turns `±inf` into `NaN` on its *second* frame
(`inf - inf`), and the `NaN` then reaches `lvgl.set` as an arc `endAngle`,
where `luaL_checkinteger` raises and the widget disables itself. `format.lua`
already refused to *print* a `NaN`; `telemetry.refresh` now applies the same
refusal to the geometry, at the one gate every reading passes through.

The last known value is cleared when the source or the ranges change, so a new
source never shows old data. After reconnection the needle snaps to the
current value instead of sweeping up from zero.

## 5. Technical reference

### 5.1 Architecture

| File | Responsibility |
|---|---|
| `main.lua` | **Boot-weight only**: option declarations, version gate, `lvgl` guard, and a `loadScript` of `app.lua` on first use. Every widget's `main.lua` is executed at radio startup, used or not (see 6.1). |
| `app.lua` | Lifecycle: create / update / refresh, config → ranges → layout, rebuild decisions. |
| `options.lua` | The option wire format: capacity and typed parsing. Pure Lua. |
| `theme.lua` | Design tokens, text metrics, RGB/luminance/contrast analysis, bounded palette and badge-ink caches. |
| `geometry.lua` | Clamp/normalize, value→angle, circle points, line/tick/triangle builders, bar fill. Pure Lua. |
| `ranges.lua` | Band ordering, state detection, hysteresis. Pure Lua. |
| `presets.lua` | Known-sensor profiles, cell detection, discharge curves. Pure Lua. |
| `format.lua` | Value/timer formatting and the widest-sample measurement. Pure Lua. |
| `smoothing.lua` | Frame-rate independent needle damping. |
| `telemetry.lua` | Source metadata cache, value reading, cell aggregation, availability model, history. |
| `layout.lua` | Mode/orientation/style classification, dial and bar geometry, typography, regions. |
| `renderer.lua` | Retained LVGL dial tree; per-frame property-only updates. |
| `bar_style.lua` | Appearance presets, Auto inheritance, runtime palettes, compact variants and signatures. |
| `bar_faces.lua` | Retained face interface, normalized render state, the Continuous Precision Rail, object ceilings and future-face fallback. |
| `bar.lua` | Linear orchestrator: shared thresholds/history/labels/badges plus face dispatch. |
| `alerts.lua` | Transition alerts with startup delay, switch gate and rate limiting. |
| `dev/preview.lua` | Renders the real object tree to SVG for off-radio design review. |
| `dev/collage.lua` | The official option sheet committed under `docs/` (7.1). |
| `dev/api_spike.lua` | LVGL API feasibility widget for Companion/hardware. |
| `dev/RESEARCH.md` | Research notes behind the design decisions. |
| `tests/` | Headless suites (see 7). |

### 5.2 The option contract

This is the part that most Lua widgets get wrong, so it is spelled out:

- The firmware delivers options to Lua as **numbers**, never strings, except
  `String`/`File` options (`lua_widget.cpp` `updateWithoutRefresh`:
  `String/File → lua_pushstring`, `Integer/Switch → lua_pushinteger` signed,
  everything else → `lua_pushinteger` unsigned). Comparing a `CHOICE` option
  against its label string can never match.
- `CHOICE` values are stored **1-based**: the settings dialog reads
  `getUnsignedValue(i) - 1` and writes `newValue + 1`
  (`widget_settings.cpp`). Declared defaults are 1-based too; a stored `0`
  means "never edited" and falls back to the declared default.
- Option slots are **positional and typed**; `setDefault()` resets a slot only
  when the stored type differs. Options may only ever be appended.
- Capacity is version dependent (see 4.1). Extra declarations are silently
  truncated (`lua_widget_factory.cpp`).

### 5.3 Lifecycle

Registration is `{ name, options, translate, create, update, refresh,
useLvgl = true }`. `destroy` is **not** a widget callback — the firmware never
calls it (`widgets.cpp` reads exactly those keys).

- **`create(zone, options, path)`** — loads `app.lua`, which loads the twelve
  modules and builds the state tables.
- **`update(widget, options)`** — on every option or size change: parse
  options into a typed config, resolve the source, apply the scale (preset or
  manual), resolve precision and the displayed unit/name, build the bands and
  the layout, and rebuild the LVGL tree **only when the structural signature
  changed** (style, mode, orientation, visibility flags, colour mode, sweep,
  value font, radius, zone size, unit text).
- **`refresh(widget, event, touch)`** — per frame: check the reset switch,
  read telemetry, run alerts, then write only the properties that changed.
- **`background()` is intentionally absent.** The firmware only calls it while
  the widget is **off-screen**, so history and data maintenance live in
  `refresh()`.

### 5.4 Rendering model

`build()` creates every object once; `update()` mutates only properties that
actually changed, guarded by a per-object cache, and writes through a single
reused table so `refresh()` allocates nothing.

Dial object tree (worst audited case at 200×200 — needle, Sections, scale
labels, markers+text, chip shown): **33 visible objects**; the tests assert
≤ 40. The solid bar is **16 visible / 19 retained objects** in its normal
default scene and **20** for Sections + markers + critical badge. The spatial
Gradient is capped from the actual layout anatomy: both the canonical 300×70
scene and the 480×120 panel/chamfer/markers stress scene are exactly **38
retained objects**, never 40 hidden behind a smaller visible census.
The counts are reproducible: `lua5.3 dev/census.lua ./`.

| Object | Kind | Count | Created when |
|---|---|---|---|
| Track | arc | 1 | always (behind everything) |
| Section bands | arc | 3 | Colours = Sections — ADDED to the track, not replacing it |
| Peak-hold ghost | arc | 1 | always (hidden until history exists; NOT gated on the Min/max option — Tanda 6 F-8) |
| Value arc | arc | 1 | always |
| Pivot hub | circle | 1 | needle shown |
| Value / unit / name | label | 3 | by mode |
| State word | label | 1 | chip shown |
| Min/max text | label | 2 | large + "Markers + text" |
| Scale ends | label | 2 | large, sweep < 360 |
| Needle (body, mid, tip) | line | 3 | needle shown — the P2-1 taper, no triangles, no counterweight |
| Major ticks | line | 3 / 5 / 7 | micro / compact+normal / large |
| Minor ticks | line | 6 | large mode |
| Min/max markers | line | 2 | markers on |
| State badge + edge | rectangle | 2 | badge shown |

Per-frame writes: arc `endAngle`, needle `pts` (only when the angle
changed), `color`/`opacity` on a state change, label `text` when the string
changed, and show/hide on data loss.

### 5.5 Dial geometry

- LVGL angles: **0° = 3 o'clock, increasing clockwise** (screen y grows down).
- Sweeps: 270° from 135°, 180° from 180°, 360° from 270°. A full ring clamps
  its end angle to `start + 359` so it can never close onto its own start
  (which would render nothing).
- Value → angle: `start + clamp((v − min) / (max − min), 0, 1) × sweep`,
  rounded to the nearest degree.
- The **radius is derived last**: ring thickness, rail, gap and tick length
  are computed from the zone, then the radius is whatever remains inside the
  dial box. Deriving the radius from the box first pushes ticks outside the
  zone (a real bug caught by the layout tests).
- Lines and triangles take `{x, y}` point pairs — the exact format the binding
  reads; named `{x = …}` points fail on the radio. A triangle must have
  exactly three points.
- All physical sizes pass through `theme.px()` (`lvgl.LCD_SCALE` = 0.8 / 1.0 /
  1.375 for 320 / 480 / 800 px wide screens).

### 5.6 Typography

Fonts are `LcdFlags` with the font index in bits 8–11 — the convention the
firmware itself uses. Text is **never positioned by measuring it at runtime**:
every label gets a region (`x`, `y`, `w`) plus an alignment, and LVGL centres
or right-aligns inside it (`lvgl.label` supports `align`). Consequences:

- the value cannot shift its neighbours as digits change,
- the unit sits at a fixed offset on the value baseline,
- `refresh()` makes no `lcd.sizeText` calls at all.

The value font is auto-fit: the largest font whose **height and width** fit
the value region, measured once per layout against the widest string the
configured scale can produce (e.g. `100.0`), so the digits never move.

### 5.7 Telemetry engine

**Source resolution** (cached, runs only when the source id changes):

- `getFieldInfo(id)` → name (cleaned of leading invalid bytes), unit,
  telemetry flag. `unit` is present **only** for telemetry sources, which is
  what distinguishes them from sticks, timers and gvars.
- Timers are detected by **source id**, from `getSourceIndex("timer1")` — not
  by name. `T1`/`T2`/`T3` are common temperature sensor labels, and reading a
  temperature as `hh:mm:ss` was a real defect in 1.0.
- Sensor precision is looked up once through `model.getSensor(i)` over
  `MAX_SENSORS` entries (40/60/99 by target — scanning a fixed 32 misses
  sensors on large radios).
- Sibling `<name>-` / `<name>+` sources are resolved for history.

**Per frame:**

- `getSourceValue(id)` returns **three** values: `value, current, fresh`.
  Telemetry values arrive already scaled by the sensor precision.
- Tables (`CELLS`) are reduced by the Cell reading mode; non-numeric tables
  (GPS, date/time) report no data.
- `current == false` on a telemetry source ⇒ `stale`; a nil value ⇒
  `disconnected` when `getRSSI() == 0`, else `unavailable`.

### 5.8 Performance discipline

- Per-callback budget: the firmware sets a count hook every 200 VM
  instructions and errors past 100 hooks — **20,000 instructions per
  callback** (`widgets.cpp` `luaHook`, `lua_widget_factory.cpp`).
- `refresh()` creates no objects, allocates no tables, makes no text
  measurements, and skips `lvgl.set` when the cached value is unchanged.
- `update()` rebuilds only when the structural signature changes.
- Text metrics and font heights are memoized for the life of the widget.

### 5.9 Binding compatibility notes

Verified against `radio/src/lua` in this fork:

- `lvgl.arc` accepts absolute `startAngle`/`endAngle` plus `bgStartAngle`/
  `bgEndAngle`, `color`/`bgColor`, `opacity`/`bgOpacity`, `radius`,
  `thickness`, `rounded`, `filled`. **`thickness` and `rounded` are
  build-time only** (no setter), so options that change them force a rebuild.
- `lvgl.triangle` accepts **only `pts`** plus the base object properties — no
  `filled`, `thickness` or `rounded`; it always fills.
- `dashGap`/`dashWidth` exist on `hline`/`vline` (`LvglWidgetLineBase`) but
  **not** on the free-angle `lvgl.line`.
- `lvgl.circle` does not accept `bgColor`/`bgOpacity`; `filled = 1` fills with
  `color`.
- `lvgl.label` accepts `text`, `color`, `font`, `align`, `x`, `y`, `w`, `h`.
- Object properties may also be **functions** (`pts`, colour, `text`), which
  the firmware re-evaluates EVERY frame through `callRefs` — unconditionally,
  in every `foreground()`. This widget deliberately does not use them (Tanda 6
  §C.6): a guarded explicit `lvgl.set` costs nothing when the value is static
  (the per-object cache drops the write), while a callback form would run a
  Lua call per property per frame against the 20 000-instruction budget for a
  widget whose values are mostly static between frames. Do not "modernise"
  the needle or the labels into the callback form.
- **String methods are unavailable** (no string metatable in the firmware
  build); always `string.lower(s)`, never `s:lower()`.
- `getTime()` returns **10 ms ticks**; all time maths converts explicitly.
- Documented arc angles are 0–360; this fork also normalises 405 → 45, but the
  widget clamps its own angles rather than relying on that.

## 6. Notes on decisions

### 6.1 Boot weight

Every `main.lua` under `/WIDGETS/` is executed at radio startup for every
model, whether the widget is placed or not. `main.lua` therefore contains
option data and a guard, and nothing else; the twelve modules load on first
use, inside `create()`. The option-array builder and label translator live
INLINE in `main.lua` for the same reason (one file read per widget at boot);
options.lua's copies were deleted in Tanda 6 (F-14/6.1) after verifying both
byte-identical — one builder remains, so they cannot drift.

### 6.2 Why a rail instead of coloured sections

Recolouring the whole track (Sections) destroys the figure/ground
relationship — the value arc stops being distinguishable from the scale. A
thin outer rail marks the bands permanently while the thick inner arc keeps
the foreground. Sections remains available.

### 6.3 Why a tapered needle

A one-pixel line reads as a construction guide. Both the widget this one
succeeds (`GaugeRotary`, `lcd.drawFilledTriangle`) and the ecosystem
benchmark (`yaapu`, a three-line triangle) draw a tapered needle.

The taper is three LINE segments, not triangles: on the radio
`LvglWidgetTriangle::refresh` frees its canvas and rebuilds it on every
angle change (~46 rebuilds in 20 frames under damping, AUDIT P2-1), while
`LvglWidgetLine::refresh` only rewrites the points. The three segments
(body → mid → tip, `rounded = 1`) restore the taper with zero churn, over a
solid hub circle (review P-A).

### 6.4 Why no bitmap dial face

`yaapu` and FlightDash render a pre-drawn dial-face PNG. That buys crisp
ticks, and costs a per-resolution asset set, theme adaptation and the ability
to recolour for warn/crit. Vectors plus `LCD_SCALE` are the point of this
widget.

### 6.5 Why alerts have a startup delay

A model powering up reports nonsense for a second or two. Without a delay,
every power-on is a critical alarm — the lesson from `ePowerbar`.

### 6.6 Damping

`factor = 1 − exp(−dt / tau)` with `tau = damping × 40 ms`, `dt` clamped to
1–1000 ms and measured in **milliseconds** (`getTime() × 10`). The digital
value updates instantly; only the needle glides. Damping 0 disables the
filter — right for RSSI, wrong for a noisy current sensor.

## 7. Testing

Headless suites run with stock Lua 5.3 (the version EdgeTX embeds):

```sh
lua5.3 tests/run_tests.lua  <widget-dir>/   # pure modules        (60 tests)
lua5.3 tests/smoke_test.lua <widget-dir>/   # full lifecycle     (168 tests)
lua5.3 dev/collide.lua      <widget-dir>/   # geometric collision audit
lua5.3 dev/collage.lua      <widget-dir>/ docs/   # the official option sheet
lua5.3 dev/preview.lua      <widget-dir>/   # writes dev/preview.html
```

The mock environment enforces the firmware's real behaviour: per-object
property allow-lists (including the triangle and dash-parameter restrictions
in 5.9), `{x, y}` point arrays, the missing string metatable, 10 ms
`getTime()` ticks, the three-value `getSourceValue`, and — most importantly —
the **integer option wire format** with 1-based choices. Test input is written
in readable form (`Style = "Needle"`) and converted to the wire format by
`mock.makeOptions`, so the tests stay legible without lying about the
contract.

Coverage includes: the two frozen option contracts (slots 1–24 and 25–39),
name lengths, 1-based
defaults, the 2.11 ten-slot build and the 2.12 full build), all colour modes
and styles reaching the objects, preset/override precedence, all four bar
palettes, exact custom anchors, bounded color caches, face contracts and
ceilings, live theme polling/cache invalidation, spatial gradient continuity,
partial-span truth, contrast Off/Auto/Strong and simulated protanopia,
deuteranopia and tritanopia, all six bar families, thickness/end/surface variants, exact
head/history positions, cell aggregation modes, pack detection,
battery percent, timer vs temperature disambiguation, every availability
state, needle hide/snap on reconnect, hysteresis on a noisy ramp, alerts and
their startup delay, the reset switch, the 17-layout firmware atlas plus the
golden zone matrix (every object inside the zone, object count ≤ 40), and a 200-frame
flight that must produce zero object churn.

`dev/preview.lua` renders the actual object tree — same coordinates, angles,
fonts and theme roles — as SVG. The production gallery covers stock, dark and
high-contrast fixtures. It is the
fastest way to review a visual change, and it is how the layout, chip sizing
and gradient mapping in this version were checked.

### 7.1 The visual contract sheet

`dev/gallery.lua` composes **every** scene in the catalogue into one
self-contained SVG plus a machine-readable manifest. It is pure Lua — no
browser, no Python, no image library — so it runs anywhere the test suites do.

```
lua5.3 dev/gallery.lua .                       # stock + dark sheets, manifest
lua5.3 dev/gallery.lua . --theme highcontrast  # maximum-separation fixture
lua5.3 dev/gallery.lua . --only bateria        # one section
lua5.3 dev/gallery.lua . --tag pre-tanda6      # keep a named snapshot
lua5.3 dev/gallery.lua . --baseline dev/shots/gallery/manifest-pre-tanda6.lua
lua5.3 dev/gallery.lua . --list                # the catalogue, no rendering
lua5.3 dev/gallery.lua . --png                 # also rasterise, if a
                                               # rasteriser is installed
```

| File | Role |
|---|---|
| `dev/svgkit.lua` | The LVGL → SVG emitter and the theme palettes. One emitter, shared. |
| `dev/scenes.lua` | The scene catalogue and the fact extractor. One list, shared. |
| `dev/gallery.lua` | Composition, manifest, coverage report, baseline diff. |
| `dev/shots.lua` | The same scenes as individual SVGs, for close-up review. |
| `dev/collage.lua` | The **official** sheet in `docs/` — the one the README embeds. |

`dev/collage.lua` is the only one of these whose output is **committed**
(`docs/gauge-pro-options.png`, its dark and high-contrast twins, plus all three
SVGs). It is
deliberately a different sheet from the gallery rather than a flag on it: the
gallery is a working instrument — object censuses, overflow boxes, warning
dots, a coverage audit, written in the owner's language — and exists to fail a
review. The collage is a picture for users: English, no diagnostics, nothing on
it that only means something to someone who has read the audit. Same catalogue,
same emitter, so the two can never disagree about what the widget draws.

**A tool must let the widget see the theme it is rendering.** Since
`theme.labelOn` reads the theme's text roles through `lcd.getColor` to choose
the badge's ink, every one of these calls
`mock.setThemeColors(svgkit.themeColors(name))` **before building** a scene.
Skipping it renders a decision the radio would not have made — measured on the
amber badge: white at 3.94 : 1, where a dark-theme radio picks black at
5.32 : 1.

Three things make it a verification tool rather than a picture:

- **The manifest** records what a picture cannot show — layout mode and
  orientation, availability, semantic colour key, resolved scale and
  thresholds, the object census — for every scene, deterministically ordered
  so two runs diff cleanly. `--baseline` reports exactly which field of which
  scene moved, which is how a refactor proves it changed nothing it did not
  intend to.
- **The coverage panel** cross-checks the catalogue against `main.lua`'s
  option declarations and names any option no scene ever varies. Options that
  cannot appear in a still frame (alerts, haptics, the reset switch) are
  listed as `n/a` with the reason, so the gap list stays honest. Append option
  25 without a scene for it and the sheet says so.
- **Three visual fixtures**: stock light, representative dark and explicit
  high contrast, because theme roles, fixed safety colours and authored custom
  colours must coexist on every supported ground. The light pass is the only
  check that the fixed needle colour
  (`COLOR_THEME_PRIMARY1`) still contrasts against every band when the theme
  inverts the ramp.

Render problems are not silently smoothed over: a label that does not fit its
box is drawn wrapped **and** outlined in red, the scene gets a red badge, and
the message is printed. `--strict` turns any such warning into a non-zero exit
for CI.

Output lands in `dev/shots/gallery/` (git-ignored — it is a build artefact).
A filtered run (`--only`) writes to its own `-only-<filter>` file names, so a
partial render can never overwrite the full sheet or, worse, the manifest a
baseline comparison depends on.

### 7.2 Extending the sheet

**Add a scene** — one table appended to the right section's `cases` list in
`dev/scenes.lua`. The full field reference (required vs optional, what `post`
receives, how `opts` values are written) is the block comment at the top of
that file; it is kept next to the code it describes rather than here, so it
cannot drift. The short version:

```lua
{ name = "ba-pct-low", title = "Li-Po % / Lowest", zone = { 200, 160 },
  source = "Cels", opts = { Battery = "Li-Po", Cells = "Lowest" },
  value = { 3.85, 3.84, 3.86, 3.85 }, note = "deberia ser ~55 %" },
```

Options are written in **readable** form — `CHOICE` by its label, `BOOL` as
`true`/`false` — and `mock.makeOptions()` converts them to the integer wire
format the firmware actually delivers. Nothing else has to change: both tools
pick the scene up, and `--list` will show it.

**Add a source** — an entry in `scenes.SOURCES` carrying `id`, the
`TelemetryUnit` enum as `unit`, `prec`, the optional `minId`/`maxId` history
siblings and the 0-based `sensor` index. Omit `unit` for a non-telemetry
source (stick, timer): `telemetry.lua` keys `isTelemetry` off its presence.

**Add an option** — after appending it to `main.lua`'s `DEFS`, give it a scene.
If you do not, the coverage panel lists it as `SIN COBERTURA` and the run says
so on stdout. If the option genuinely cannot show up in a still frame, add it
to `scenes.NON_VISUAL` with the reason instead; it then reports as `n/a`
rather than as a gap. That choice is deliberately explicit — an option should
never fall out of coverage by silence.

**Regression workflow.** Snapshot before a change, compare after:

```sh
lua5.3 dev/gallery.lua . --tag before
# ... make the change ...
lua5.3 dev/gallery.lua . --baseline dev/shots/gallery/manifest-before.lua
```

The diff names the exact field of the exact scene that moved, so a refactor
has to account for everything it changed and nothing else.

**Harness traps**, all of them real and all documented in `dev/scenes.lua`:
`tests/mock_env.lua` removes the string metatable on purpose (EdgeTX builds
without `LUA_ENABLE_STRLIB_MT`), so `("%d"):format(n)` raises in dev tooling
exactly as it would on the radio — use `string.format`. And the mock is global
state: a scene's objects must be captured before the next `build()` resets
them.

## 8. Distribution

- The widget ships from this repository; the folder is the SD-card payload.
- To list it in the official EdgeTX gallery, open an "Add a Lua App or Widget
  to the Gallery" issue at https://github.com/EdgeTX/lua-scripts with a
  description and screenshots.
- A patch to `EdgeTX/edgetx-sdcard` (`dev/WIDGETS/GaugePro/`) is the ecosystem
  path for firmware-adjacent Lua widgets.

## 9. Known limitations and roadmap

- Presets adjust the scale internally; the settings dialog still shows the
  values you typed (a Lua widget cannot write back to persistent option
  storage). Scale = Manual makes the relationship explicit.
- Pack cell-count detection assumes the first reading is a reasonably charged
  pack, and latches. Powering the radio on mid-flight can mis-detect.
- Unit text covers the common `TelemetryUnit` values; unknown units show none
  (the Unit override option covers the rest).
- Alert sounds are tones, not spoken values; `/SOUNDS` playback is a
  candidate for a later version.
- Not yet implemented: the fullscreen detail view (stat row, history
  sparkline, reset button), optional label shadows (a second offset label, as
  the official Value widget does), and a background fill colour.
- On 2.11 the widget is limited to its core ten options; the rest require
  2.12+ on both the radio **and** Companion.

## 10. License

GPLv2 — see the header of each file.
