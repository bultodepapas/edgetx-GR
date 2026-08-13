# Gauge Bar Pro

Gauge Bar Pro (`BarPro` in the EdgeTX widget picker) is the linear member of
the Gauge Pro telemetry family for EdgeTX color radios. This first public
version is a **beta candidate**: it is ready for broader user feedback after
the remaining release gates in the
[beta/pre-PR review](../GaugePro/docs/PRE-PR-BETA-REVIEW-2026-08-13.md) are
closed.

## What it provides

- Responsive horizontal and vertical rails for micro, compact, normal, large
  and fullscreen zones.
- Continuous, spatial Gradient, Blocks, Hex, Fine Ticks, Signal Steps and Dual
  Rail faces, with source-aware Auto selection and explicit overrides.
- Threshold-aligned severity context, an exact position head, zero origin,
  low-is-good/descending ranges and independent min/max/ghost history.
- Four thickness levels, round/square/chamfer ends, configurable scale marks,
  value/name placement, panels, palettes and custom colors.
- Theme-aware normal, warning, critical and unavailable states, retained
  object ceilings and bounded motion profiles.
- Numeric telemetry, timers, sticks, channels, GVars, transmitter battery and
  battery/cell interpretation through the shared Gauge Core runtime.

EdgeTX 2.11 exposes the stable ten-option compatibility contract. EdgeTX
2.12+ exposes all 42 Bar Pro options. Published option positions are
append-only so saved model settings remain compatible.

## Installation

Gauge Bar Pro is a small front end. It **requires** the matching shared
runtime at `/SCRIPTS/TOOLS/GaugeCore/`; copying only this directory will not
work. From the repository root, install the exact SD-card layout with:

```powershell
pwsh WIDGETS/GaugePro/dev/sync-sd.ps1 -Destination E:\
```

This installs both current widgets and the shared core. Use `-IncludeLegacy`
only when the migration guide requires the transitional `GaugePro` widget.
Before removing an existing legacy folder, read
[`MIGRATION.md`](../GaugePro/MIGRATION.md).

Required SD-card paths:

```text
/WIDGETS/GaugeBarPro/main.lua
/SCRIPTS/TOOLS/GaugeCore/*.lua
```

Compatibility: EdgeTX 2.11+ with the LVGL Lua API. The project is developed
against EdgeTX 3.0 while preserving the tested 2.11 registration contract.

## Beta safety and feedback

Back up the SD card and model configuration before installation. Do not use
this beta widget as the only warning for a flight-critical condition; retain
the radio's normal alarms and telemetry failsafes.

Bug reports and feature, option or visual-improvement requests are welcome.
Please include the radio model, exact EdgeTX version, telemetry source,
layout/zone, theme, non-default options, expected behavior, actual behavior,
and a screenshot or simulator log when available.

## Documentation and verification

- [Gauge Pro overview and test commands](../GaugePro/README.md)
- [Full user and technical reference](../GaugePro/DOCS.md)
- [Migration guide](../GaugePro/MIGRATION.md)
- [Latest visual-run summary](../GaugePro/docs/visual-kit/RUN_SUMMARY.md)
- [2026-08-13 beta/pre-PR review](../GaugePro/docs/PRE-PR-BETA-REVIEW-2026-08-13.md)

License: GPLv2, as declared in the source files.
