#!/bin/sh
# UTV build script — no Gradle, just the Android SDK build-tools.
#
#   ./build.sh            build release APK and install it on the connected device
#   ./build.sh noinstall  build only
#
# Needs: JDK 17+ and Android SDK (build-tools 35, platform android-35).
#   SDK path:  $ANDROID_HOME, else ~/.local/sdk
#   Signing:   keystore/release.jks + keystore/release.properties (created on first run, never committed)
# Output: release/UTV-v<version>.apk
set -e
cd "$(dirname "$0")"

VERSION_NAME=1.0
VERSION_CODE=1
MIN_SDK=21
TARGET_SDK=35

SDK=${ANDROID_HOME:-$HOME/.local/sdk}
[ -n "$JAVA_HOME" ] || JAVA_HOME=$(ls -d "$SDK"/jdk-* 2>/dev/null | head -1)
[ -n "$JAVA_HOME" ] || JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
BT=$SDK/build-tools/35.0.0
JAR=$SDK/platforms/android-$TARGET_SDK/android.jar
KS=keystore/release.jks
KP=keystore/release.properties

rm -rf build && mkdir -p build/classes release

# 1. resources + manifest
"$BT/aapt2" compile --dir res -o build/res.zip
"$BT/aapt2" link -o build/unsigned.apk -I "$JAR" --manifest AndroidManifest.xml \
  --min-sdk-version $MIN_SDK --target-sdk-version $TARGET_SDK \
  --version-code $VERSION_CODE --version-name $VERSION_NAME build/res.zip

# 2. code -> dex
"$JAVA_HOME/bin/javac" -nowarn --release 11 -cp "$JAR" -d build/classes $(find src -name '*.java')
"$BT/d8" --release --min-api $MIN_SDK --lib "$JAR" --output build $(find build/classes -name '*.class')
(cd build && zip -q -9 unsigned.apk classes.dex)

# 3. align + sign (v1+v2+v3, so it installs on Android 5.0 through current)
"$BT/zipalign" -f -p 4 build/unsigned.apk build/aligned.apk
if [ ! -f "$KS" ]; then
  mkdir -p keystore
  PASS=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
  "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KS" -storetype PKCS12 -storepass "$PASS" \
    -alias utv -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=UTV, O=localhost969" >/dev/null 2>&1
  printf 'storePassword=%s\n' "$PASS" > "$KP"
  chmod 600 "$KS" "$KP"
  echo "Created new release key in keystore/ - back it up; updates need the same key."
fi
PASS=$(sed -n 's/^storePassword=//p' "$KP")
OUT=release/UTV-v$VERSION_NAME.apk
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$PASS" --ks-key-alias utv \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --v4-signing-enabled false \
  --out "$OUT" build/aligned.apk
"$BT/apksigner" verify --min-sdk-version $MIN_SDK "$OUT"
ls -l "$OUT"

[ "$1" = noinstall ] || { adb install -r "$OUT" && adb shell am start -n utv.app/utv.Main >/dev/null; }
