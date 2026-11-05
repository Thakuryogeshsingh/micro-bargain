# Ek command se naya app version banaiye:
#   powershell -ExecutionPolicy Bypass -File update_app.ps1
#
# 1. Version number apne aap badhata hai (mobile/pubspec.yaml)
# 2. WSL mein APK build karta hai (live server ke liye)
# 3. APK ko Desktop par MicroBargain_<version>.apk naam se rakhta hai
# 4. Code GitHub par push karta hai
# 5. Admin panel mein kya bharna hai, wo bata deta hai

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$pubspec = Join-Path $root "mobile\pubspec.yaml"

# --- 1. version badhao: 0.2.1+3  ->  0.2.2+4
$text = Get-Content $pubspec -Raw -Encoding UTF8
if ($text -notmatch "version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)") { throw "pubspec.yaml mein version nahi mila" }
$name = "$($Matches[1]).$($Matches[2]).$([int]$Matches[3] + 1)"
$build = [int]$Matches[4] + 1
$text = $text -replace "version:\s*\d+\.\d+\.\d+\+\d+", "version: $name+$build"
[IO.File]::WriteAllText($pubspec, $text, (New-Object Text.UTF8Encoding $false))
Write-Host "Naya version: $name (build $build)" -ForegroundColor Cyan

# --- 2. APK build (WSL)
Write-Host "APK ban raha hai... (5-10 minute)" -ForegroundColor Cyan
wsl -d Ubuntu -- bash "/mnt/c/Users/User_PC/Desktop/Local Vendors/scripts/build_apk.sh"
if ($LASTEXITCODE -ne 0) { throw "APK build fail hua. Upar ka error dekhein." }

# --- 3. Desktop par copy
$apk = Join-Path ([Environment]::GetFolderPath("Desktop")) "MicroBargain_$name.apk"
Move-Item -Force (Join-Path $root "MicroBargain.apk") $apk
Write-Host "APK taiyar: $apk" -ForegroundColor Green

# --- 4. GitHub par push
git -C $root add mobile/pubspec.yaml
git -C $root commit -q -m "App version $name ($build)"
git -C $root push -q
Write-Host "Code GitHub par push ho gaya" -ForegroundColor Green

# --- 5. aage kya karna hai
Write-Host ""
Write-Host "Ab sabke phone par update bhejne ke liye:" -ForegroundColor Yellow
Write-Host "  1. $apk ko Google Drive par upload karein -> Share -> 'Anyone with the link'"
Write-Host "  2. https://micro-bargain-api.onrender.com/admin/releases/apprelease/add/ kholein"
Write-Host "     Version code: $build     Version name: $name     APK URL: (Drive ka link)"
Write-Host "  3. Save karein - sabke app mein update ka popup aa jayega"
