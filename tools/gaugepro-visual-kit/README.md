# Gauge Pro visual kit

Real-firmware visual validation catalog for the Gauge Pro widget. See
`myplans/gaugepro-visual-kit-plan.md` for the full design.

Renders every Gauge Pro option combination worth looking at through the
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
python run.py all                     # generate + capture (track 1 + 2) + report
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
log, see `RunLog.drop_sections`) and call `report` once at the end -- `all`
does this for track 1 + 2 automatically but not `--themes-only`, which is
run and reported separately.

## How it works

- `defs_dump.lua` / `scenes_dump.lua`: load the REAL `WIDGETS/GaugePro/main.lua`
  and `dev/scenes.lua` under the widget's own test mock
  (`tests/mock_env.lua`) and dump the option table / scenario catalog as
  JSON. Zero hand-duplication -- this can never silently drift from the
  widget source (see `main.lua`'s own Tanda 6 F-14 note on exactly that risk).
- `defs.py`: translates readable option overrides (`{"Style": "Bar"}`) into
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
- `catalog.py`: Track 1 (single-widget, ported from `dev/scenes.lua`) and
  Track 2 (layout galleries) screen lists.
- `driver.py`: owns the `simu` process and the `--pipe` steering channel.
  Switches models by a full process **restart** (stop, then start with a
  freshly written model selected), not an in-place reset -- see the module
  docstring for the two regressions that made the in-place design unsafe
  (an autosave race, and a `radio.yml` checksum rejection).
- `themes/`: the two authored `theme.yml` files (Sec 3), copied into the SD
  tree's `THEMES/` by `run.py`'s `seed_themes()`.
- `sd_extra/`: static SD-card content copied in on every run --
  `WIDGETS/TeleInject` (a companion widget for telemetry injection, built
  but not currently wired to any capture path -- see Known limitation) and
  its data file.
- `report.py`: generates the docs from `run.log.jsonl`.
- `verify_dupes.py`: post-run check for screenshots that are byte-identical
  to a *different* case's screenshot -- the signature of a capture/reset
  race. Run after any change to the driver or capture timing.

## Known limitation (this pass)

Every Track 1/2 screen uses `TX_VOLTAGE` (a real, always-live internal
source, no setup needed) rather than a dynamically registered telemetry
sensor, remapped through a linear window (`catalog.voltage_window`) so each
scene's *relative* value/threshold positions are preserved even though the
literal displayed number isn't the scene's original one.

Real per-sensor telemetry injection (CELLS aggregation, stale/no-link
states, a live step for the damping cases) needs a `telemetrySensors[]`
entry pre-declared in the model YAML for the Source option to resolve at
all. The union encoding was decoded (`catalog.py`'s module docstring has
the exact field mapping) and a hand-written entry DID load without a parse
error, but the resulting screen showed the radio's setup chrome instead of
the Gauge Pro home view, with no error in `simu.log` to explain why -- root
cause not found within a bounded follow-up effort. 16 of 222 `dev/scenes.lua`
cases are skipped for this reason, listed with their exact reason in the
generated `CATALOG.md`.

The `zonas` section (Sec 4 Track 1) is the only part of the single-widget
catalog that varies canvas size; every other Track 1 case renders
full-screen regardless of the size its original `dev/scenes.lua` case named
(a few cases -- e.g. `tx-prec2-micro`, `br-tall` -- were specifically about
behavior at a constrained size, and that aspect isn't exercised here).
