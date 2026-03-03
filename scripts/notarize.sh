#!/usr/bin/env bash
#
# notarize.sh -- Archive, sign, notarize, and staple SwiftEditor.app
#
# Usage:
#   ./scripts/notarize.sh [--team-id TEAM_ID] [--apple-id EMAIL] [--password APP_SPECIFIC_PASSWORD]
#
# Environment variables (alternative to flags):
#   TEAM_ID               -- Apple Developer Team ID
#   APPLE_ID              -- Apple ID email for notarytool
#   APP_SPECIFIC_PASSWORD -- App-specific password (or @keychain: reference)
#
# Prerequisites:
#   - Xcode 15+ with command-line tools
#   - Valid Developer ID Application certificate in keychain
#   - App-specific password stored via: xcrun notarytool store-credentials
#
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────
SCHEME="SwiftEditorApp"
BUNDLE_ID="com.swifteditor.app"
ARCHIVE_PATH="build/SwiftEditor.xcarchive"
EXPORT_PATH="build/export"
APP_NAME="SwiftEditor.app"
DMG_NAME="SwiftEditor.dmg"

# ── Parse arguments ───────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --team-id)      TEAM_ID="$2"; shift 2 ;;
        --apple-id)     APPLE_ID="$2"; shift 2 ;;
        --password)     APP_SPECIFIC_PASSWORD="$2"; shift 2 ;;
        *)              echo "Unknown option: $1"; exit 1 ;;
    esac
done

TEAM_ID="${TEAM_ID:?Error: set TEAM_ID via --team-id or environment}"
APPLE_ID="${APPLE_ID:?Error: set APPLE_ID via --apple-id or environment}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:?Error: set APP_SPECIFIC_PASSWORD via --password or environment}"

# ── Helpers ───────────────────────────────────────────────────────────
step() { echo ""; echo "==> $1"; }
fail() { echo "ERROR: $1" >&2; exit 1; }

# ── 1. Archive ────────────────────────────────────────────────────────
step "Archiving ${SCHEME}..."
xcodebuild archive \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    | tail -1

[[ -d "$ARCHIVE_PATH" ]] || fail "Archive not found at $ARCHIVE_PATH"

# ── 2. Export ─────────────────────────────────────────────────────────
step "Exporting application..."

EXPORT_OPTIONS_PLIST=$(mktemp /tmp/exportOptions.XXXXXX.plist)
cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    -exportPath "$EXPORT_PATH" \
    | tail -1

rm -f "$EXPORT_OPTIONS_PLIST"

APP_PATH="${EXPORT_PATH}/${APP_NAME}"
[[ -d "$APP_PATH" ]] || fail "Exported app not found at $APP_PATH"

# ── 3. Notarize ──────────────────────────────────────────────────────
step "Creating ZIP for notarization..."
ZIP_PATH="build/SwiftEditor.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

step "Submitting to Apple notary service..."
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait

# ── 4. Staple ─────────────────────────────────────────────────────────
step "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

# ── 5. Verify ─────────────────────────────────────────────────────────
step "Verifying signature and notarization..."
codesign --verify --deep --strict "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

# ── 6. Create DMG (optional) ─────────────────────────────────────────
step "Creating distributable DMG..."
hdiutil create -volname "SwiftEditor" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "build/${DMG_NAME}"

# Notarize the DMG as well
xcrun notarytool submit "build/${DMG_NAME}" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait

xcrun stapler staple "build/${DMG_NAME}"

step "Done! Distributable DMG at build/${DMG_NAME}"
