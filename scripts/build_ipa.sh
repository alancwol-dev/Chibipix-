#!/usr/bin/env bash
# Builds ChibiPix.ipa on a Mac with Xcode 16+.
#
#   ./scripts/build_ipa.sh                 # unsigned IPA (for re-signing with Sideloadly / AltStore)
#   TEAM_ID=ABCDE12345 ./scripts/build_ipa.sh   # signed development IPA for your registered devices
#
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/ChibiPix.xcarchive"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"

if [[ -n "${TEAM_ID:-}" ]]; then
  echo "▶︎ Archiving (signed, team $TEAM_ID)…"
  xcodebuild -project ChibiPix.xcodeproj -scheme ChibiPix -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates archive

  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>${EXPORT_METHOD:-debugging}</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$BUILD_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" -allowProvisioningUpdates
else
  echo "▶︎ Archiving (unsigned)…"
  xcodebuild -project ChibiPix.xcodeproj -scheme ChibiPix -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" archive
  mkdir -p "$BUILD_DIR/Payload"
  cp -R "$ARCHIVE/Products/Applications/ChibiPix.app" "$BUILD_DIR/Payload/"
  (cd "$BUILD_DIR" && zip -qry ChibiPix.ipa Payload)
fi

echo "✅ $(pwd)/$BUILD_DIR/ChibiPix.ipa"
