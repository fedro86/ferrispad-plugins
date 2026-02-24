# FerrisPad Official Plugins

Official plugins for [FerrisPad](https://github.com/fedro86/ferrispad), a lightweight text editor written in Rust.

## Available Plugins

| Plugin | Description | Status |
|--------|-------------|--------|
| [python-lint](python-lint/) | Python linting with ruff and pyright | Stable |
| [rust-lint](rust-lint/) | Rust linting with clippy and cargo build | Stable |

## Installation

### Manual Installation

Copy the desired plugin folder to your FerrisPad plugins directory:

```bash
# Linux/macOS
cp -r <plugin-name> ~/.config/ferrispad/plugins/

# Windows
copy <plugin-name> %APPDATA%\ferrispad\plugins\
```

### From This Repository

```bash
# Clone the repository
git clone https://github.com/fedro86/ferrispad-plugins.git

# Copy desired plugins
cp -r ferrispad-plugins/python-lint ~/.config/ferrispad/plugins/
```

## Plugin Structure

Each plugin follows this structure:

```
plugin-name/
├── init.lua      # Main plugin file (required)
├── plugin.toml   # Plugin metadata and permissions (required)
└── README.md     # Documentation (required)
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

See the [FerrisPad Plugin API Documentation](https://github.com/fedro86/ferrispad/blob/main/docs/temp/0.9.1/07_DIAGNOSTIC_PANEL_ENHANCEMENTS.md) for details on:

- Available hooks (`on_document_open`, `on_document_save`, `on_document_lint`, etc.)
- API functions (`api:run_command()`, `api:file_exists()`, etc.)
- Diagnostic format and severity levels

## Contributing

1. Fork this repository
2. Create a new folder for your plugin
3. Include `init.lua`, `plugin.toml`, and `README.md`
4. Submit a pull request

## License

MIT License - see individual plugin folders for specific licenses.
