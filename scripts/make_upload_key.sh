#!/usr/bin/env bash
# Creates the Play Store upload key and android/key.properties. Run once, then BACK UP the .jks file
# and the password somewhere safe: without them you cannot publish updates to the same app.
set -euo pipefail
cd "$(dirname "$0")/../mobile/android"
read -rsp "Choose a keystore password (min 6 chars): " PASS; echo
keytool -genkeypair -v -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" -dname "CN=Micro Bargain, O=Micro Bargain, L=Bharatpur, ST=Rajasthan, C=IN"
cat > key.properties <<PROPS
storeFile=../upload-keystore.jks
storePassword=$PASS
keyAlias=upload
keyPassword=$PASS
PROPS
echo "Done. Back up mobile/android/upload-keystore.jks and the password now."
