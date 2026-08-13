# Gauge Dial Pro + Gauge Bar Pro visual kit

Real-firmware visual validation catalog for both split Gauge Pro widgets. See
`myplans/gaugepro-visual-kit-plan.md` for the full design.

Renders the DialPro and BarPro option combinations worth looking at through the
**actual firmware** (native `simu`, real LVGL, real Lua binding, real
themes) and captures deterministic PNGs into
`WIDGETS/GaugePro/docs/visual-kit/screenshots/`, with a generated
`CATALOG.md` (one row per screen, options + link) and `INDEX.md` (browsable
gallery).

## Prerequisites

- `simu` built with `-DWIDGET_STUDIO=ON` (see `radio/src/targets/simu/CMakeLists.txt`):
  ```
  cmake --preset simu -DWIDGET_STUDIO=ON
  cmake --build build/simu --target simu
  ```
- Lua 5.3.6 on PATH as `lua` (or pass `--lua <path>`).

## Usage

From this directory:

```
python run.py all                     # generate + capture (tracks + themes) + report
python run.py check                   # split contracts + YAML, no simulator
python run.py generate                # dump defs.json/scenes.json, print counts only
python run.py capture                 # (re)run track 1 + 2 against the last generate
python run.py capture --track1-only   # just the single-widget catalog
python run.py capture --track2-only   # just the layout-gallery screens
python run.py capture --themes-only   # the theme-comparison subset (Sec 4.1)
python run.py report                  # rebuild CATALOG.md/INDEX.md/RUN_SUMMARY.md
                                       # from the existing run.log.jsonl
```

`report` merges whatever is already in `run.log.jsonl`, so run the three
`capture` variants you want (they each only touch their own section of the
log, see `RunLog.drop_sections`) and call `report` once at the end. `all` is
the release-evidence path and captures Track 1, Track 2 and the theme subset
under one fresh run ID before generating the report.

## Current verification

Verified on the repository's `build/simu/simu.exe` after the Pro split:

- `check`: 69 DialPro + 152 BarPro Track 1 scenes; mixed YAML contract passed.
- Track 1: 221/221 captures completed; eight rich-source cases are documented
  skips rather than retained screenshots.
- Track 2: 8/8 layouts completed, including the 2-dial/3-bar screen.
- Themes: 48/48 captures completed across stock, GaugeProLab Light and Dark.
- Full evidence: 277 fresh PASS, 0 WARN, 0 FAIL, 0 unreferenced PNGs and
  0 unexpected duplicate groups.
- Runtime log: only `DialPro`, `BarPro` and the `TeleInject` helper loaded;
  no Lua/core errors.
- Eight structured/timer/history cases remain explicitly skipped below.

## How it works

- `defs_dump.lua`: loads the REAL `GaugeDialPro/main.lua` and
  `GaugeBarPro/main.lua` contracts and writes the 24-slot/42-slot schema,
  including IDs, folders, families and `coreApi`.
- `scenes_dump.lua`: loads the audited legacy `dev/scenes.lua` catalogue.
  `catalog.py` converts its old `Style` selector exactly once into a fixed
  DialPro or BarPro family and rejects cross-family options.
- `defs.py`: translates readable family-specific overrides into
  the model-YAML wire format, empirically reverse-engineered by round-tripping
  a hand-authored zone through the real firmware (see
  `myplans/widget-visual-emulator-plan.md` Sec 9a and `defs.py`'s docstring).
- `layouts.py`: real EdgeTX screen-layout zone geometry, transcribed from
  `WIDGETS/GaugePro/dev/zone_atlas.lua`'s own parse of
  `radio/src/gui/colorlcd/layouts/*.cpp`. `nearest_zone()` maps an arbitrary
  target size onto the closest real (LayoutId, zone_index) -- used for the
  `zonas` section, the one place Track 1 varies canvas size instead of
  rendering full-screen.
- `modelgen.py`: assembles full model YAML text from a proven-working
  skeleton (a file the real firmware itself wrote and reloaded). Model
  filenames MUST match `model<digits>.yml` -- `ModelsList::loadYaml()`
  (`radio/src/storage/modelslist.cpp`) silently skips anything else when
  scanning `MODELS/` at boot.
- `run.py` seeds `/SCRIPTS/TOOLS/GaugeCore/`, `/WIDGETS/GaugeDialPro/` and
  `/WIDGETS/GaugeBarPro/`. Its disposable SD tree removes a stale GaugePro
  legacy frontend and compiled `.luac` siblings before every run, so the
  simulator exposes exactly the default two widgets and cannot execute stale bytecode.
  After the one-time bootstrap it also replaces only `model<digits>.yml` files inside
  its scratch SD tree, preventing old `widgetName: GaugePro` models from contaminating a run.
  Generated model names are bounded to EdgeTX colorlcd's 15-character
  `LEN_MODEL_NAME`, and the same bounded marker is used by the boot waiter.
- `catalog.py`: Track 1 (single-widget, ported from `dev/scenes.lua`) and
  Track 2 (layout galleries) screen lists.
- `driver.py`: owns the `simu` process and the `--pipe` steering channel.
  Switches models by a full process **restart** (stop, then start with a
  freshly written model selected), not an in-place reset -- see the module
  docstring for the two regressions that made the in-place design unsafe
  (an autosave race, and a `radio.yml` checksum rejection).
  Layout captures additionally reject a byte-identical successor: a dropped
  `PageDown` is retried, and a persistent unchanged page becomes a FAIL.
- `themes/`: the two authored `theme.yml` files (Sec 3), copied into the SD
  tree's `THEMES/` by `run.py`'s `seed_themes()`.
- `sd_extra/`: static SD-card content copied in on every run --
  `WIDGETS/TeleInject` (a companion widget for telemetry injection, built
  into the scalar telemetry capture path) and its data file.
- `report.py`: generates the docs from `run.log.jsonl`.
- `verify_dupes.py`: post-run check for screenshots that are byte-identical
  to a *different* case's screenshot -- the signature of a capture/reset
  race. Run after any change to the driver or capture timing.

## Known limitation (this pass)

The runner now emits valid telemetry declarations and drives scalar RSSI,
RxBt, T1, current/history values, stale/current/link loss and stepped damping
through the native firmware path. Cases that do not require a dynamic sensor
may still use the real always-live `TX_VOLTAGE` source with a relative window.

Eight cases remain skipped: six require a structured multi-instance CELLS
source, one needs timer-typed source control and one needs descending-history
orchestration. Their exact reasons are generated in `CATALOG.md`; no old PNG is
retained in their place.

The `zonas` section (Sec 4 Track 1) is the only part of the single-widget
catalog that varies canvas size; every other Track 1 case renders
full-screen regardless of the size its original `dev/scenes.lua` case named
(a few cases -- e.g. `tx-prec2-micro`, `br-tall` -- were specifically about
behavior at a constrained size, and that aspect isn't exercised here).
