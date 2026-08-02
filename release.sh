#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if argument provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <patch|minor|major>"
    print_info "Examples:"
    print_info "  $0 patch  # 0.0.20-beta → 0.0.21-beta"
    print_info "  $0 minor  # 0.0.20-beta → 0.1.0-beta"
    print_info "  $0 major  # 0.0.20-beta → 1.0.0-beta"
    exit 1
fi

BUMP_TYPE=$1

# Validate bump type
if [[ ! "$BUMP_TYPE" =~ ^(patch|minor|major)$ ]]; then
    print_error "Invalid bump type: $BUMP_TYPE"
    print_error "Must be one of: patch, minor, major"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository"
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    print_warn "You have uncommitted changes. Please commit or stash them first."
    git status --short
    exit 1
fi

# Extract current version from mix.exs
CURRENT_VERSION=$(grep -o 'version: "[^"]*"' mix.exs | sed 's/version: "\(.*\)"/\1/')

if [ -z "$CURRENT_VERSION" ]; then
    print_error "Could not extract version from mix.exs"
    exit 1
fi

print_info "Current version: $CURRENT_VERSION"

# Parse version components (handle both X.Y.Z and X.Y.Z-suffix formats)
if [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)?$ ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    SUFFIX="${BASH_REMATCH[4]}"
else
    print_error "Version format not recognized: $CURRENT_VERSION"
    print_error "Expected format: X.Y.Z or X.Y.Z-suffix"
    exit 1
fi

# Calculate new version
case $BUMP_TYPE in
    "patch")
        NEW_PATCH=$((PATCH + 1))
        NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}${SUFFIX}"
        ;;
    "minor")
        NEW_MINOR=$((MINOR + 1))
        NEW_VERSION="${MAJOR}.${NEW_MINOR}.0${SUFFIX}"
        ;;
    "major")
        NEW_MAJOR=$((MAJOR + 1))
        NEW_VERSION="${NEW_MAJOR}.0.0${SUFFIX}"
        ;;
esac

print_info "New version: $NEW_VERSION"

# Gate the release on the same checks CI runs
print_info "Running checks..."
mix format --check-formatted
mix compile --warnings-as-errors
mix test

# Update version in mix.exs
sed -i.bak "s/version: \"${CURRENT_VERSION}\"/version: \"${NEW_VERSION}\"/" mix.exs

# Check if the replacement was successful
if ! grep -q "version: \"${NEW_VERSION}\"" mix.exs; then
    print_error "Failed to update version in mix.exs"
    # Restore backup
    mv mix.exs.bak mix.exs
    exit 1
fi

# Remove backup file
rm mix.exs.bak

print_info "Updated mix.exs with new version"

# Build release binaries before anything is published
print_info "Building release binaries..."
MIX_ENV=prod mix release

for f in pled_linux_arm pled_linux_x86 pled_macos_arm pled_macos_x86 pled_windows.exe; do
    if [ ! -f "burrito_out/$f" ]; then
        print_error "Build did not produce burrito_out/$f"
        git checkout mix.exs
        exit 1
    fi
done

# Package binaries into archives (so downloaded file is always "pled")
print_info "Packaging binaries..."
ARCHIVE_DIR="burrito_out/archives"
rm -rf "$ARCHIVE_DIR"
mkdir -p "$ARCHIVE_DIR"

# Unix platforms → tar.gz
for f in pled_linux_arm pled_linux_x86 pled_macos_arm pled_macos_x86; do
    if [ -f "burrito_out/$f" ]; then
        name="${f/pled_/pled-}"
        name="${name//_/-}"
        cp "burrito_out/$f" "burrito_out/pled"
        chmod +x "burrito_out/pled"
        tar czf "${ARCHIVE_DIR}/${name}.tar.gz" -C burrito_out pled
        rm "burrito_out/pled"
        print_info "  Created ${name}.tar.gz"
    else
        print_warn "  Skipping $f (not found)"
    fi
done

# Windows → zip
if [ -f "burrito_out/pled_windows.exe" ]; then
    cp "burrito_out/pled_windows.exe" "burrito_out/pled.exe"
    (cd burrito_out && zip -q "archives/pled-windows.zip" pled.exe && rm pled.exe)
    print_info "  Created pled-windows.zip"
else
    print_warn "  Skipping pled_windows.exe (not found)"
fi

# Everything built: now publish the version bump
git add mix.exs
COMMIT_MSG="Bump version from ${CURRENT_VERSION} to ${NEW_VERSION}"
git commit -m "$COMMIT_MSG"
git tag "v${NEW_VERSION}"

print_info "Created commit: $COMMIT_MSG"
print_info "Created tag: v${NEW_VERSION}"

print_info "Pushing to origin..."
git push origin main
git push origin "v${NEW_VERSION}"

# Create GitHub release and upload archives
print_info "Creating GitHub release v${NEW_VERSION}..."
gh release create "v${NEW_VERSION}" \
    ${ARCHIVE_DIR}/pled-*.tar.gz \
    ${ARCHIVE_DIR}/pled-*.zip \
    --title "v${NEW_VERSION}" \
    --prerelease \
    --generate-notes

print_info "Release v${NEW_VERSION} published with binaries!"
print_info "  https://github.com/RicoTrevisan/pled/releases/tag/v${NEW_VERSION}"