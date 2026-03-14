#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────
# Package the Managers' Agent Fleet into a distributable zip
#
# The zip extracts into a managers-agent-fleet/ subdirectory
# so users can run: unzip managers-agent-fleet.zip
#                   bash managers-agent-fleet/install.sh
#
# Usage: bash scripts/package.sh
# Output: managers-agent-fleet.zip (in project root)
# ─────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Clean previous build
rm -rf .package-tmp managers-agent-fleet.zip

# Create staging directory with the correct top-level name
STAGE=".package-tmp/managers-agent-fleet"
mkdir -p "$STAGE"

# Copy distributable files into the staging directory
cp install.sh "$STAGE/"
cp CLAUDE.md "$STAGE/"
cp CHANGELOG.md "$STAGE/"
cp README.md "$STAGE/"
cp prompt.md "$STAGE/"
cp sprout-logo-01.svg "$STAGE/"

# scripts/
mkdir -p "$STAGE/scripts"
cp scripts/sprout-bootstrap.sh "$STAGE/scripts/"
cp scripts/sprout-init.sh "$STAGE/scripts/"

# docs/
mkdir -p "$STAGE/docs"
cp docs/*.md "$STAGE/docs/"

# manual/
mkdir -p "$STAGE/manual"
cp manual/sprout-guide.html "$STAGE/manual/"

# .claude/ (full tree)
for subdir in agents hooks hooks/lib rules reviewers scripts; do
    mkdir -p "$STAGE/.claude/$subdir"
done
cp .claude/settings.json "$STAGE/.claude/"
cp .claude/mode "$STAGE/.claude/"
cp .claude/deploy-gates.json "$STAGE/.claude/"
cp .claude/deploy-state.json "$STAGE/.claude/"
cp .claude/dev-log.md "$STAGE/.claude/" 2>/dev/null || true

# Copy subdirectories
for subdir in agents hooks hooks/lib rules reviewers scripts; do
    if ls ".claude/$subdir/"* &>/dev/null 2>&1; then
        cp ".claude/$subdir/"* "$STAGE/.claude/$subdir/" 2>/dev/null || true
    fi
done

# Build the zip from the staging directory
# The -j flag is NOT used — paths are preserved relative to .package-tmp/
cd .package-tmp
zip -r "$PROJECT_DIR/managers-agent-fleet.zip" managers-agent-fleet/
cd "$PROJECT_DIR"

# Clean up
rm -rf .package-tmp

# Verify
echo ""
echo "Built: managers-agent-fleet.zip"
echo "Contents verify — top-level directory:"
unzip -l managers-agent-fleet.zip | head -5
echo "..."
FILE_COUNT=$(unzip -l managers-agent-fleet.zip | tail -1 | awk '{print $2}')
echo "Total: $FILE_COUNT files"
echo ""
echo "Users extract with:"
echo "  unzip managers-agent-fleet.zip"
echo "  bash managers-agent-fleet/install.sh"
