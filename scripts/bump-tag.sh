#!/bin/bash
set -euo pipefail

# Script to bump version tag and push to GitHub
# Usage: ./scripts/bump-tag.sh [major|minor|patch]
# Default increment type: patch

BUMP_TYPE="${1:-patch}"

# Validate bump type
if [[ ! "$BUMP_TYPE" =~ ^(major|minor|patch)$ ]]; then
    echo "ERROR: Invalid bump type '$BUMP_TYPE'. Must be major, minor, or patch."
    exit 1
fi

# Get the latest tag, or default to 0.0.0 if none exist
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")

# Remove 'v' prefix if present for parsing
CURRENT_VERSION="${LATEST_TAG#v}"

# Split version into parts
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Increment based on bump type
case "$BUMP_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
esac

NEW_TAG="${MAJOR}.${MINOR}.${PATCH}"

# Check if tag already exists
if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
    echo "ERROR: Tag '$NEW_TAG' already exists."
    exit 1
fi

# Create and push the tag
echo "Creating tag: $NEW_TAG (previous: $LATEST_TAG)"
git tag -a "$NEW_TAG" -m "Version $NEW_TAG"
git push origin "$NEW_TAG"

echo "✓ Tag '$NEW_TAG' created and pushed successfully"

# Wait for GitHub Actions workflow to update store-index.json
echo "Waiting for GitHub Actions workflow to complete..."
echo "Checking dist/store-index.json for tag '$NEW_TAG' (polling every 15s)..."

MAX_ATTEMPTS=120  # 120 * 15 = 1800 seconds = 30 minutes
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    
    # Fetch the latest version from GitHub
    if git fetch origin >/dev/null 2>&1; then
        # Extract the tag from the remote store-index.json
        REMOTE_TAG=$(git show origin/main:dist/store-index.json 2>/dev/null | grep -o '"tag"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        
        if [ "$REMOTE_TAG" = "$NEW_TAG" ]; then
            echo "✓ Store index updated with tag '$NEW_TAG'"
            echo "Pulling latest changes from GitHub..."
            git pull origin main
            echo "✓ Repository synced successfully"
            exit 0
        fi
    fi
    
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        echo "  [$ATTEMPT/$MAX_ATTEMPTS] Tag mismatch or not yet updated. Retrying in 15s..."
        sleep 15
    fi
done

echo "ERROR: Timeout waiting for store-index.json to be updated with tag '$NEW_TAG'"
exit 1
