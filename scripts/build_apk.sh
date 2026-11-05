#!/usr/bin/env bash
# Builds the release APK inside WSL (Gradle is much faster on the Linux disk than on /mnt/c).
# Usage: bash scripts/build_apk.sh [api-base-url]
set -e
API_URL="${1:-https://micro-bargain-api.onrender.com/api/v1}"
export ANDROID_HOME="$HOME/android-sdk"
SRC="$(cd "$(dirname "$0")/../mobile" && pwd)"
mkdir -p "$HOME/mb_mobile"
rsync -a --delete --exclude build --exclude .dart_tool "$SRC/" "$HOME/mb_mobile/"
cd "$HOME/mb_mobile"
"$HOME/flutter/bin/flutter" pub get >/dev/null
"$HOME/flutter/bin/flutter" build apk --release --dart-define=API_BASE_URL="$API_URL"
cp build/app/outputs/flutter-apk/app-release.apk "$SRC/../MicroBargain.apk"
echo "APK_READY"
