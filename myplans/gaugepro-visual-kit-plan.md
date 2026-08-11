# Gauge Dial Pro + Gauge Bar Pro Visual Validation Kit — Plan

> **Split ejecutado:** el catálogo legado sigue siendo la fuente auditada de escenas, pero el
> adaptador lo divide en contratos `GaugeDialPro`/`DialPro` y `GaugeBarPro`/`BarPro`, genera YAML
> por familia e instala el `GaugeCore` compartido. Consulte
> [`../WIDGETS/GaugePro/DOCUMENTATION.md`](../WIDGETS/GaugePro/DOCUMENTATION.md).

**Document version:** 0.2
**Status:** Split adapter implemented and verified against real `simu.exe`: 206/206 Track 1 captures and 8/8 Track 2 layouts completed; 16 telemetry-injection cases remain explicitly skipped.
**Depends on:** `myplans/widget-visual-emulator-plan.md` ("Widget Studio") §9a — its Phase 1 engine-hooks spike **already passed** on 2026-08-10. This plan does not repeat that work; it consumes it.
**Date:** August 10, 2026

---

## 0. Scope statement (read this first)

The request is for a **reproducible, real-firmware, pixel-truth visual catalog of Gauge Dial Pro and Gauge Bar Pro**: every relevant family option, every layout, every telemetry state, every theme, captured as committed PNGs with generated documentation, runnable as one script.

This is deliberately **narrower** than the full "Widget Studio" platform described in `widget-visual-emulator-plan.md` (contract-driven multi-widget genericity, `studio.yml` schema, hot reload, browser workspace, golden-diff CI gate). That plan is real and its Phase 1 spike is the foundation this one stands on, but building its full generic driver (Phases 2–6) is a separate, larger undertaking with its own gates. Building it is **not required** to deliver what was asked here.

So: **reuse the engine hooks Phase 1 already proved** (native `simu` + `WIDGET_STUDIO` + `--pipe` steering + deterministic capture — all already merged, see §9a of that plan), and build a **small, Gauge-Pro-specific driver** on top of them. If a future session wants the generic platform, this plan's driver is a worked example of exactly the kind of client it would serve — but it does not block on it, and does not try to be it.

### 0.1 Implemented split delta

- `defs.json` schema 2 contains both real frontend contracts: DialPro 24 and BarPro 42 options.
- The legacy scene source is adapted into 56 DialPro and 150 BarPro runnable cases; `Style` is
  consumed by the adapter and never reaches generated YAML.
- Model zones carry an explicit family and serialize `widgetName: DialPro` or `BarPro`.
- The disposable SD tree installs `GaugeCore` plus both Pro frontends and removes stale legacy
  frontend/bytecode only inside that generated tree.
- Run-log schema 2 rejects rows left by monolithic runs.
- Verified on real `simu.exe`: 206/206 Track 1 cases and 8/8 Track 2 layouts captured, zero runtime
  errors. Sixteen source-injection cases remain explicitly skipped.

---

## 1. Research — original monolithic baseline

The table below records the pre-split baseline used to author the scene catalog. The implemented
driver now reads `GaugeDialPro/main.lua` and `GaugeBarPro/main.lua`; current runtime modules are
listed in `WIDGETS/GaugePro/DOCUMENTATION.md`.

### 1.1 Historical legacy option contract (`GaugePro/main.lua`, 44 entries)

Options are **positional and typed**; the wire format and 1-based CHOICE convention are documented in `options.lua`'s header and verified against `radio/src/gui/lua_widget_factory.cpp` / `widget_settings.cpp` in an earlier session. Full table, in declaration order (this **is** the option matrix for §5):

| # | Key | Type | Default | Choices / range |
|---|---|---|---|---|
| 0 | Source | SOURCE | `RSSI`/`RQly`/`RxBt`/`Cels`/`TxBt` (first available) | any source |
| 1 | Min | VALUE | 0 | −10000..10000 |
| 2 | Max | VALUE | 100 | −10000..10000 |
| 3 | Warn | VALUE | 55 | −10000..10000 |
| 4 | Crit | VALUE | 35 | −10000..10000 |
| 5 | HighGood | BOOL | 1 | — |
| 6 | Style | CHOICE | Auto | Auto / Needle / Arc / Bar |
| 7 | ColorMode | CHOICE | Rail (3) | Static / Threshold / Rail / Gradient / Sections |
| 8 | Precision | CHOICE | 0 (Auto) | Auto / 0 / 1 / 2 |
| 9 | ShowMinMax | CHOICE | Markers (2) | Off / Markers / Markers + text |
| 10 | Accent | COLOR | `#209058` | any |
| 11 | Label | STRING | "" | override name |
| 12 | Suffix | STRING | "" | override unit |
| 13 | Scale | CHOICE | Auto | Auto / Manual |
| 14 | Sweep | CHOICE | 270° | 270° / 180° / 360° |
| 15 | Damping | SLIDER | 4 | 0..9 |
| 16 | Cells | CHOICE | Lowest | Lowest / Total / Average |
| 17 | Battery | CHOICE | Off | Off / Li-Po / Li-Ion |
| 18 | Alerts | CHOICE | Off | Off / Critical / Warning + critical |
| 19 | AlertSw | SWITCH | 0 | any switch |
| 20 | Delay | VALUE | 4 | 0..30 (s) |
| 21 | Vibrate | BOOL | 0 | — |
| 22 | ResetSw | SWITCH | 0 | any switch |
| 23 | ShowChip | BOOL | 1 | — |
| 24 | BarPreset | CHOICE | Classic | Auto / Classic / Theme / Hex / Blocks / Ticks / RC center / Minimal / Bold data |
| 25 | BarFace | CHOICE | Auto | Auto / Continuous / Blocks / Hex / Ticks / Steps / Dual rail |
| 26 | BarDir | CHOICE | Auto | Auto / Horizontal / Vertical |
| 27 | BarOrigin | CHOICE | Auto | Auto / Scale low / Zero |
| 28 | BarSize | CHOICE | Auto | Auto / Thin / Medium / Thick / Maximum |
| 29 | BarEnds | CHOICE | Auto | Auto / Round / Square / Chamfer |
| 30 | Segments | CHOICE | Auto | Auto / 6 / 8 / 10 / 12 / 16 / 24 |
| 31 | SegGap | CHOICE | Auto | Auto / Tight / Normal / Wide |
| 32 | Palette | CHOICE | Auto | Auto / Classic / Theme adaptive / Custom 3 / Custom 2 |
| 33 | WarnClr | COLOR | `#c86000` | any |
| 34 | CritClr | COLOR | `#ff0000` | any |
| 35 | TrackClr | COLOR | `COLOR_THEME_SECONDARY1` | any |
| 36 | Surface | CHOICE | Auto | Auto / Transparent / Theme panel / Custom colors |
| 37 | PanelClr | COLOR | `COLOR_THEME_SECONDARY3` | any |
| 38 | Contrast | CHOICE | Auto | Auto / Off / Strong |
| 39 | Motion | CHOICE | Auto | Auto / Off / Essential / Refined / Expressive |
| 40 | BarHead | CHOICE | Auto | Auto / None / Cap / Dot / Line / Needle |
| 41 | ScaleMarks | CHOICE | Auto | Auto / Off / Thresholds / Ends / Full |
| 42 | ValuePos | CHOICE | Auto | Auto / Above / Inside / End / Off |
| 43 | LabelPos | CHOICE | Auto | Auto / Above / Below / Inside / Off |

These 44 slots describe GaugePro legacy only. The current visual-kit contracts are 24 DialPro
slots and 42 BarPro slots, both extracted mechanically from their real frontends.

**Non-visual options** (cannot be shown in a still frame — verbatim from `dev/scenes.lua:99-106`, already an audited exclusion list, reused rather than re-litigated):

| Option | Reason |
|---|---|
| Alerts | sound/haptic, paints nothing |
| AlertSw | alert gate switch, not a visual state |
| Delay | alert startup delay, not visual |
| Vibrate | haptic |
| ResetSw | an action, not a state |
| Motion | a temporal profile — needs a sequence, not a frame (§6 handles this separately) |

### 1.2 The 0-default trap (`options.lua:60-111`) — binding constraint on the generator

`M.parse()` only falls back to the declared default for **CHOICE** (`choiceOf`: any raw value `<1` → default) and **BOOL** (`boolOf`: `nil` → default, but a literal `0` is a valid, meaningful `false`). **VALUE, SLIDER, SWITCH, COLOR, and SOURCE never do this** — `numberOf(raw, default)` returns `tonumber(raw) or default`, and a stored `0` is a valid number, so it is returned as-is, not replaced. This was independently confirmed empirically in the Widget Studio Phase 1 spike (`widget-visual-emulator-plan.md` §9a, last paragraph): a hand-authored zone with unset `Min`/`Max` read back as literal `0`, not Gauge Pro's compiled defaults of 0/100.

**Implemented consequence:** the model-YAML generator writes an explicit value for every option
in the selected family contract—24 for DialPro or 42 for BarPro—and rejects unknown or
cross-family overrides. It never relies on omission-equals-default.

### 1.3 Colour contract (`theme.lua`, cross-checked against memory `gaugepro-colour-contract`)

Two channels, never mixed:

- **Status** (arc, rail/section bands, threshold marks, badge) — three **fixed** `lcd.RGB` literals, chosen to clear WCAG 3:1 against both the stock light background (`#e4eef2`) and a dark theme (`#303030`) simultaneously: normal `#209058`, warning `#c86000`, critical `#ff0000`. This is a hard, already-solved constraint (arithmetic maximum is 3.35:1 on both at once) — **any custom test theme must not fight it**: a test theme's own background must not itself sit inside a narrow band that defeats this, and in general the test theme should be built to *showcase* the contrast, not stress-test it (that stress test already exists and is out of scope here).
- **Data** (value, unit, name, min/max) — theme **roles**: `COLOR_THEME_PRIMARY1`/`PRIMARY2`, `SECONDARY1`, `DISABLED`. These *do* track whatever theme is active, which is exactly the property §3 exploits.

### 1.4 Existing scenario catalog (`dev/scenes.lua`) — the coverage source of truth

`dev/scenes.lua` is a mature, audited, ~150-case catalog already used by the pure-Lua SVG mock loop (`dev/shots.lua`, `dev/gallery.lua`), organized into 13 sections:

| Key | Title | Cases (approx.) | What it proves |
|---|---|---|---|
| `estado` | Estado y disponibilidad | 7 | normal/warn/crit/stale/no-link/no-data/no-source |
| `color` | Modos de color | 10 | all 5 `ColorMode`s × normal/critical |
| `escala` | Escalas y umbrales | 9 | non-0..100 ranges, descending scale, out-of-range, warn==crit |
| `dial` | Opciones del dial | 11 | Sweep, DialStyle, ShowChip, ShowMinMax |
| `aguja` | Aguja y amortiguación | 5 | needle positions, Damping 0 vs 9 |
| `texto` | Valor, unidad y nombre | 7 | Precision, Label/Suffix override, timer source |
| `bateria` | Batería y celdas | 7 | Cells aggregation, Battery %, CELLS table |
| `acento` | Color de acento | 3 | Accent override |
| `paleta` | Personalización de paleta | 15 | Palette, custom colors, monochrome + Contrast assist |
| `barra` | Estilo barra | 29 | BarSize/BarEnds/Surface/ColorMode/BarPreset, zero-crossing |
| `caras4` | Caras segmentadas | 33 | BarFace × ColorMode matrix + density/gap edge cases |
| `ejes5` | Ejes, cero y presentación | ~55 | vertical bars, numeric-zero origin, Dual rail, BarHead/ScaleMarks/ValuePos/LabelPos, Auto-source |
| `zonas` | Matriz de zonas | 12 | the same config at every real EdgeTX widget-cell size |

This catalog already achieves near-total coverage of every visual option (its own `gallery.lua` cross-checks the case list against `main.lua`'s `DEFS` and reports uncovered options, so drift is already caught). **This plan reuses this catalog as its primary content source** rather than re-authoring ~150 cases by hand (see §4).

### 1.5 Zone geometry (`dev/zone_atlas.lua`) — the layout source of truth

Already parses the real firmware layout maps (`radio/src/gui/colorlcd/layouts/*.cpp`) and the real `ViewMainDecoration::getWidgetsZone()` formula, and computes exact `(x,y,w,h)` rectangles per layout per resolution (320×240 / 480×272 / 800×480), deduplicated. This tool is the existing, audited source of truth for "what size can a Gauge Pro zone actually be" — reused directly rather than re-deriving zone sizes.

---

## 2. Research — widget layout system

`radio/src/gui/colorlcd/layouts/*.cpp` registers 16 standard screen layouts plus one app-mode layout via `BaseLayoutFactory<Layout>`, each with a real YAML `LayoutId` string (this is what a model file's `screenData[].LayoutId` must contain — confirmed against `radio/src/storage/yaml/yaml_datastructs_tx16smk3.cpp` in the prior Widget Studio session):

| YAML `LayoutId` | Display name | Zones | Arrangement (from source comments) |
|---|---|---|---|
| `Layout1x1` | Full screen | 1 | the whole screen — **the fullscreen case §3 of the request asks for** |
| `Layout1x2` | 1 x 2 | 2 | side by side |
| `Layout1x3` | 1 x 3 | 3 | 3-wide row |
| `Layout1x4` | 1 x 4 | 4 | 4-wide row |
| `Layout1x6` | 1 x 6 | 6 | 6-wide row |
| `Layout2x1` | 2 x 1 | 2 | stacked |
| `Layout2x2` | 2 x 2 | 4 | grid |
| `Layout2x3` | 2 x 3 | 6 | grid |
| `Layout2x4` | 2 x 4 | 8 | grid |
| `Layout1P2` | 1 + 2 | 3 | 1 wide zone on top (half height) + 2 zones stacked below it |
| `Layout1P3` | 1 + 3 | 4 | verified: 1 left column + 3 right zones (top/mid/bottom, 1/3-height each) |
| `Layout1P4` | 1 + 4 | 5 | 1 left column + 4 right zones |
| `Layout2P1` | 2 + 1 | 3 | 2 zones + 1 zone |
| **`Layout2P3`** | **2 + 3** | **5** | **verified from source (`layout2+3.cpp:29-33`): left column split top/bottom (2 zones) + right column split into thirds top/middle/bottom (3 zones) — this is exactly the "three widgets on one side, two on another" example from the request** |
| `Layout4P2` | 4 + 2 | 6 | verified: left column split into quarters (4 zones stacked) + right column split in half (2 zones stacked) |
| `Layout4P2B` | 4 + 2B | 6 | a variant arrangement of the same 4+2 split |
| `Layout1x1AM` | App mode | 1 | full-screen app-mode variant; excluded from this plan (not a normal home-screen layout) |

**Decision:** the "layout galleries" track (§4, Track 2) uses `Layout1x1` (fullscreen heroes), `Layout1P2`, `Layout2P3` (the request's literal example), `Layout4P2`, and `Layout2x2` as the representative set — one screen per layout is enough to prove the layout renders correctly with real Gauge Pro instances in it; exhaustively covering all 17 layouts is listed as a stretch item in Phase C, not a hard gate (the fullscreen case and the "N+M" split case are the two structurally distinct layout families the request calls out by name).

---

## 3. Research — theme system

There is **no SD-card theme content in this repository** — `radio/src/gui/colorlcd/themes/theme_manager.cpp` scans `THEMES/<folder>/theme.yml` on the SD card at runtime (`scanThemeFolder`, line 294), but the actual theme folders (EdgeTX ships one built in called "EdgeTX") are SD-card assets from a separate packaging step, not vendored in `radio/src`. What **is** in this repo is:

1. A **compiled-in fallback palette** (`radio/src/gui/colorlcd/colors.h` + `colors.cpp:28-65`, `defaultColors[]`) — used whenever no theme.yml is found. This is the "stock" theme referenced throughout Gauge Pro's own colour-contract work: `SECONDARY3 = RGB(228,238,242) = #e4eef2` (main light background) and `PRIMARY1 = RGB(0,0,0)` (main ink) match the `#e4eef2` reference exactly, confirming this fallback **is** the "stock light" theme Gauge Pro's colour math is calibrated against. Fourteen theme roles total: `PRIMARY1/2/3`, `SECONDARY1/2/3`, `FOCUS`, `EDIT`, `ACTIVE`, `WARNING`, `DISABLED`, `QM_BG`, `QM_FG`, `CUSTOM`.
2. The **`theme.yml` schema** itself (`theme_manager.cpp:74-139`), fully reverse-engineered:
   ```yaml
   ---
   summary:
     name: GaugeProLab Dark
     author: Gauge Pro visual kit
     info: High-contrast dark theme for the Gauge Pro visual catalog
   colors:
     PRIMARY1: 0xF2F2F2
     PRIMARY2: 0x000000
     PRIMARY3: 0x1C1C1C
     SECONDARY1: 0x3A6EA5
     SECONDARY2: 0x2A2A2A
     SECONDARY3: 0x181818
     FOCUS: 0x14A1E5
     EDIT: 0x00B43C
     ACTIVE: 0xFFDE00
     WARNING: 0xE00000
     DISABLED: 0x707070
     QM_BG: 0x000000
     QM_FG: 0xFFFFFF
   ```
   (Colour values above are a first proposal, not final — actual values get chosen in Phase D against the luminance-window discipline in §1.3.) Colours may be written as `0xRRGGBB` or `RGB(r,g,b)` (`r_color`, line 43); the generator uses `0xRRGGBB` for readability.
3. **Theme selection** is a **general radio setting**, not a per-model one: `g_eeGeneral.selectedTheme` (`datastructs_private.h:1135`, a ≤25-char string that must equal the theme's folder name) is a top-level `selectedTheme` field in the YAML general-settings file (confirmed present in every board's `yaml_datastructs_*.cpp`, including `yaml_datastructs_tx16smk3.cpp:463`). This means switching theme means editing `RADIO/radio.yml` (the `--settings` tree), **not** the model file — the driver (§10) must regenerate/patch that one field between theme batches and `reset`.

**Decision — 3 themes, not a large theme matrix** (matches the request's "clear, readable, attractive, different enough to spot problems" brief without exploding the capture count):

| Theme | Folder | Purpose |
|---|---|---|
| **EdgeTX default** | *(none — no `THEMES/` folder on the generated SD card at all)* | Zero-config baseline; what Gauge Pro's own fixed status colours are calibrated against (§1.3). Free — costs no authoring. |
| **GaugeProLab Light** | `THEMES/GaugeProLab Light/theme.yml` | A deliberately higher-contrast, saturated light theme (distinct `SECONDARY1`/`FOCUS`/`ACTIVE` from stock) so a colour bound to the wrong role becomes visible. |
| **GaugeProLab Dark** | `THEMES/GaugeProLab Dark/theme.yml` | Dark background (`#181818`-class `SECONDARY3`), light ink — exercises the dark leg of Gauge Pro's own `#303030` luminance-window design target directly, on real firmware for the first time (the SVG mock only approximates this via `dev/svgkit.lua`'s static palette table, per memory `gaugepro-render-tooling`). |

Both new themes are authored to satisfy the WCAG-3:1-on-both-backgrounds constraint from §1.3 for their own text roles (`PRIMARY1` on `SECONDARY3`) — not just eyeballed — since a theme that itself fails contrast would make every screenshot captured under it useless for judging Gauge Pro's own contrast behaviour.

---

## 4. Test-screen architecture

Two tracks, sharing one option/value vocabulary (§1.1) and one zone vocabulary (§1.5), so nothing is invented twice.

### Track 1 — Single-widget catalog (mechanical port of `dev/scenes.lua`)

For every case in every one of the 13 existing sections (§1.4): one model screen, `Layout1x1` sized to the case's exact `zone` (or the nearest real zone from `dev/zone_atlas.lua` when the model format requires a whole-layout size rather than an arbitrary rectangle — resolved empirically in Phase A, see §17), one Gauge Pro instance, options = the case's `opts` merged over **every** DEFS default (§1.2), source/value = the case's `source`/`value` mapped onto a real registered sensor (§6). This inherits the full ~150-case coverage, the section grouping, and the audit discipline (`M.NON_VISUAL`) for free — **this track alone already satisfies "use all or almost all options" and "expose edge cases"** from the request, because that catalog already does.

Cases with a `post` mutation (stale/no-link/no-data, damping step-response, chip-off-but-critical) are reproduced by issuing the equivalent real action over the `--pipe` channel after the initial settle (e.g. `st-nolink`'s `mock.setValue(srcId, nil)` becomes: don't call `setTelemetryValue` for that sensor at all / call it once then stop updating it past the staleness timeout — exact mechanism nailed down empirically in Phase A against `telemetry.lua`'s real availability rules).

### Track 2 — Layout galleries (new; does not exist in the SVG catalog)

One screen per representative layout from §2 (`Layout1x1`, `Layout1P2`, `Layout2P3`, `Layout4P2`, `Layout2x2`), each zone populated with a **distinct, meaningfully different** Gauge Pro configuration — not the same config stamped N times — so the screen reads as a plausible radio home screen and a reviewer can visually compare configurations side by side under identical lighting/theme conditions. Concretely:

- **Fullscreen heroes** (`Layout1x1`, request's explicit examples): bar gauge full-screen; needle/clock-style (`Style=Needle`, `Sweep=360°`) full-screen; bar gauge with `ShowMinMax=Markers + text` + `Label`/`Suffix` overrides ("with additional details"); one more full-screen Bar variant using a segmented `BarFace` (Hex or Ticks) to show the "other full-screen Gauge Pro variants currently supported" the request asks for.
- **`Layout2P3`** ("three on one side, two on another" — request's literal example): 2 left zones in Needle/Arc dial styles at normal/warning state, 3 right zones in Bar style at normal/warning/critical state — one screen demonstrating dial and bar families together.
- **`Layout1P2`, `Layout4P2`, `Layout2x2`**: each a themed mix of Style × ColorMode picked to maximize visual distinctness within the zone budget, one screen per theme from §3 for at least the `Layout2P3` and one fullscreen hero (the cross-theme comparison subset — see §4.1).

### 4.1 Theme comparison subset

Not a full cross-product (150 cases × 3 themes = 450 captures is disproportionate to the marginal information gained — most cases don't touch a theme role at all, since Gauge Pro's status colours are fixed literals per §1.3). Instead: the `estado` and `color` sections in full (17 cases — these are exactly the sections that exercise `COLOR_THEME_*` data-channel roles alongside the fixed status colours) plus the `Layout2P3` layout gallery screen and one fullscreen hero, each **repeated under all 3 themes**. That is `(17 + 2) × 3 = 57` theme-tagged screenshots — enough to catch a theme/status collision (the exact class of bug §1.3's history describes) without multiplying the whole catalog.

---

## 5. Gauge configuration matrix

This **is** §1.1's DEFS table — restated here only as a checklist derived mechanically from it, not re-invented:

- **Structural / always visible:** Style, ColorMode, Sweep, ShowMinMax, Precision, ShowChip, HighGood, Scale, BarPreset, BarFace, BarDir, BarOrigin, BarSize, BarEnds, Segments, SegGap, Palette, Surface, Contrast, BarHead, ScaleMarks, ValuePos, LabelPos, Cells, Battery — all appear varied across Track 1's ported sections (`dial`, `barra`, `caras4`, `ejes5`, `bateria`) already.
- **Parametric / colour:** Accent, WarnClr, CritClr, TrackClr, PanelClr — covered in `acento` and `paleta`.
- **Text:** Label, Suffix — covered in `texto`.
- **Numeric:** Min, Max, Warn, Crit, Damping — covered in `escala`, `aguja`.
- **Excluded, with reason** (§1.1's non-visual table): Alerts, AlertSw, Delay, Vibrate, ResetSw. Motion is excluded from **still frames** but is the one option explicitly given its own treatment in §6 (dynamic transitions), since "cannot be seen in a still frame" is not the same as "cannot be validated visually."

A coverage cross-check (mirroring `gallery.lua`'s existing DEFS-vs-cases diff) is a Phase F gate item (§16), so a future option added to `main.lua` without a corresponding scene fails the catalog build loudly instead of silently under-covering.

---

## 6. Simulated telemetry strategy

**No firmware changes needed.** `radio/src/lua/api_general.cpp:1989` (`setTelemetryValue(id, subId, instance, value, unit, prec, name)`) is a **public, standard EdgeTX Lua global**, available on real hardware and in `simu` alike — it registers a real sensor in the real sensor registry and sets its value, exactly the fidelity Gauge Pro's own `telemetry.lua` expects (`getValue`/`getFieldInfo`/`CELLS` aggregation all behave as on-radio). This is a strictly better mechanism than anything `WIDGET_STUDIO`-gated, and it means telemetry setup is **pure SD-card Lua**, not another firmware hook.

**Source table** — reuse `dev/scenes.lua`'s own `M.SOURCES` (§1.4) verbatim (already-validated ids/units/precisions): `RSSI` (id 3072, unit 17), `RxBt` (3081, unit 1, 2dp, has min/max history siblings), `Cels` (3075, unit 1, 2dp — the `CELLS` table source), `T1` (3078, unit 11 — a low-is-good preset source). Non-telemetry sources (`Thr`, `Ail`, a generic channel, a timer) use the already-built `simu.setAnalog()` engine hook or the model's own timer, exactly as Track 1's ported cases require.

**Value sweep** — inherited directly from each ported case's literal `value` field, which already spans (against the default `Warn=55`/`Crit=35`, `HighGood=1` scale): normal (`78`), warning-band (`45`), critical-band (`22`), scale extremes (`0`, `100`), and deliberately out-of-range / cliff / descending-scale edge cases (`sc-outofrange`, `sc-cliff`, `sc-descending`). No new value design work — this satisfies the request's "low / normal / mid / high / near-threshold / warning / critical / near-min / near-max" brief because the existing catalog was already built to that brief.

**Dynamic transitions (Motion, damping, critical pulse)** — a real still-PNG catalog cannot show motion, but a **short deterministic filmstrip** can: for the handful of cases that are specifically about motion (`ne-damp0`/`ne-damp9` step response, the critical-state pulse), capture N frames (e.g. 6, at the pipe's natural ~16 ms cadence, `capture` reissued between fixed `key`/no-op ticks) into `<case>_frame1.png … frame6.png`. This is listed as **Phase E, optional/stretch** — it multiplies capture count for a small, clearly-scoped set of cases, not the whole catalog, and it directly answers the request's "simulate dynamic data transitions so we can observe animations."

---

## 7. Screen naming convention

`{seq:03d}_{section}_{case-name}.png`, with `{section}` and `{case-name}` copied **verbatim** from `dev/scenes.lua`'s own `sec.key` / `case.name` fields (e.g. `014_color_color-threshold-crit.png`, `102_barra_br-mode-gradient.png`) — this is a deliberate choice to avoid a second, divergent naming taxonomy; the existing SVG catalog and this one describe the same case under the same name, so a reviewer cross-referencing `docs/phase0/full-validation/` against the new kit never has to guess which SVG matches which PNG. `{seq}` is assigned once, in section-then-declaration order, and is stable across regenerations as long as the section/case list itself doesn't reorder (append-only, same discipline as the option slots in §1.1).

Track 2 and theme-tagged screens use two purpose-built prefixes so they don't collide with Track 1's namespace:

- Layout galleries: `L{seq:02d}_layout_{LayoutId}_{descriptor}.png` (e.g. `L03_layout_Layout2P3_dial-vs-bar.png`).
- Theme comparison: `{seq:03d}_{section}_{case-name}__{theme-slug}.png` (e.g. `014_color_color-threshold-crit__gaugeprolab-dark.png`), theme-slug ∈ `{stock, gaugeprolab-light, gaugeprolab-dark}`.

Motion filmstrips (§6): `{seq:03d}_{section}_{case-name}__frame{N}.png`.

---

## 8. Screenshot architecture

No new firmware code. Reuses, exactly as already built and proven (`widget-visual-emulator-plan.md` §9a):

- `simuCaptureArm(path)` / `simuLcdNotify()` force-redraw fix — deterministic one-shot PNG dump of the next frame, armed and consumed automatically, no wall-clock races.
- `--pipe <path>` steering channel: `reset` (reload settings + model — used between **model** batches and **theme** batches, since `selectedTheme` and the current model are both general-settings/SD-tree state), `capture <path>`, `key <code> <0|1>` (paging between a model's own `screenData[]` entries via PAGEUP/PAGEDN, `KEY_PAGEUP=3`/`KEY_PAGEDN=4`, when several Track-1 screens are packed into one 10-screen model budget), `touch`/`touchup` (unused by this catalog — no interactive UI flow is being demonstrated, only static configured screens).

Driver-side capture loop per model file: `reset` → wait for boot alerts to clear (the two first-boot `raiseAlert` dialogs, dismissed with `KEY_ENTER` — a known, already-solved sequence from the Phase 1 spike) → for each of that model's up to `MAX_CUSTOM_SCREENS=10` screens: `capture <path>`, then `key 3 1`/`key 3 0` (PAGEDN) to advance, with a short settle delay honoring the critical-pulse-crest rule already established in `dev/scenes.lua:155-173` (advance until `frame.pulse` is at its crest — same 50 ms/11-frame rule, ported as-is since the underlying widget clock is unchanged) → next model.

---

## 9. Repository directory structure

```
WIDGETS/GaugePro/
  docs/
    phase0/full-validation/         # existing SVG catalog — untouched
    visual-kit/                     # NEW — this plan's committed output
      screenshots/
        001_estado_st-normal.png
        ...
        L01_layout_Layout1x1_bar-hero.png
        ...
      CATALOG.md                    # generated: one row per screen (§13)
      INDEX.md                      # generated: browsable thumbnail gallery (§13)
      RUN_SUMMARY.md                # generated: condensed last-run stats (§11)
  dev/
    visual-kit-run/                 # gitignored — scratch SD tree, settings, logs
      sdcard/MODELS/*.yml
      sdcard/THEMES/GaugeProLab Light/theme.yml
      sdcard/THEMES/GaugeProLab Dark/theme.yml
      settings/RADIO/radio.yml
      run.log.jsonl

tools/
  gaugepro-visual-kit/               # NEW — the Python driver package (§10)
    __init__.py
    catalog.py       # loads dev/scenes.lua's case list (via the Lua defs dump, §10) + the Track 2/theme case lists
    defs.py           # loads the DEFS dump (§10), exposes option translation
    modelgen.py       # writes MODELS/*.yml + THEMES/*/theme.yml + RADIO/radio.yml patches
    driver.py          # owns the simu process + --pipe channel
    report.py          # writes CATALOG.md / INDEX.md / RUN_SUMMARY.md / run.log.jsonl
    run.py              # CLI entrypoint, subcommands per §10
    defs_dump.lua       # loads both real Pro frontends; dumps schema 2 contracts
```

**Why `WIDGETS/GaugePro/docs/visual-kit/` and not a top-level `docs/gauge-pro/visual-kit/` or `tests/visual/gauge-pro/`:** this repo already has exactly this precedent, and it already carves the exception out of `.gitignore` — `WIDGETS/GaugePro/.gitignore:9-11`: *"NOT ignored, deliberately: docs/ holds the official option collage... unlike dev/shots/, which is scratch."* There is no top-level `tests/` directory in this repo to extend, and `docs/gauge-pro/` (top-level) would split Gauge Pro's documentation across two locations for no benefit. `tools/gaugepro-visual-kit/` mirrors the sibling `tools/widget-studio/` package the other plan proposes (not yet built), keeping the two tools visually consistent if both exist later.

**No `.gitignore` changes needed** for the committed artifacts (they land under the already-excepted `docs/` path); one new line is added for `dev/visual-kit-run/` (parallel to the existing `dev/shots/` entry).

---

## 10. Script / harness architecture

Single Python entrypoint, `python tools/gaugepro-visual-kit/run.py <subcommand>`, subcommands:

| Subcommand | Behavior |
|---|---|
| `check` | Extracts both real frontend contracts, converts all scenes, rejects family leakage and verifies generated YAML contains `DialPro` + `BarPro` but never legacy `GaugePro`; does not launch simu. |
| `generate` | Writes schema-2 `defs.json` and `scenes.json`, builds the 56 Dial/150 Bar Track 1 catalog and eight Track 2 layouts, validating every override against its family contract. |
| `capture` | Boots `simu` (must already be built with `-DWIDGET_STUDIO=ON`, `ws build`-equivalent — reuses the exact CMake option from the other plan's §4.1, already merged) headless (`SDL_VIDEODRIVER=dummy`), drives it over `--pipe` per §8, collects PNGs into `docs/visual-kit/screenshots/`, appends one JSONL row per screen to `run.log.jsonl`. |
| `report` | Regenerates `CATALOG.md`, `INDEX.md`, `RUN_SUMMARY.md` from the same catalog + the run log — never hand-edited (§13). |
| `all` | `defs` → `generate` → `capture` → `report`, in order. **This is the "single script" the request asks for.** Nonzero exit if any screen failed (§12). |

No new language toolchain: Python 3 (repo precedent, `tools/*.py`), Lua 5.3.6 (already installed per memory `lua-toolchain`), the already-built `simu` binary.

---

## 11. Logging strategy

- `dev/visual-kit-run/run.log.jsonl` (gitignored, regenerated every run): one JSON line per screen — `{seq, section, case, model_file, theme, zone, capture_path, ms, bytes, status}`, `status` ∈ `PASS | WARN | FAIL`. This is the diagnostic detail layer — verbose by design, but scoped to exactly one line per screen, not per frame or per pipe command.
- `docs/visual-kit/RUN_SUMMARY.md` (committed): a short, human-readable snapshot of the **last successful** run — totals only (screens generated, PASS/WARN/FAIL counts, wall-clock, `simu` build hash) — not a growing history. This directly follows the request's "do not create excessive useless logs" instruction: the noisy detail stays out of git, the useful summary stays in it.
- `simu`'s own stderr (already emits `TRACE(...)` lines and Lua `error()` output) is captured per-model-batch into `dev/visual-kit-run/simu-<batch>.stderr.log` (gitignored) and scanned for known warning markers (`error:`, `LV_LOG_ERROR`, `assert`) — any hit against the batch currently capturing downgrades that screen's row to `WARN` even if the PNG itself wrote successfully, since a silent Lua error before a render is exactly the kind of defect §10/§11 of the request calls out ("widget rendering failures", "runtime exceptions").

---

## 12. Failure detection

`capture` verifies, per screen, before moving on:

1. The PNG file exists and is non-zero-byte.
2. Its `IHDR` chunk (first 33 bytes — hand-parsed, no new dependency) reports the expected `LCD_W × LCD_H` for the configured resolution. A wrong size means the capture caught the wrong screen (e.g. a boot alert still on top) — `FAIL`, not a silently-wrong image.
3. No `FAIL`/`WARN` stderr marker landed for that batch (§11).

A `simu` process crash or an unresponsive pipe (`capture` command not acknowledged within a timeout) aborts **only the current model batch**: remaining screens in that batch are logged `FAIL` with the reason, the process is restarted, and the run continues with the next model. `run.py all`'s exit code is nonzero iff any row is `FAIL` (CI-compatible, mirrors acceptance criterion 6 of the Widget Studio plan this one builds on).

---

## 13. Documentation structure

`CATALOG.md` and `INDEX.md` are **generated, never hand-written** — both read the same catalog object `generate` and `capture` already consumed (one source of truth, per the request's explicit "should come from the same source of truth so they do not become inconsistent"):

- `CATALOG.md`: one row per screen — name, id (`seq`+section+case), layout, full option diff from defaults (only non-default DEFS values are printed — a 44-column table per row would be unreadable), theme, source/value, Warn/Crit thresholds, the case's own `note`/`title` from `dev/scenes.lua` where present (already-authored expected-behavior text, reused rather than rewritten), and a relative Markdown image link to the screenshot.
- `INDEX.md`: a browsable gallery — one `##` heading per section (13 from Track 1 + `layouts` + `themes`), a Markdown image grid underneath (plain `![](...)` sequences sized via HTML `<img width>` — no new JS/CSS dependency, renders natively on GitHub).
- `RUN_SUMMARY.md`: §11.

---

## 14. Visual catalog structure

15 sections total in the generated docs: the 13 existing `dev/scenes.lua` sections (§1.4, §4 Track 1) unchanged, plus two new ones this plan adds:

| New section key | Title | Content |
|---|---|---|
| `layouts` | Layout galleries | Track 2, §4 |
| `themes` | Theme comparison | The 57-screen theme-tagged subset, §4.1 |

---

## 15. Reproducibility requirements

- Fully deterministic given: a pinned `simu.exe` build (`-DWIDGET_STUDIO=ON`), the pinned Lua 5.3.6 toolchain, and the catalog's own literal values (no randomness anywhere in the case list, matching the discipline `dev/scenes.lua` already established).
- The one known non-determinism source — the critical-state pulse's animation phase — is neutralized the same way `dev/scenes.lua:155-173` already solved it for the SVG loop: settle to the pulse crest on a fixed frame-count/cadence rule before capturing, ported as-is (§8).
- **Acceptance test:** two consecutive `run.py all` invocations against the same `simu` build must produce byte-identical PNGs for every screen (a checksum diff, not a visual diff) — this is the actual gate for "the process should be deterministic and easy to rerun," not just an aspiration.

---

## 16. Validation criteria

1. Every DEFS option not in the §1.1 non-visual exclusion list is varied (non-default) in at least one generated screen — mechanical cross-check against `defs.json`, ported from `gallery.lua`'s existing equivalent logic.
2. All 5 representative layouts from §2 appear in at least one Track 2 screen; `Layout2P3` specifically is present (the request's literal example).
3. All 3 themes from §3 render every screen in the §4.1 subset without a `FAIL`.
4. Reproducibility acceptance test (§15) passes.
5. `run.py all` exits 0 on a clean checkout with only `simu` prebuilt — no manual steps, no hand-edited intermediate file.
6. `CATALOG.md` row count equals `INDEX.md` image count equals `screenshots/` PNG count (no orphaned or missing artifacts) — a cheap, mechanical cross-check worth automating in `report`.

---

## 17. Implementation phases and gates

| Phase | Scope | Gate |
|---|---|---|
| **A — Generator core** | `defs_dump.lua` + `defs.py`; `modelgen.py` writes one valid `MODELS/*.yml` + boots real `simu`, confirms it loads without error; resolve the two remaining empirical unknowns flagged above: (a) whether an arbitrary Track‑1 zone rectangle must snap to a real `Layout1x1` (it should — `Layout1x1` is the whole screen, and per-widget sizing inside it is set by the layout's own options, not free-form — verify against `layout1x1.cpp`'s options in this phase) or needs a per-size synthetic layout; (b) the exact YAML `Source` string grammar for a telemetry-sensor option value vs. a fixed internal source (`TX_VOLTAGE` was confirmed to work as a literal string in the prior spike — confirm the same holds for a `setTelemetryValue`-registered sensor by name). | A `defs.json` that matches `main.lua`'s DEFS byte-for-byte in content; one hand-verified screenshot of a non-trivial option combination, produced through `generate`+`capture`, not hand-authored YAML. |
| **B — Track 1 catalog** | Full ~150-case port, stock theme only. | §16 criteria 1, 5 hold for Track 1 alone; reproducibility (§15) holds. |
| **C — Track 2 layout galleries** | The 5 representative layouts, §4. | §16 criterion 2. |
| **D — Themes** | Author + tune the two `GaugeProLab` themes against the §1.3/§3 contrast constraint; run the §4.1 subset. | §16 criterion 3. |
| **E — Telemetry dynamics (stretch)** | Motion filmstrips, §6. | Filmstrips exist for the damping and critical-pulse cases; does not block F. |
| **F — Reporting & polish** | `CATALOG.md`/`INDEX.md`/`RUN_SUMMARY.md` generation, coverage cross-check (§16.1), exit codes, a short `docs/visual-kit/README.md` pointing at the gallery. | All of §16 holds; `run.py all` green end-to-end on a clean checkout. |

---

## 18. Expected final artifacts

- `tools/gaugepro-visual-kit/` — the Python driver + Lua defs-dump shim (§9, §10).
- `WIDGETS/GaugePro/docs/visual-kit/screenshots/*.png` — the committed visual catalog (Track 1 + Track 2 + theme subset + optional filmstrips).
- `WIDGETS/GaugePro/docs/visual-kit/CATALOG.md`, `INDEX.md`, `RUN_SUMMARY.md`, `README.md` — generated documentation.
- Two authored themes seeded into the tool (`tools/gaugepro-visual-kit/themes/*.yml`, copied into the scratch SD tree at run time — not committed as real radio `THEMES/` content, since that's runtime SD-card state, not source).
- `defs.json` — the mechanically-extracted, drift-checked mirror of Gauge Pro's option table, reusable by any future tooling (including the generic Widget Studio driver, if it gets built later).
- One new `dev/visual-kit-run/` line in `WIDGETS/GaugePro/.gitignore`.

---

## Appendix: what this plan deliberately does not (re)do

- Does not touch firmware. Every engine hook this plan depends on (`--pipe`, `simuCaptureArm`, `WIDGET_STUDIO`) already exists and already passed its own gate (`widget-visual-emulator-plan.md` §9a, 2026-08-10).
- Does not re-author Gauge Pro's option/scenario catalog — it ports `dev/scenes.lua`'s existing, audited one.
- Does not attempt the generic multi-widget "any standard-contract widget" platform from the Widget Studio plan (its Q9/Q11 decisions) — this driver is intentionally Gauge-Pro-specific.
- Does not build a golden-image pixel-diff/regression gate — this is a **catalog** (documentation + visual reference), not a CI regression suite. If a future need for automated visual regression on Gauge Pro emerges, it should be scoped as its own follow-up against this same screenshot set, not folded in here.
