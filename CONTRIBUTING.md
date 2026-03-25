# Contributing to FerrisPad Plugins

Thank you for your interest in contributing to FerrisPad's plugin ecosystem!

## Ways to Contribute

### 1. Create an Official Plugin

Official plugins are hosted in this repository, signed by the FerrisPad maintainer, and shown with a "Verified" badge in the Plugin Manager.

**Process:**
1. Fork this repository
2. Create a plugin directory with the required files (see below)
3. Submit a pull request
4. After review, the maintainer signs the plugin and updates `plugins.json`

**Requirements:**
- `init.lua` — main plugin logic
- `plugin.toml` — metadata, permissions, menu items, configuration
- `README.md` — user documentation
- `CHANGELOG.md` — version history (Keep a Changelog format)

### 2. Create a Community Plugin

Community plugins live in their own GitHub repositories and are listed in `community-plugins.json`. They appear in the Plugin Manager's Community tab with a "Community" badge.

**Process:**
1. Create a public GitHub repository with `init.lua` and `plugin.toml` at the root
2. Tag a release (e.g., `git tag v1.0.0 && git push origin v1.0.0`)
3. Compute checksums: `sha256sum init.lua plugin.toml`
4. Open a pull request to this repository adding an entry to `community-plugins.json`:

```json
{
  "name": "your-plugin-name",
  "repo": "https://github.com/your-user/your-plugin-repo",
  "git_ref": "v1.0.0",
  "version": "1.0.0",
  "description": "Short description",
  "author": "Your Name",
  "license": "MIT",
  "min_ferrispad_version": "0.9.2",
  "tags": ["relevant", "tags"],
  "checksums": {
    "init.lua": "sha256:<hex>",
    "plugin.toml": "sha256:<hex>"
  }
}
```

**Security review is mandatory.** All community plugins are reviewed for:
- No blocked Lua patterns (`loadstring`, `debug`, `ffi`, `_G`, etc.)
- Permissions match actual tool usage
- Well-formed `plugin.toml`
- Checksums match the repository files

Plugins that represent a security threat will be removed from the registry.

### 3. Improve Existing Plugins

Bug fixes, feature additions, and documentation improvements to existing official plugins are welcome via pull request.

### 4. Report Issues

Open an issue at [ferrispad-plugins](https://github.com/fedro86/ferrispad-plugins/issues) for bugs, feature requests, or questions.

## Plugin Development Documentation

The full plugin development guide — API reference, hooks, widgets, security model, publishing, and cookbook — lives in the **[ferrispad-plugins wiki](https://github.com/fedro86/ferrispad-plugins/wiki)**.

Key pages:
- [Getting Started](https://github.com/fedro86/ferrispad-plugins/wiki/Getting-Started) — Create your first plugin in 5 minutes
- [Plugin Lifecycle](https://github.com/fedro86/ferrispad-plugins/wiki/Plugin-Lifecycle) — Discovery, loading, state, reload, shutdown
- [Editor API](https://github.com/fedro86/ferrispad-plugins/wiki/Editor-API) — Document query, filesystem, commands, configuration
- [Hooks Reference](https://github.com/fedro86/ferrispad-plugins/wiki/Hooks-Reference) — All 11 event hooks
- [Widget API](https://github.com/fedro86/ferrispad-plugins/wiki/Widget-API) — Tree views, split panels, terminal views
- [Plugin TOML Reference](https://github.com/fedro86/ferrispad-plugins/wiki/Plugin-TOML-Reference) — Manifest format
- [Security Model](https://github.com/fedro86/ferrispad-plugins/wiki/Security-Model) — Sandbox, permissions, trust tiers
- [Cookbook](https://github.com/fedro86/ferrispad-plugins/wiki/Cookbook) — Common recipes

## Keyboard Shortcut Conventions

| Plugin | Shortcut |
|--------|----------|
| Python Lint | `Ctrl+Shift+P` |
| Rust Lint | `Ctrl+Shift+R` |
| JavaScript Lint | `Ctrl+Shift+J` |
| File Explorer | `Ctrl+Shift+E` |
| YAML/JSON Viewer | `Ctrl+Shift+Y` |
| Claude Code | `Ctrl+Shift+I` |

## Official Plugin Submission Checklist

- [ ] `init.lua`, `plugin.toml`, `README.md`, `CHANGELOG.md` present
- [ ] Tool detection with helpful error messages
- [ ] Project/environment detection appropriate for the language
- [ ] JSON output parsing (for linter plugins)
- [ ] Configurable parameters with sensible defaults
- [ ] Documentation URLs for diagnostics (if available)
- [ ] Tested all menu actions
- [ ] Updated `plugins.json` registry
- [ ] Updated main `README.md` plugins table

## License

MIT License — see individual plugin folders for specific licenses.
