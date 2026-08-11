# Install the shared GaugeCore plus the two visible widget frontends.
#
#   pwsh dev/sync-sd.ps1
#   pwsh dev/sync-sd.ps1 -Destination E:\
#   pwsh dev/sync-sd.ps1 -Destination E:\ -IncludeLegacy
#
# The default package installs GaugeDialPro and GaugeBarPro. The optional
# transition package also refreshes GaugePro. For model safety, an existing
# legacy folder is never deleted automatically, so an upgraded SD can still
# show three widgets until GaugePro is removed manually after migration.

param(
  [string]$Destination = "D:\SD",
  [switch]$IncludeLegacy
)

$legacySource = [System.IO.Path]::GetFullPath(
  (Split-Path -Parent $PSScriptRoot))
$repoRoot = [System.IO.Path]::GetFullPath(
  (Join-Path $legacySource "..\.."))
$destinationPath = [System.IO.Path]::GetFullPath($Destination)

$coreManifest = @(
  "app.lua", "options.lua", "theme.lua", "geometry.lua", "ranges.lua",
  "presets.lua", "format.lua", "smoothing.lua", "motion.lua",
  "telemetry.lua", "layout_common.lua", "ui_core.lua", "dial_layout.lua",
  "dial_renderer.lua", "bar_layout.lua", "bar_style.lua", "bar_faces.lua",
  "bar.lua", "alerts.lua"
)
$frontManifest = @("main.lua")
$legacyManifest = @("main.lua") + $coreManifest

function Get-ValidatedTarget {
  param([string]$Relative, [string]$ExpectedSuffix)
  $target = [System.IO.Path]::GetFullPath(
    (Join-Path $destinationPath $Relative))
  $suffix = $ExpectedSuffix.Replace("/", [System.IO.Path]::DirectorySeparatorChar)
  if (-not $target.EndsWith($suffix,
      [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing unsafe target: $target"
  }
  return $target
}

function Copy-RuntimeManifest {
  param(
    [string]$Name,
    [string]$Source,
    [string]$Target,
    [string[]]$Manifest
  )

  New-Item -ItemType Directory -Force -Path $Target | Out-Null

  # EdgeTX can prefer compiled siblings. Only direct children of the exact,
  # suffix-validated target are touched; no recursive cleanup is performed.
  $staleBytecode = @(Get-ChildItem -LiteralPath $Target -Filter "*.luac" -File)
  foreach ($file in $staleBytecode) {
    Remove-Item -LiteralPath $file.FullName -Force
  }

  $copied = 0
  foreach ($file in $Manifest) {
    $sourceFile = Join-Path $Source $file
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
      throw "$Name missing runtime module: $sourceFile"
    }
    Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $Target $file) -Force
    $copied++
  }

  $expected = @{}
  foreach ($file in $Manifest) { $expected[$file.ToLowerInvariant()] = $true }
  $unexpected = @(Get-ChildItem -LiteralPath $Target -Filter "*.lua" -File |
    Where-Object { -not $expected.ContainsKey($_.Name.ToLowerInvariant()) })
  foreach ($file in $unexpected) {
    Write-Warning "$Name retains unmanifested Lua file: $($file.FullName)"
  }

  $bytes = (Get-ChildItem -LiteralPath $Target -File |
    Measure-Object Length -Sum).Sum
  if ($null -eq $bytes) { $bytes = 0 }
  $kb = [math]::Round($bytes / 1KB, 1)
  Write-Host "$Name -> $Target  ($copied files, $kb KB, $($staleBytecode.Count) stale .luac removed)"
}

$coreTarget = Get-ValidatedTarget "SCRIPTS\TOOLS\GaugeCore" "SCRIPTS\TOOLS\GaugeCore"
$dialTarget = Get-ValidatedTarget "WIDGETS\GaugeDialPro" "WIDGETS\GaugeDialPro"
$barTarget = Get-ValidatedTarget "WIDGETS\GaugeBarPro" "WIDGETS\GaugeBarPro"

# Copy order is contractual: a radio must never receive a frontend before the
# core it requires is present.
Copy-RuntimeManifest "GaugeCore" $legacySource $coreTarget $coreManifest
Copy-RuntimeManifest "GaugeDialPro" (Join-Path $repoRoot "WIDGETS\GaugeDialPro") `
  $dialTarget $frontManifest
Copy-RuntimeManifest "GaugeBarPro" (Join-Path $repoRoot "WIDGETS\GaugeBarPro") `
  $barTarget $frontManifest

if ($IncludeLegacy) {
  $legacyTarget = Get-ValidatedTarget "WIDGETS\GaugePro" "WIDGETS\GaugePro"
  Copy-RuntimeManifest "GaugePro legacy" $legacySource $legacyTarget $legacyManifest
} else {
  $existingLegacy = Join-Path $destinationPath "WIDGETS\GaugePro"
  if (Test-Path -LiteralPath $existingLegacy -PathType Container) {
    Write-Warning "GaugePro legacy retained unchanged: $existingLegacy. This SD will still show 3 widgets until the legacy folder is removed manually after model migration."
  }
}

# Post-copy ABI and completeness check. Keep this textual and boot-light: it
# catches mixed/partial payloads without executing LVGL-dependent chunks.
$required = @(
  (Join-Path $coreTarget "app.lua"),
  (Join-Path $dialTarget "main.lua"),
  (Join-Path $barTarget "main.lua")
)
foreach ($file in $required) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    throw "post-copy verification missing: $file"
  }
  if (-not (Select-String -LiteralPath $file -SimpleMatch "CORE_API = 1" -Quiet)) {
    throw "post-copy verification found incompatible or missing coreApi=1: $file"
  }
}

Write-Host "Gauge split install verified: GaugeCore API 1 + GaugeDialPro + GaugeBarPro"
if ($IncludeLegacy) {
  Write-Host "Transition package: 3 visible widgets (including GaugePro legacy)"
} else {
  Write-Host "New frontends installed: GaugeDialPro and GaugeBarPro"
}
