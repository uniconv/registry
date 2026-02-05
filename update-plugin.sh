#!/bin/bash
set -euo pipefail

# Update the registry after a plugin release.
#
# Fetches the latest manifest.json from the uniconv/plugins repo (which
# CI has already populated with SHA256 hashes) and syncs it into the
# registry, updating index.json accordingly.
#
# Usage:
#   ./update-plugin.sh ascii
#   ./update-plugin.sh video-convert
#   ./update-plugin.sh ascii --dry-run
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_REPO="uniconv/plugins"
DRY_RUN=false

# --- Helpers ---

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
    echo "Usage: $0 <plugin-name> [--dry-run]"
    exit 1
}

# --- Parse arguments ---

[[ $# -ge 1 ]] || usage

NAME="$1"
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

# --- Step 1: Fetch manifest from plugins repo ---

echo "--- Step 1: Fetch manifest from $PLUGINS_REPO ---"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

MANIFEST_URL=$(gh api "repos/$PLUGINS_REPO/contents/$NAME/manifest.json" --jq '.download_url')
[[ -n "$MANIFEST_URL" ]] || die "Could not find $NAME/manifest.json in $PLUGINS_REPO"

curl -sL "$MANIFEST_URL" -o "$TMPDIR/manifest.json"

# Extract metadata from the fetched manifest
VERSION=$(python3 -c "import json; m=json.load(open('$TMPDIR/manifest.json')); print(m['releases'][0]['version'])")
INTERFACE=$(python3 -c "import json; m=json.load(open('$TMPDIR/manifest.json')); print(m['releases'][0]['interface'])")

echo "  Plugin:    $NAME"
echo "  Latest:    $VERSION"
echo "  Interface: $INTERFACE"
echo ""

# --- Step 2: Update registry manifest ---

echo "--- Step 2: Update registry manifest ---"

REGISTRY_MANIFEST="$SCRIPT_DIR/plugins/$NAME/manifest.json"

if $DRY_RUN; then
    echo "  [dry-run] Would copy manifest to $REGISTRY_MANIFEST"
else
    mkdir -p "$SCRIPT_DIR/plugins/$NAME"
    cp "$TMPDIR/manifest.json" "$REGISTRY_MANIFEST"
    echo "  Updated: plugins/$NAME/manifest.json"
fi
echo ""

# --- Step 3: Update index.json ---

echo "--- Step 3: Update index.json ---"

INDEX_FILE="$SCRIPT_DIR/index.json"
[[ -f "$INDEX_FILE" ]] || die "index.json not found: $INDEX_FILE"

if $DRY_RUN; then
    echo "  [dry-run] Would update $NAME in index.json (latest: $VERSION)"
else
    python3 -c "
import json, sys
from datetime import datetime, timezone

name = sys.argv[1]
version = sys.argv[2]
interface = sys.argv[3]
manifest_path = sys.argv[4]
index_path = sys.argv[5]

with open(index_path) as f:
    index = json.load(f)

with open(manifest_path) as f:
    manifest = json.load(f)

description = manifest.get('description', '')
keywords = manifest.get('keywords', [])

# Find or create entry
existing = None
for entry in index['plugins']:
    if entry['name'] == name:
        existing = entry
        break

if existing:
    existing['latest'] = version
    existing['description'] = description
    existing['keywords'] = keywords
    print(f'  Updated {name} in index.json (latest: {version})')
else:
    index['plugins'].append({
        'name': name,
        'description': description,
        'keywords': keywords,
        'latest': version,
        'author': 'uniconv',
        'interface': interface
    })
    print(f'  Added {name} to index.json')

index['updated_at'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

with open(index_path, 'w') as f:
    json.dump(index, f, indent=2)
    f.write('\n')
" "$NAME" "$VERSION" "$INTERFACE" "$TMPDIR/manifest.json" "$INDEX_FILE"
fi
echo ""

echo "=== Done: registry updated for $NAME v$VERSION ==="
echo "  Remember to commit and push the changes."
