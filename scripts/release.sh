#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/release.sh <version> [--publish|--verify]

Builds, signs, notarizes, and packages Murmur. With --publish, it also commits
the release metadata and DMG, tags and pushes the release, creates the GitHub
Release, and verifies the GitHub Pages download. With --verify, it resumes only
the remote release and website checks for an already-published version.

Publishing requires a clean repository on main. Configure notarization using
one of the authentication methods documented in scripts/notarize.sh.
USAGE
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    exit 64
fi

VERSION="$1"
PUBLISH=false
VERIFY_ONLY=false
if [ "${2:-}" = "--publish" ]; then
    PUBLISH=true
elif [ "${2:-}" = "--verify" ]; then
    VERIFY_ONLY=true
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
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-arvindang/murmur}"
MURMUR_SITE_URL="${MURMUR_SITE_URL:-https://arv.in/murmur/}"
PAGES_WAIT_SECONDS="${PAGES_WAIT_SECONDS:-1800}"
PAGES_POLL_SECONDS="${PAGES_POLL_SECONDS:-5}"
BACKUP_DIR=""
RELEASE_COMMITTED=false

wait_for_pages_build() {
    local release_commit="$1"
    local expected_link="$2"
    local build_type deadline build_info build_status build_url build_error run_id

    build_type="$(gh api "repos/$GITHUB_REPOSITORY/pages" --jq .build_type)"
    deadline=$((SECONDS + PAGES_WAIT_SECONDS))

    if [ "$build_type" = "legacy" ]; then
        echo "==> Waiting for the branch-based Pages build..."
        while [ "$SECONDS" -lt "$deadline" ]; do
            if curl --fail --silent --location "$MURMUR_SITE_URL" | rg -q "$expected_link"; then
                echo "The live site already contains $expected_link."
                return 0
            fi

            build_info="$(gh api "repos/$GITHUB_REPOSITORY/pages/builds?per_page=30" \
                --jq ".[] | select(.commit == \"$release_commit\") | [.status, .url, (.error.message // \"\")] | @tsv" \
                | head -1)"

            if [ -n "$build_info" ]; then
                IFS=$'\t' read -r build_status build_url build_error <<< "$build_info"
                case "$build_status" in
                    built)
                        echo "Pages build completed: $build_url"
                        return 0
                        ;;
                    errored)
                        echo "Pages build is currently errored: ${build_error:-$build_url}"
                        ;;
                esac
            fi

            sleep "$PAGES_POLL_SECONDS"
        done

        echo "Error: Timed out waiting for the Pages build for $release_commit."
        return 1
    fi

    echo "==> Waiting for the workflow-based Pages deployment..."
    run_id=""
    while [ "$SECONDS" -lt "$deadline" ]; do
        if curl --fail --silent --location "$MURMUR_SITE_URL" | rg -q "$expected_link"; then
            echo "The live site already contains $expected_link."
            return 0
        fi

        run_id="$(gh run list \
            --repo "$GITHUB_REPOSITORY" \
            --branch main \
            --limit 50 \
            --json databaseId,headSha,workflowName \
            --jq ".[] | select(.headSha == \"$release_commit\" and (.workflowName | ascii_downcase | contains(\"pages\"))) | .databaseId" \
            | head -1)"
        if [ -n "$run_id" ]; then
            gh run watch "$run_id" --repo "$GITHUB_REPOSITORY" --exit-status
            return 0
        fi
        sleep "$PAGES_POLL_SECONDS"
    done

    echo "Error: Timed out waiting for the Pages workflow for $release_commit."
    return 1
}

wait_for_live_site() {
    local expected_link="$1"
    local deadline=$((SECONDS + PAGES_WAIT_SECONDS))

    echo "==> Verifying the live download link..."
    while [ "$SECONDS" -lt "$deadline" ]; do
        if curl --fail --silent --location "$MURMUR_SITE_URL" | rg -q "$expected_link"; then
            return 0
        fi
        sleep "$PAGES_POLL_SECONDS"
    done

    echo "Error: Pages completed, but the live site does not link to $expected_link."
    return 1
}

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

for command in git gh rg curl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: Required command is not installed: $command"
        exit 1
    fi
done

if [ "$VERIFY_ONLY" != true ]; then
    for command in ruby xcodegen xcodebuild; do
        if ! command -v "$command" >/dev/null 2>&1; then
            echo "Error: Required command is not installed: $command"
            exit 1
        fi
    done
fi

gh auth status >/dev/null

git fetch origin main --tags

if [ "$VERIFY_ONLY" = true ]; then
    if ! gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
        echo "Error: GitHub Release $TAG does not exist."
        exit 1
    fi
    if ! git rev-parse "$TAG^{commit}" >/dev/null 2>&1; then
        echo "Error: Git tag $TAG does not resolve to a commit."
        exit 1
    fi

    RELEASE_COMMIT="$(git rev-parse "$TAG^{commit}")"
    EXPECTED_LINK="Murmur-$VERSION.dmg"
    wait_for_pages_build "$RELEASE_COMMIT" "$EXPECTED_LINK"
    wait_for_live_site "$EXPECTED_LINK"
    echo "Published Murmur $TAG successfully."
    echo "Release: https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG"
    echo "Website: $MURMUR_SITE_URL"
    exit 0
fi

if [ "$(git branch --show-current)" != "main" ]; then
    echo "Error: Releases must be run from main."
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Commit or stash existing changes before starting a release."
    exit 1
fi

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
    --repo "$GITHUB_REPOSITORY" \
    --title "Murmur $TAG" \
    --generate-notes \
    --latest \
    --verify-tag

RELEASE_COMMIT="$(git rev-parse HEAD)"
EXPECTED_LINK="Murmur-$VERSION.dmg"
wait_for_pages_build "$RELEASE_COMMIT" "$EXPECTED_LINK"
wait_for_live_site "$EXPECTED_LINK"
echo "Published Murmur $TAG successfully."
echo "Release: https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG"
echo "Website: $MURMUR_SITE_URL"
