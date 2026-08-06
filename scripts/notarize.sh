#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Murmur — Build, Sign, Notarize, and Package for Distribution
# =============================================================================
#
# Notarization authentication (choose one):
#   KEYCHAIN_PROFILE                 — Recommended; profile created by
#                                      `xcrun notarytool store-credentials`
#   APP_STORE_CONNECT_API_KEY_PATH   — App Store Connect .p8 private key
#   APP_STORE_CONNECT_KEY_ID         — App Store Connect key ID
#   APP_STORE_CONNECT_ISSUER_ID      — Required for Team API keys
#   APPLE_ID                         — Apple ID email
#   APP_SPECIFIC_PASSWORD            — App-specific password
#
# Optional:
#   TEAM_ID — Apple Developer Team ID (defaults to Murmur's distribution team)
#
# Usage:
#   KEYCHAIN_PROFILE="murmur-notary" ./scripts/notarize.sh
# =============================================================================

APP_NAME="Murmur"
BUNDLE_ID="com.murmur.app"
SCHEME="Murmur"
CONFIG="Release"
TEAM_ID="${TEAM_ID:-R9H5W4SA9U}"

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

NOTARY_AUTH_ARGS=()
if [ -n "${KEYCHAIN_PROFILE:-}" ]; then
    NOTARY_AUTH_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
elif [ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ] && [ -n "${APP_STORE_CONNECT_KEY_ID:-}" ]; then
    if [ ! -f "$APP_STORE_CONNECT_API_KEY_PATH" ]; then
        echo "Error: App Store Connect API key not found: $APP_STORE_CONNECT_API_KEY_PATH"
        exit 1
    fi
    NOTARY_AUTH_ARGS=(
        --key "$APP_STORE_CONNECT_API_KEY_PATH"
        --key-id "$APP_STORE_CONNECT_KEY_ID"
    )
    if [ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
        NOTARY_AUTH_ARGS+=(--issuer "$APP_STORE_CONNECT_ISSUER_ID")
    fi
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    NOTARY_AUTH_ARGS=(
        --apple-id "$APPLE_ID"
        --team-id "$TEAM_ID"
        --password "$APP_SPECIFIC_PASSWORD"
    )
else
    echo "Error: Configure notarization authentication."
    echo "Recommended one-time setup:"
    echo "  xcrun notarytool store-credentials murmur-notary"
    echo "    --apple-id you@example.com --team-id $TEAM_ID"
    echo "Then run with KEYCHAIN_PROFILE=murmur-notary."
    exit 1
fi

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

DMG_RW_PATH="$BUILD_DIR/$APP_NAME-rw.asif"
DMG_MOUNT_PATH="$BUILD_DIR/dmg-mount"
DMG_DEVICE=""

cleanup_mounted_image() {
    if [ -d "$DMG_MOUNT_PATH" ] && mount | grep -Fq "on $DMG_MOUNT_PATH "; then
        diskutil unmount force "$DMG_MOUNT_PATH" >/dev/null 2>&1 || true
    fi
    if [ -n "$DMG_DEVICE" ]; then
        diskutil eject "$DMG_DEVICE" >/dev/null 2>&1 || true
    fi
}
trap cleanup_mounted_image EXIT

APP_SIZE_KIB=$(du -sk "$APP_PATH" | awk '{print $1}')
DMG_SIZE_MIB=$(( (APP_SIZE_KIB + 1023) / 1024 + 20 ))

diskutil image create blank \
    --size "${DMG_SIZE_MIB}MiB" \
    --volumeName "$APP_NAME" \
    --fs APFS \
    "$DMG_RW_PATH"

mkdir "$DMG_MOUNT_PATH"
ATTACH_OUTPUT=$(diskutil image attach \
    --mountOptions nobrowse \
    --mountPoint "$DMG_MOUNT_PATH" \
    "$DMG_RW_PATH")
echo "$ATTACH_OUTPUT"
DMG_DEVICE=$(echo "$ATTACH_OUTPUT" | awk 'NR == 1 {print $1}')

touch "$DMG_MOUNT_PATH/.metadata_never_index"
ditto "$APP_PATH" "$DMG_MOUNT_PATH/$APP_NAME.app"
ln -s /Applications "$DMG_MOUNT_PATH/Applications"
sync

# Xcode's CoreSimulator service may inspect a newly mounted app bundle and
# dissent from a normal unmount. This is a private, fully synced temporary
# image, so force-unmounting only this mount point is safe and deterministic.
diskutil unmount force "$DMG_MOUNT_PATH"
diskutil eject "$DMG_DEVICE"
DMG_DEVICE=""

diskutil image create from \
    --format UDZO \
    "$DMG_RW_PATH" \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"

rm -f "$DMG_RW_PATH"
rmdir "$DMG_MOUNT_PATH"
trap - EXIT

# ---------------------------------------------------------------------------
# Step 7: Sign the DMG
# ---------------------------------------------------------------------------

echo "==> Signing .dmg..."
codesign --force --sign "Developer ID Application: ARVIN DANG ($TEAM_ID)" "$DMG_PATH"

# ---------------------------------------------------------------------------
# Step 8: Notarize
# ---------------------------------------------------------------------------

echo "==> Submitting for notarization..."

xcrun notarytool submit "$DMG_PATH" \
    "${NOTARY_AUTH_ARGS[@]}" \
    --wait \
    --timeout 30m

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
