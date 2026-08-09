# Copy the GaugePro runtime payload to an SD-card folder (radio or simulator).
#
#   pwsh dev/sync-sd.ps1                       # -> D:\SD\WIDGETS\GaugePro
#   pwsh dev/sync-sd.ps1 -Destination E:\      # -> E:\WIDGETS\GaugePro
#
# Only the runtime modules are copied: tests/ and dev/ have no business on a
# radio, and stale copies there make it hard to tell which version is running.

param(
  [string]$Destination = "D:\SD"
)

$source = Split-Path -Parent $PSScriptRoot
$target = Join-Path $Destination "WIDGETS\GaugePro"

$runtime = @(
  "main.lua", "app.lua", "options.lua", "theme.lua", "geometry.lua",
  "ranges.lua", "presets.lua", "format.lua", "smoothing.lua",
  "telemetry.lua", "layout.lua", "renderer.lua", "bar.lua", "alerts.lua"
)

New-Item -ItemType Directory -Force $target | Out-Null

$copied = 0
foreach ($f in $runtime) {
  $src = Join-Path $source $f
  if (-not (Test-Path $src)) { throw "missing runtime module: $f" }
  Copy-Item $src (Join-Path $target $f) -Force
  $copied++
}
foreach ($doc in @("DOCS.md", "README.md")) {
  $src = Join-Path $source $doc
  if (Test-Path $src) { Copy-Item $src (Join-Path $target $doc) -Force }
}

$kb = [math]::Round(((Get-ChildItem $target -File | Measure-Object Length -Sum).Sum / 1KB), 1)
Write-Host "GaugePro -> $target  ($copied modules, $kb KB)"
