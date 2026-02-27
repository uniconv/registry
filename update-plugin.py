#!/usr/bin/env python3
"""
Update the registry after a plugin release.

Fetches the latest manifest.json from the uniconv/plugins repo (which
CI has already populated with SHA256 hashes) and syncs it into the
registry, updating index.json accordingly.

Usage:
    python update-plugin.py ascii
    python update-plugin.py video-convert
    python update-plugin.py all                  # update every plugin
    python update-plugin.py ascii --dry-run
    python update-plugin.py ascii --push         # commit & push after update
    python update-plugin.py all --push --dry-run # preview what would happen

Prerequisites:
    - GitHub CLI (gh) installed and authenticated
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PLUGINS_REPO = "uniconv/plugins"


def die(msg: str):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def run(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    """Run a command and return the result. Dies on failure unless check=False."""
    check = kwargs.pop("check", True)
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if check and result.returncode != 0:
        cmd_str = " ".join(args)
        die(f"{cmd_str} failed:\n{result.stderr.strip()}")
    return result


def git(*args: str) -> str:
    """Run a git command in the registry directory and return stdout."""
    result = run(["git", "-C", str(SCRIPT_DIR), *args])
    return result.stdout.strip()


def update_one_plugin(plugin: str, *, dry_run: bool):
    """Fetch manifest from plugins repo and update the registry for one plugin."""

    # --- Step 1: Fetch manifest from plugins repo ---
    print(f"--- Step 1: Fetch manifest from {PLUGINS_REPO} ({plugin}) ---")

    tmpdir = tempfile.mkdtemp()
    try:
        # Get download URL via gh CLI
        result = run([
            "gh", "api",
            f"repos/{PLUGINS_REPO}/contents/{plugin}/manifest.json",
            "--jq", ".download_url",
        ])
        manifest_url = result.stdout.strip()
        if not manifest_url:
            die(f"Could not find {plugin}/manifest.json in {PLUGINS_REPO}")

        tmp_manifest = os.path.join(tmpdir, "manifest.json")
        run(["curl", "-sL", manifest_url, "-o", tmp_manifest])

        with open(tmp_manifest) as f:
            manifest = json.load(f)

        version = manifest["releases"][0]["version"]
        interface = manifest["releases"][0]["interface"]
        scope = manifest.get("scope", manifest["name"])

        print(f"  Plugin:    {plugin}")
        print(f"  Scope:     {scope}")
        print(f"  Latest:    {version}")
        print(f"  Interface: {interface}")
        print()

        # --- Step 2: Update registry manifest ---
        print(f"--- Step 2: Update registry manifest ({plugin}) ---")

        registry_manifest = SCRIPT_DIR / "plugins" / plugin / "manifest.json"

        if dry_run:
            print(f"  [dry-run] Would copy manifest to {registry_manifest}")
        else:
            registry_manifest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(tmp_manifest, registry_manifest)
            print(f"  Updated: plugins/{plugin}/manifest.json")
        print()

        # --- Step 3: Update index.json ---
        print(f"--- Step 3: Update index.json ({plugin}) ---")

        index_file = SCRIPT_DIR / "index.json"
        if not index_file.is_file():
            die(f"index.json not found: {index_file}")

        if dry_run:
            print(f"  [dry-run] Would update {plugin} in index.json (latest: {version})")
        else:
            with open(index_file) as f:
                index = json.load(f)

            description = manifest.get("description", "")
            keywords = manifest.get("keywords", [])

            # Find or create entry
            existing = None
            for entry in index["plugins"]:
                if entry["name"] == plugin:
                    existing = entry
                    break

            if existing:
                existing["scope"] = scope
                existing["latest"] = version
                existing["description"] = description
                existing["keywords"] = keywords
                print(f"  Updated {plugin} in index.json (latest: {version})")
            else:
                index["plugins"].append({
                    "name": plugin,
                    "scope": scope,
                    "description": description,
                    "keywords": keywords,
                    "latest": version,
                    "author": "uniconv",
                    "interface": interface,
                })
                print(f"  Added {plugin} to index.json")

            index["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

            with open(index_file, "w") as f:
                json.dump(index, f, indent=2)
                f.write("\n")
        print()

        print(f"=== Done: registry updated for {plugin} v{version} ===")

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def find_all_plugins() -> list[str]:
    """Discover all plugins by listing directories under plugins/."""
    plugins_dir = SCRIPT_DIR / "plugins"
    if not plugins_dir.is_dir():
        return []
    return sorted(d.name for d in plugins_dir.iterdir() if d.is_dir())


def main():
    parser = argparse.ArgumentParser(description="Update the registry after a plugin release")
    parser.add_argument("name", help="Plugin name or 'all'")
    parser.add_argument("--dry-run", action="store_true", help="Show what would happen")
    parser.add_argument("--push", action="store_true", help="Commit & push after update")
    args = parser.parse_args()

    name = args.name
    dry_run = args.dry_run
    push = args.push
    updated_plugins: list[str] = []

    if name == "all":
        for plugin in find_all_plugins():
            print("========================================")
            print(f"  Updating plugin: {plugin}")
            print("========================================")
            print()
            update_one_plugin(plugin, dry_run=dry_run)
            updated_plugins.append(plugin)
            print()
    else:
        update_one_plugin(name, dry_run=dry_run)
        updated_plugins.append(name)

    # --- Step 4: Commit & push (if --push) ---
    if push:
        print("--- Step 4: Commit & push ---")

        if len(updated_plugins) == 1:
            commit_msg = f"chore({updated_plugins[0]}): update plugin manifest"
        else:
            commit_msg = "chore: update plugin manifests"

        if dry_run:
            print(f"  [dry-run] Would commit: {commit_msg}")
            print("  [dry-run] Would push to remote")
        else:
            git("add", "plugins/", "index.json")
            git("commit", "-m", commit_msg)
            git("push")
            print(f"  Committed and pushed: {commit_msg}")
        print()

    print("=== All done ===")


if __name__ == "__main__":
    main()
