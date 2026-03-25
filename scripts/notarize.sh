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

# Read version from project.yml MARKETING_VERSION
VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    echo "Error: Could not read MARKETING_VERSION from project.yml"
    exit 1
fi
echo "==> Version: $VERSION"

ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/$APP_NAME-${VERSION}.dmg"

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
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    SKIP_INSTALL=NO

# ---------------------------------------------------------------------------
# Step 4: Extract .app from archive
# ---------------------------------------------------------------------------

echo "==> Extracting .app from archive..."

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Archive does not contain $APP_NAME.app"
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
# Step 7: Sign the DMG
# ---------------------------------------------------------------------------

echo "==> Signing .dmg..."
codesign --force --sign "Developer ID Application: ARVIN DANG ($TEAM_ID)" "$DMG_PATH"

# ---------------------------------------------------------------------------
# Step 8: Notarize
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
# Step 9: Staple
# ---------------------------------------------------------------------------

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# ---------------------------------------------------------------------------
# Step 10: Validate
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
