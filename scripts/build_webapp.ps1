# Builds the customer web app (open from a WhatsApp link, no install) and copies it to backend/webapp,
# which the server publishes at /app/. Run after app changes, then commit and push:
#   powershell -ExecutionPolicy Bypass -File scripts/build_webapp.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$mobile = Join-Path $root "mobile"
$out = Join-Path $root "backend\webapp"

Push-Location $mobile
& C:\flutter-sdk\bin\flutter.bat build web --release --base-href /app/ --dart-define=API_BASE_URL=https://micro-bargain-api.onrender.com/api/v1
if ($LASTEXITCODE -ne 0) { throw "web build failed" }
Pop-Location

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
# canvaskit (the graphics engine) is loaded from Google's CDN, so the local copy is not shipped.
robocopy (Join-Path $mobile "build\web") $out /E /XD canvaskit /NFL /NDL /NJH /NJS | Out-Null
Write-Host ("Web app ready in backend/webapp ({0:N1} MB)" -f ((Get-ChildItem $out -Recurse | Measure-Object Length -Sum).Sum / 1MB)) -ForegroundColor Green
