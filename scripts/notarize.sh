#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Murmur — Build, Sign, Notarize, and Package for Distribution
# =============================================================================
#
# Required env vars:
#   TEAM_ID              — Apple Developer Team ID
#   APPLE_ID             — Apple ID email for notarytool
#   APP_SPECIFIC_PASSWORD — App-specific password for notarytool
#
# Optional:
#   KEYCHAIN_PROFILE     — If set, uses stored notarytool credentials instead
#
# Usage:
#   export TEAM_ID="XXXXXXXXXX"
#   export APPLE_ID="you@example.com"
#   export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   ./scripts/notarize.sh
# =============================================================================

APP_NAME="Murmur"
BUNDLE_ID="com.murmur.app"
SCHEME="Murmur"
CONFIG="Release"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

if [ -z "${KEYCHAIN_PROFILE:-}" ]; then
    if [ -z "${TEAM_ID:-}" ] || [ -z "${APPLE_ID:-}" ] || [ -z "${APP_SPECIFIC_PASSWORD:-}" ]; then
        echo "Error: Set TEAM_ID, APPLE_ID, and APP_SPECIFIC_PASSWORD (or KEYCHAIN_PROFILE)."
        exit 1
    fi
fi

TEAM_ID="${TEAM_ID:?}"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Step 1: Generate Xcode project
# ---------------------------------------------------------------------------

echo "==> Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

# ---------------------------------------------------------------------------
# Step 2: Resolve SPM dependencies
# ---------------------------------------------------------------------------

echo "==> Resolving package dependencies..."
xcodebuild -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -resolvePackageDependencies

# ---------------------------------------------------------------------------
# Step 3: Archive
# ---------------------------------------------------------------------------

echo "==> Archiving ($CONFIG)..."
xcodebuild archive \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# ---------------------------------------------------------------------------
# Step 4: Export archive (Developer ID)
# ---------------------------------------------------------------------------

echo "==> Exporting archive..."

EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Export failed — $APP_PATH not found."
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 5: Verify code signature
# ---------------------------------------------------------------------------

echo "==> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# ---------------------------------------------------------------------------
# Step 6: Create .dmg
# ---------------------------------------------------------------------------

echo "==> Creating .dmg..."

DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

# ---------------------------------------------------------------------------
# Step 7: Notarize
# ---------------------------------------------------------------------------

echo "==> Submitting for notarization..."

if [ -n "${KEYCHAIN_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait
else
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --wait
fi

# ---------------------------------------------------------------------------
# Step 8: Staple
# ---------------------------------------------------------------------------

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# ---------------------------------------------------------------------------
# Step 9: Validate
# ---------------------------------------------------------------------------

echo "==> Validating..."
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

FILE_SIZE=$(du -h "$DMG_PATH" | cut -f1)
SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

echo ""
echo "=========================================="
echo "  Build complete!"
echo "  DMG:    $DMG_PATH"
echo "  Size:   $FILE_SIZE"
echo "  SHA256: $SHA256"
echo "=========================================="
