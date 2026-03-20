# FerrisPad Plugins

Plugin registry for [FerrisPad](https://github.com/fedro86/ferrispad), a lightweight text editor written in Rust.

## Official Plugins

These plugins are hosted in this repository, signed, and verified by FerrisPad.

| Plugin | Version | Description |
|--------|---------|-------------|
| [python-lint](python-lint/) | 2.7.0 | Python linting with ruff and pyright (venv support, lint-on-save) |
| [rust-lint](rust-lint/) | 1.5.0 | Rust linting with clippy and cargo build (individual toggles) |
| [file-explorer](file-explorer/) | 0.5.1 | File explorer tree view with context menus and file management |
| [yaml-json-viewer](yaml-json-viewer/) | 1.0.1 | Tree viewer for YAML and JSON files with search and copy actions |
| [git-diff](git-diff/) | 1.1.0 | Show git diff in a split view with revert capability |

## Community Plugins

Community plugins are hosted in their own repositories and listed in [`community-plugins.json`](community-plugins.json). They are installable from the **Community** tab in FerrisPad's Plugin Manager.

| Plugin | Author | Description |
|--------|--------|-------------|
| [javascript-lint](https://github.com/fedro86/ferrispad-js-linter) | Federico Conticello | Run ESLint on JavaScript and TypeScript files |
| [claude-code](https://github.com/fedro86/ferrispad-claude-code-plugin) | Federico Conticello | AI assistant powered by Claude Code CLI with embedded terminal |

### Three-Tier Trust Model

FerrisPad uses a three-tier trust system for plugins:

| Tier | Badge | Description |
|------|-------|-------------|
| **Official** | Verified | Hosted in this repo, signed with ed25519 — full trust |
| **Community** | Community | Listed in `community-plugins.json`, reviewed before listing |
| **Manual** | Unverified | Installed via URL — no review, user assumes responsibility |

All tiers are installable. The badges are informational, helping users make informed decisions.

### Listing a Community Plugin

To get your plugin listed in the Community tab:

1. Host your plugin in a public GitHub repository with `init.lua` and `plugin.toml` at the root
2. Open a pull request to this repository adding an entry to `community-plugins.json`:

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
    "init.lua": "sha256:<run sha256sum init.lua>",
    "plugin.toml": "sha256:<run sha256sum plugin.toml>"
  }
}
```

3. Checksums are **required** — FerrisPad verifies downloaded files match the registry
4. Your plugin will be reviewed for security (no blocked Lua patterns, reasonable permissions)
5. Once merged, it appears in the Community tab for all FerrisPad users

## Installation

### From the Plugin Manager (recommended)

Open **Plugins > Plugin Manager** in FerrisPad. The **Official** and **Community** tabs let you install plugins with one click.

### Manual Installation

Copy the desired plugin folder to your FerrisPad plugins directory:

```bash
# Linux/macOS
cp -r <plugin-name> ~/.config/ferrispad/plugins/

# Windows
copy <plugin-name> %APPDATA%\ferrispad\plugins\
```

## Plugin Structure

Each plugin follows this structure:

```
plugin-name/
├── init.lua       # Main plugin logic (required)
├── plugin.toml    # Metadata and permissions (required)
├── README.md      # Documentation (required)
└── CHANGELOG.md   # Version history (required for official)
```

### plugin.toml Format

```toml
name = "Plugin Name"
version = "1.0.0"
description = "Short description of the plugin"

[permissions]
execute = ["cmd1", "cmd2"]  # Commands the plugin can run
```

## Writing Plugins

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full plugin API reference, including hooks, API functions, widgets, and diagnostic format.

## Contributing

- **Official plugins**: Fork this repo, create a plugin folder, submit a PR
- **Community plugins**: Host your own repo, submit a PR adding an entry to `community-plugins.json`

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines and the submission checklist.

## License

MIT License - see individual plugin folders for specific licenses.
