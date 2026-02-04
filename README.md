# uniconv plugin registry

Official plugin registry for [uniconv](https://github.com/uniconv/uniconv), a universal file converter with a plugin-based pipeline architecture.

This repository serves as the centralized catalog of plugins. When you run `uniconv plugin install <name>`, uniconv fetches plugin metadata from this registry and downloads the appropriate artifact.

## Available Plugins

| Plugin | Type | Description | Platforms |
|--------|------|-------------|-----------|
| [ascii](plugins/ascii/manifest.json) | CLI | Convert media to ASCII representation | Any (Python) |
| [image-filter](plugins/image-filter/manifest.json) | CLI | Apply image filters (grayscale, invert) | Any (Python) |
| [image-convert](plugins/image-convert/manifest.json) | Native | Image format conversion using libvips | linux-x86_64, linux-aarch64, darwin-aarch64 |
| [video-convert](plugins/video-convert/manifest.json) | Native | Convert video formats using FFmpeg | linux-x86_64, darwin-aarch64 |

## Installing Plugins

```bash
# Install a single plugin
uniconv plugin install image-convert

# Install a collection
uniconv plugin install +essentials
```

### Collections

| Collection | Plugins | Description |
|------------|---------|-------------|
| essentials | ascii, image-filter, video-convert, image-convert | Essential plugins for common media operations |

## Repository Structure

```
registry/
├── index.json                  # Plugin index (all plugins, latest versions)
├── collections.json            # Named plugin collections
├── plugins/
│   ├── DEVELOPMENT.md          # Plugin development guide
│   ├── ascii/manifest.json
│   ├── image-convert/manifest.json
│   ├── image-filter/manifest.json
│   └── video-convert/manifest.json
└── update-plugin.sh            # Script to sync plugin manifests
```

- **index.json** -- Lightweight index listing all plugins with name, description, latest version, and interface type. This is the first file uniconv fetches when resolving plugins.
- **collections.json** -- Defines named groups of plugins for bulk installation.
- **plugins/\<name\>/manifest.json** -- Full manifest for each plugin including release history, platform-specific artifact URLs, SHA256 checksums, and dependency declarations.

## For Plugin Developers

See [plugins/DEVELOPMENT.md](plugins/DEVELOPMENT.md) for the full guide covering:

- Plugin types (CLI vs Native)
- Manifest format and fields
- CLI plugin protocol (arguments, JSON output)
- Native plugin C++ API
- Dependency management
- Testing and publishing

### Submitting a Plugin

1. Create a plugin following the [development guide](plugins/DEVELOPMENT.md)
2. Host your artifact on GitHub Releases (or another public URL)
3. Add a `plugins/<your-plugin>/manifest.json` with release metadata
4. Update `index.json` with your plugin entry
5. Submit a pull request

## License

MIT
