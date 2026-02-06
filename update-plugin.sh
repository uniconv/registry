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
#   ./update-plugin.sh all                  # update every plugin
#   ./update-plugin.sh ascii --dry-run
#   ./update-plugin.sh ascii --push         # commit & push after update
#   ./update-plugin.sh all --push --dry-run # preview what would happen
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_REPO="uniconv/plugins"
DRY_RUN=false
PUSH=false

# --- Helpers ---

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
    echo "Usage: $0 <plugin-name|all> [--dry-run] [--push]"
    exit 1
}

# --- Parse arguments ---

[[ $# -ge 1 ]] || usage

NAME="$1"
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --push)    PUSH=true ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

# --- update_one_plugin: Steps 1-3 for a single plugin ---

update_one_plugin() {
    local plugin="$1"

    # --- Step 1: Fetch manifest from plugins repo ---

    echo "--- Step 1: Fetch manifest from $PLUGINS_REPO ($plugin) ---"

    local tmpdir
    tmpdir=$(mktemp -d)

    local manifest_url
    manifest_url=$(gh api "repos/$PLUGINS_REPO/contents/$plugin/manifest.json" --jq '.download_url')
    [[ -n "$manifest_url" ]] || die "Could not find $plugin/manifest.json in $PLUGINS_REPO"

    curl -sL "$manifest_url" -o "$tmpdir/manifest.json"

    # Extract metadata from the fetched manifest
    local version interface
    version=$(python3 -c "import json; m=json.load(open('$tmpdir/manifest.json')); print(m['releases'][0]['version'])")
    interface=$(python3 -c "import json; m=json.load(open('$tmpdir/manifest.json')); print(m['releases'][0]['interface'])")

    echo "  Plugin:    $plugin"
    echo "  Latest:    $version"
    echo "  Interface: $interface"
    echo ""

    # --- Step 2: Update registry manifest ---

    echo "--- Step 2: Update registry manifest ($plugin) ---"

    local registry_manifest="$SCRIPT_DIR/plugins/$plugin/manifest.json"

    if $DRY_RUN; then
        echo "  [dry-run] Would copy manifest to $registry_manifest"
    else
        mkdir -p "$SCRIPT_DIR/plugins/$plugin"
        cp "$tmpdir/manifest.json" "$registry_manifest"
        echo "  Updated: plugins/$plugin/manifest.json"
    fi
    echo ""

    # --- Step 3: Update index.json ---

    echo "--- Step 3: Update index.json ($plugin) ---"

    local index_file="$SCRIPT_DIR/index.json"
    [[ -f "$index_file" ]] || die "index.json not found: $index_file"

    if $DRY_RUN; then
        echo "  [dry-run] Would update $plugin in index.json (latest: $version)"
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
" "$plugin" "$version" "$interface" "$tmpdir/manifest.json" "$index_file"
    fi
    echo ""

    echo "=== Done: registry updated for $plugin v$version ==="

    rm -rf "$tmpdir"
}

# --- Main ---

UPDATED_PLUGINS=()

if [[ "$NAME" == "all" ]]; then
    # Discover all plugins by listing directories under plugins/
    for dir in "$SCRIPT_DIR/plugins"/*/; do
        plugin=$(basename "$dir")
        echo "========================================"
        echo "  Updating plugin: $plugin"
        echo "========================================"
        echo ""
        update_one_plugin "$plugin"
        UPDATED_PLUGINS+=("$plugin")
        echo ""
    done
else
    update_one_plugin "$NAME"
    UPDATED_PLUGINS+=("$NAME")
fi

# --- Step 4: Commit & push (if --push) ---

if $PUSH; then
    echo "--- Step 4: Commit & push ---"

    if $DRY_RUN; then
        if [[ "${#UPDATED_PLUGINS[@]}" -eq 1 ]]; then
            echo "  [dry-run] Would commit: chore(${UPDATED_PLUGINS[0]}): update plugin manifest"
        else
            echo "  [dry-run] Would commit: chore: update plugin manifests"
        fi
        echo "  [dry-run] Would push to remote"
    else
        cd "$SCRIPT_DIR"
        git add plugins/ index.json

        commit_msg=""
        if [[ "${#UPDATED_PLUGINS[@]}" -eq 1 ]]; then
            commit_msg="chore(${UPDATED_PLUGINS[0]}): update plugin manifest"
        else
            commit_msg="chore: update plugin manifests"
        fi

        git commit -m "$commit_msg"
        git push
        echo "  Committed and pushed: $commit_msg"
    fi
    echo ""
fi

echo "=== All done ==="
