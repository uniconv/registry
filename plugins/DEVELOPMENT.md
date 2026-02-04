# Plugin Development Guide

This guide covers everything you need to build, test, and publish a uniconv plugin.

## Table of Contents

- [Overview](#overview)
- [Plugin Types](#plugin-types)
- [Manifest (plugin.json)](#manifest)
- [CLI Plugin Development](#cli-plugin-development)
- [Native Plugin Development](#native-plugin-development)
- [Dependencies](#dependencies)
- [Testing Your Plugin](#testing-your-plugin)
- [Publishing to the Registry](#publishing-to-the-registry)

---

## Overview

A uniconv plugin is a directory containing:

```
my-plugin/
├── plugin.json          # Manifest (required)
├── my-plugin.py         # Executable or shared library
└── ...                  # Any supporting files
```

uniconv discovers plugins by scanning for `plugin.json` files in:

1. `~/.uniconv/plugins/` (user plugins)
2. `<executable>/plugins/` (portable plugins)
3. `/usr/local/share/uniconv/plugins/` (system plugins)

Plugins come in two types: **CLI** (recommended) and **Native**.

---

## Plugin Types

### CLI Plugins

CLI plugins are external executables invoked as subprocesses. They can be written in any language — Python, Bash, Go, Rust, Node.js, etc.

- Any language
- No compilation needed for scripting languages
- Process-isolated (bugs don't crash uniconv)
- Slight overhead from subprocess spawning

### Native Plugins

Native plugins are shared libraries (`.so`, `.dylib`, `.dll`) loaded directly into the uniconv process via the C ABI defined in `include/uniconv/plugin_api.h`.

- Maximum performance (no IPC)
- Must be compiled per platform
- More complex to develop
- Bugs can crash the host process

**Use CLI plugins unless you have a specific performance need.**

---

## Manifest

Every plugin requires a `plugin.json` manifest:

```json
{
  "name": "image-filter",
  "scope": "image-filter",
  "version": "1.0.0",
  "description": "Apply image filters (grayscale, invert)",
  "interface": "cli",
  "executable": "image_filter.py",
  "targets": ["grayscale", "gray", "bw", "invert", "negative"],
  "input_formats": ["jpg", "jpeg", "png", "webp", "bmp", "gif"],
  "input_types": ["image", "file"],
  "output_types": ["image"],
  "options": [
    {
      "name": "--quality",
      "type": "int",
      "default": "85",
      "description": "Output quality (1-100)"
    }
  ],
  "dependencies": [
    { "name": "python3", "type": "system", "version": ">=3.8" },
    { "name": "Pillow", "type": "python", "version": ">=9.0" }
  ]
}
```

### Field Reference

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Unique plugin identifier |
| `scope` | no | Plugin scope (defaults to `name`) |
| `version` | no | Semver string (defaults to `"0.0.0"`) |
| `description` | no | Human-readable description |
| `interface` | yes | `"cli"` or `"native"` |
| `executable` | cli only | Path to executable (relative to plugin dir or absolute) |
| `library` | native only | Shared library filename (e.g., `"libimage_invert"`) |
| `targets` | yes | Array of target names this plugin handles |
| `input_formats` | no | Array of file extensions this plugin accepts |
| `input_types` | no | Array of data types: `file`, `image`, `video`, `audio`, `text`, `json`, `binary`, `stream` |
| `output_types` | no | Array of data types this plugin produces |
| `options` | no | Array of option definitions (see below) |
| `dependencies` | no | Array of dependency declarations (see [Dependencies](#dependencies)) |

### Options

Each option is an object:

```json
{
  "name": "--quality",
  "type": "int",
  "default": "85",
  "description": "Output quality (1-100)"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Flag name including `--` prefix |
| `type` | no | `"string"`, `"int"`, `"float"`, `"bool"` (default: `"string"`) |
| `default` | no | Default value as string |
| `description` | no | Help text |

### Data Types and Pipeline Compatibility

The `input_types` and `output_types` fields determine which plugins can be chained in a pipeline. For two plugins to connect, the first plugin's output type must match the second's input type.

The `file` type is a universal fallback — it connects to anything.

Example: a plugin with `output_types: ["image"]` can connect to a plugin with `input_types: ["image", "file"]`.

---

## CLI Plugin Development

### Protocol

uniconv passes these arguments to every CLI plugin:

```
--input <path>       Input file path (always provided)
--target <target>    Target name (always provided)
--output <path>      Output path (if user specified -o)
--force              Overwrite existing files
--dry-run            Don't process, just report what would happen
```

Plugin-specific options declared in the manifest are appended after `--`:

```
grayscale.py --input photo.jpg --target grayscale --output out.jpg -- --quality 90 --method average
```

### Output Format

Your plugin must write JSON to stdout:

**On success:**

```json
{
  "success": true,
  "output": "/absolute/path/to/output.jpg",
  "output_size": 12345,
  "extra": {
    "method": "luminosity",
    "original_size": [1920, 1080]
  }
}
```

**On error:**

```json
{
  "success": false,
  "error": "Descriptive error message"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `success` | yes | `true` or `false` |
| `output` | on success | Absolute path to the output file |
| `output_size` | no | Output file size in bytes |
| `error` | on failure | Error message string |
| `extra` | no | Any additional data as a JSON object |

Write all diagnostic or log messages to **stderr**, not stdout. uniconv only parses stdout as JSON.

### Minimal Python Example

```python
#!/usr/bin/env python3
import argparse
import json
import os
import sys

def main():
    parser = argparse.ArgumentParser()

    # Universal arguments
    parser.add_argument('--input', required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--output')
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--dry-run', action='store_true')

    # Plugin-specific options
    parser.add_argument('--my-option', default='value')

    args, _ = parser.parse_known_args()

    # Determine output path
    base, ext = os.path.splitext(args.input)
    output_path = args.output or f"{base}_{args.target}{ext}"

    if args.dry_run:
        print(json.dumps({"success": True, "output": output_path}))
        return 0

    try:
        # ... do your processing here ...
        # write result to output_path

        print(json.dumps({
            "success": True,
            "output": os.path.abspath(output_path),
            "output_size": os.path.getsize(output_path)
        }))
        return 0
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        return 1

if __name__ == '__main__':
    sys.exit(main())
```

### Minimal Bash Example

```bash
#!/bin/bash
set -euo pipefail

INPUT="" TARGET="" OUTPUT="" FORCE=0 DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)   INPUT="$2"; shift 2 ;;
        --target)  TARGET="$2"; shift 2 ;;
        --output)  OUTPUT="$2"; shift 2 ;;
        --force)   FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --)        shift; break ;;
        *)         shift ;;
    esac
done

BASE="${INPUT%.*}"
EXT="${INPUT##*.}"
OUTPUT="${OUTPUT:-${BASE}_${TARGET}.${EXT}}"

if [[ $DRY_RUN -eq 1 ]]; then
    echo "{\"success\": true, \"output\": \"$OUTPUT\"}"
    exit 0
fi

# ... do processing ...

SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT" 2>/dev/null || echo 0)
echo "{\"success\": true, \"output\": \"$(realpath "$OUTPUT")\", \"output_size\": $SIZE}"
```

### Important Notes

- Your executable must be... executable. Use `chmod +x` for scripts.
- The shebang line (`#!/usr/bin/env python3`) is required for scripts.
- uniconv enforces a 5-minute timeout by default. Long-running plugins will be killed.
- Exit code 0 with valid JSON = success. Non-zero exit with no JSON = uniconv reports the stderr.

---

## Native Plugin Development

Native plugins implement three C functions exported from a shared library.

### Required Exports

```c
#include <uniconv/plugin_api.h>

// Return plugin metadata (called once at load time)
UNICONV_EXPORT UniconvPluginInfo* uniconv_plugin_info(void);

// Process a file (called per invocation)
UNICONV_EXPORT UniconvResult* uniconv_plugin_execute(const UniconvRequest* request);

// Free a result (called after uniconv reads the result)
UNICONV_EXPORT void uniconv_plugin_free_result(UniconvResult* result);
```

### Minimal C++ Example

```cpp
#include <uniconv/plugin_api.h>
#include <cstdlib>
#include <cstring>
#include <string>

static const char* targets[] = {"mytarget", nullptr};
static const char* input_formats[] = {"jpg", "png", nullptr};
static UniconvDataType in_types[] = {UNICONV_DATA_IMAGE, (UniconvDataType)0};
static UniconvDataType out_types[] = {UNICONV_DATA_IMAGE, (UniconvDataType)0};

static UniconvPluginInfo info = {
    .name = "my-native-plugin",
    .scope = "my-native-plugin",
    .version = "1.0.0",
    .description = "Does something with images",
    .targets = targets,
    .input_formats = input_formats,
    .input_types = in_types,
    .output_types = out_types
};

extern "C" {

UNICONV_EXPORT UniconvPluginInfo* uniconv_plugin_info(void) {
    return &info;
}

UNICONV_EXPORT UniconvResult* uniconv_plugin_execute(const UniconvRequest* request) {
    UniconvResult* result = (UniconvResult*)calloc(1, sizeof(UniconvResult));

    if (!request || !request->source) {
        result->status = UNICONV_ERROR;
        result->error = strdup("Missing source");
        return result;
    }

    if (request->dry_run) {
        result->status = UNICONV_SUCCESS;
        result->output = strdup(request->source);
        return result;
    }

    // ... do processing ...

    std::string output_path = std::string(request->source) + ".out";

    result->status = UNICONV_SUCCESS;
    result->output = strdup(output_path.c_str());
    return result;
}

UNICONV_EXPORT void uniconv_plugin_free_result(UniconvResult* result) {
    UNICONV_DEFAULT_FREE_RESULT(result);
}

} // extern "C"
```

### CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.16)
project(my-plugin VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)

set(UNICONV_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../include"
    CACHE PATH "Path to uniconv include directory")

add_library(my_plugin SHARED my_plugin.cpp)

target_include_directories(my_plugin PRIVATE ${UNICONV_INCLUDE_DIR})

set_target_properties(my_plugin PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "my_plugin"
)

install(TARGETS my_plugin LIBRARY DESTINATION . RUNTIME DESTINATION .)
install(FILES plugin.json DESTINATION .)
```

### Helper Macros

`plugin_api.h` provides convenience macros:

```c
// Allocate a zeroed result
UniconvResult* r = UNICONV_RESULT_ALLOC();

// Return a success result (allocates, sets fields, returns)
UNICONV_RESULT_SUCCESS("/path/to/output.jpg", 12345);

// Return an error result (allocates, sets fields, returns)
UNICONV_RESULT_ERROR("Something went wrong");

// Free all fields of a result
UNICONV_DEFAULT_FREE_RESULT(result);
```

### Accessing Options

The `UniconvRequest` provides option getter callbacks:

```c
const char* quality = request->get_plugin_option("quality", request->options_ctx);
if (quality) {
    int q = atoi(quality);
    // use q
}
```

---

## Dependencies

Plugins can declare their runtime dependencies in `plugin.json`. uniconv checks these at install time and warns the user about missing ones — it does not auto-install them.

```json
"dependencies": [
  { "name": "python3", "type": "system", "version": ">=3.8" },
  { "name": "Pillow", "type": "python", "version": ">=9.0" },
  { "name": "libvips-dev", "type": "system", "check": "pkg-config --exists vips-cpp" }
]
```

### Dependency Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Package or binary name |
| `type` | yes | `"system"`, `"python"`, `"node"` |
| `version` | no | Version constraint (e.g., `">=3.8"`) |
| `check` | no | Custom shell command to verify presence (exit 0 = found) |

### How Checks Work

| Type | Default check method |
|------|---------------------|
| `system` | `which <name>`, then `<name> --version` for version constraint |
| `python` | `pip show <name>`, parses `Version:` line |
| `node` | `npm ls -g <name>` |
| (any) | If `check` is provided, runs that command instead |

The `check` field is an escape hatch for cases where the default method doesn't work. For example, `libvips-dev` isn't a binary in PATH, so `which` would fail — but `pkg-config --exists vips-cpp` correctly detects it.

### What the User Sees

When dependencies are missing, `uniconv plugin install` prints:

```
Missing dependencies:
  [system] ffmpeg -- apt install ffmpeg
  [python] Pillow >=9.0 -- pip install 'Pillow>=9.0'

Plugin may not work until dependencies are resolved.
```

Only declare dependencies that are actually required. If a dependency is optional (enables extra features but isn't needed for basic operation), don't list it — mention it in your README instead.

---

## Testing Your Plugin

### 1. Test standalone

Run your plugin directly to verify the protocol:

```bash
# CLI plugin
./my-plugin.py --input test.jpg --target mytarget --dry-run
# Should output: {"success": true, "output": "test_mytarget.jpg"}

./my-plugin.py --input test.jpg --target mytarget
# Should output: {"success": true, "output": "/abs/path/test_mytarget.jpg", "output_size": ...}
```

### 2. Install locally

```bash
# From your plugin directory
uniconv plugin install ./my-plugin

# Verify it shows up
uniconv plugin list

# Check details
uniconv plugin info my-plugin
```

### 3. Run through uniconv

```bash
# Basic conversion
uniconv "test.jpg | mytarget"

# With options
uniconv "test.jpg | mytarget --quality 90"

# In a pipeline
uniconv "test.jpg | grayscale | mytarget"

# Dry run
uniconv --dry-run "test.jpg | mytarget"
```

### 4. Test error handling

- Missing input file
- Invalid input format
- Output path already exists (without `--force`)
- Missing runtime dependencies

---

## Publishing to the Registry

The uniconv plugin registry is a GitHub repository served via GitHub Pages. Users install plugins with `uniconv plugin install <name>`.

### Step 1: Package your plugin

Create a tarball containing your plugin directory:

```bash
# Your plugin directory structure:
#   my-plugin/
#   ├── plugin.json
#   ├── my-plugin.py
#   └── ...

tar czf my-plugin-1.0.0.tar.gz my-plugin/
sha256sum my-plugin-1.0.0.tar.gz
```

For native plugins, build per platform and create separate tarballs:

```bash
my-plugin-1.0.0-linux-x86_64.tar.gz
my-plugin-1.0.0-linux-aarch64.tar.gz
my-plugin-1.0.0-darwin-aarch64.tar.gz
```

### Step 2: Host the artifact

Create a GitHub Release on your plugin's repository and attach the tarball(s).

The download URL will be something like:
```
https://github.com/yourname/uniconv-my-plugin/releases/download/v1.0.0/my-plugin-1.0.0.tar.gz
```

### Step 3: Submit to the registry

Fork the [uniconv/registry](https://github.com/uniconv/registry) repo and create a PR adding `plugins/my-plugin/manifest.json`:

```json
{
  "name": "my-plugin",
  "description": "What the plugin does",
  "author": "yourname",
  "license": "MIT",
  "repository": "https://github.com/yourname/uniconv-my-plugin",
  "keywords": ["image", "filter"],
  "releases": [
    {
      "version": "1.0.0",
      "uniconv_compat": ">=0.1.0",
      "interface": "cli",
      "dependencies": [
        { "name": "python3", "type": "system", "version": ">=3.8" }
      ],
      "artifact": {
        "any": {
          "url": "https://github.com/yourname/uniconv-my-plugin/releases/download/v1.0.0/my-plugin-1.0.0.tar.gz",
          "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        }
      }
    }
  ]
}
```

### Artifact Platform Keys

| Key | When to use |
|-----|-------------|
| `any` | CLI plugins (platform-independent scripts) |
| `linux-x86_64` | Native Linux x86_64 build |
| `linux-aarch64` | Native Linux ARM64 build |
| `darwin-x86_64` | Native macOS Intel build |
| `darwin-aarch64` | Native macOS Apple Silicon build |
| `windows-x86_64` | Native Windows x64 build |

CLI plugins should always use `any`. Native plugins need a key for each platform they support. uniconv resolves the artifact by checking for the user's exact platform first, then falling back to `any`.

### Step 4: Publishing updates

To publish a new version:

1. Package and host the new artifact
2. Submit a PR adding a new entry to the `releases` array (newest first)

```json
"releases": [
  {
    "version": "1.1.0",
    "uniconv_compat": ">=0.1.0",
    "...": "..."
  },
  {
    "version": "1.0.0",
    "...": "..."
  }
]
```

Users update with:

```bash
uniconv plugin update my-plugin
```

### Registry manifest vs local manifest

These are two different files:

| File | Location | Purpose |
|------|----------|---------|
| **Local manifest** (`plugin.json`) | Inside the plugin directory | Tells uniconv how to load and run the plugin |
| **Registry manifest** (`manifest.json`) | In the registry repo under `plugins/<name>/` | Tells uniconv how to download and install the plugin |

The local `plugin.json` is what ships inside the tarball. The registry `manifest.json` is what you submit via PR.

---

## Collections

The registry supports **collections** — named sets of plugins that can be installed together. Users install collections with the `+` prefix:

```bash
uniconv plugin install +essentials
```

Collections are defined in `collections.json` at the registry root:

```json
{
  "version": 1,
  "collections": [
    {
      "name": "essentials",
      "description": "Essential plugins for common media operations",
      "plugins": ["ascii", "image-filter", "video-convert"]
    }
  ]
}
```

When a collection is installed, uniconv fetches the collection definition and installs each member plugin from the registry individually.

---

## Examples

Working examples are in the `examples/` directory:

| Example | Language | Type | Description |
|---------|----------|------|-------------|
| `ascii` | Python | CLI | Media to ASCII art with Pillow |
| `image-filter` | Python | CLI | Image filters (grayscale, invert) with Pillow |
| `video-convert` | C++ | Native | Video format conversion with FFmpeg |
