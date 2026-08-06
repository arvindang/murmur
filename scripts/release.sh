#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/release.sh <version> [--publish]

Builds, signs, notarizes, and packages Murmur. With --publish, it also commits
the release metadata and DMG, tags and pushes the release, creates the GitHub
Release, and verifies the GitHub Pages download.

The repository must be clean and on main. Configure notarization using one of
the authentication methods documented in scripts/notarize.sh.
USAGE
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    exit 64
fi

VERSION="$1"
PUBLISH=false
if [ "${2:-}" = "--publish" ]; then
    PUBLISH=true
elif [ -n "${2:-}" ]; then
    usage
    exit 64
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must use semantic versioning (for example, 0.2.0)."
    exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TAG="v$VERSION"
DMG_NAME="Murmur-$VERSION.dmg"
BUILD_DMG="$PROJECT_DIR/build/$DMG_NAME"
SITE_DMG="$PROJECT_DIR/docs/$DMG_NAME"
BACKUP_DIR=""
RELEASE_COMMITTED=false

restore_release_files() {
    if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ] || [ "$RELEASE_COMMITTED" = true ]; then
        return
    fi

    cp "$BACKUP_DIR/project.yml" "$PROJECT_DIR/project.yml"
    cp "$BACKUP_DIR/project.pbxproj" "$PROJECT_DIR/Murmur.xcodeproj/project.pbxproj"
    cp "$BACKUP_DIR/CHANGELOG.md" "$PROJECT_DIR/CHANGELOG.md"
    cp "$BACKUP_DIR/index.html" "$PROJECT_DIR/docs/index.html"
    rm -f "$SITE_DMG"
}

cleanup_on_exit() {
    status="$?"
    trap - EXIT
    if [ "$status" -ne 0 ]; then
        restore_release_files
    fi
    if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR"
    fi
    exit "$status"
}

trap cleanup_on_exit EXIT

cd "$PROJECT_DIR"

for command in git gh rg ruby xcodegen xcodebuild; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: Required command is not installed: $command"
        exit 1
    fi
done

gh auth status >/dev/null

if [ "$(git branch --show-current)" != "main" ]; then
    echo "Error: Releases must be run from main."
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Commit or stash existing changes before starting a release."
    exit 1
fi

git fetch origin main --tags

if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "Error: Local main must exactly match origin/main before releasing."
    exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1 || gh release view "$TAG" >/dev/null 2>&1; then
    echo "Error: $TAG already exists."
    exit 1
fi

if [ -e "$SITE_DMG" ]; then
    echo "Error: Release asset already exists: $SITE_DMG"
    exit 1
fi

BACKUP_DIR="$(mktemp -d)"
cp project.yml "$BACKUP_DIR/project.yml"
cp Murmur.xcodeproj/project.pbxproj "$BACKUP_DIR/project.pbxproj"
cp CHANGELOG.md "$BACKUP_DIR/CHANGELOG.md"
cp docs/index.html "$BACKUP_DIR/index.html"

"$SCRIPT_DIR/update-release-metadata.rb" "$VERSION"
xcodegen generate

echo "==> Running tests..."
xcodebuild -quiet \
    -project Murmur.xcodeproj \
    -scheme Murmur \
    -destination "platform=macOS" \
    CODE_SIGNING_ALLOWED=NO \
    test

echo "==> Building signed and notarized DMG..."
"$SCRIPT_DIR/notarize.sh"

if [ ! -f "$BUILD_DMG" ]; then
    echo "Error: Expected DMG was not created: $BUILD_DMG"
    exit 1
fi

cp "$BUILD_DMG" "$SITE_DMG"
hdiutil verify "$SITE_DMG"

if [ "$PUBLISH" != true ]; then
    restore_release_files
    echo "Release candidate ready at $BUILD_DMG"
    echo "The repository was restored; rerun with --publish when ready."
    exit 0
fi

git add \
    CHANGELOG.md \
    project.yml \
    Murmur.xcodeproj/project.pbxproj \
    docs/index.html \
    "$SITE_DMG"
git commit -m "Release $TAG"
RELEASE_COMMITTED=true
git tag -a "$TAG" -m "Murmur $TAG"

echo "==> Publishing source and tag..."
git push --atomic origin main "$TAG"

echo "==> Creating GitHub Release..."
gh release create "$TAG" "$SITE_DMG" \
    --repo arvindang/murmur \
    --title "Murmur $TAG" \
    --generate-notes \
    --latest \
    --verify-tag

RELEASE_COMMIT="$(git rev-parse HEAD)"
echo "==> Waiting for the Pages deployment..."
RUN_ID=""
for _ in {1..30}; do
    RUN_ID="$(gh run list \
        --repo arvindang/murmur \
        --workflow deploy-pages.yml \
        --branch main \
        --limit 10 \
        --json databaseId,headSha \
        --jq ".[] | select(.headSha == \"$RELEASE_COMMIT\") | .databaseId" \
        | head -1)"
    if [ -n "$RUN_ID" ]; then
        break
    fi
    sleep 2
done

if [ -z "$RUN_ID" ]; then
    echo "Error: Could not find the Pages workflow for $RELEASE_COMMIT."
    exit 1
fi

gh run watch "$RUN_ID" --repo arvindang/murmur --exit-status

EXPECTED_LINK="Murmur-$VERSION.dmg"
for _ in {1..30}; do
    if curl --fail --silent --location https://arv.in/murmur/ | rg -q "$EXPECTED_LINK"; then
        echo "Published Murmur $TAG successfully."
        echo "Release: https://github.com/arvindang/murmur/releases/tag/$TAG"
        echo "Website: https://arv.in/murmur/"
        exit 0
    fi
    sleep 2
done

echo "Error: Pages deployed, but the live site does not link to $EXPECTED_LINK."
exit 1
