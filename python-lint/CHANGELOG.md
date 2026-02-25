# Changelog

All notable changes to the Python Lint plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.5.0] - 2026-02-26

### Added
- `ruff_enabled` and `pyright_enabled` config toggles to enable/disable individual tools
- `ruff_shortcut` and `pyright_shortcut` config for optional per-tool keyboard shortcuts
- "Run Ruff Only" and "Run Pyright Only" menu items that bypass config toggles

### Changed
- Replaced in-memory toggle state with persistent config-based toggles
- "Run Lint" now respects `ruff_enabled` and `pyright_enabled` config settings
- Removed Toggle menu items (replaced by config settings)

## [2.4.0] - 2026-02-25

### Added
- `ruff_select` dropdown setting with rule presets: Default, All, E+W, E+W+F, Custom
- `ruff_line_length` dropdown setting: Default (88), 79 (PEP 8), 88 (Black), 100, 120, Custom
- `pyright_mode` dropdown setting for type checking strictness: Default, Off, Basic, Standard, Strict, All
- Improved settings dialog with dropdown choices for common options

### Changed
- Settings now use dropdown menus for better UX instead of requiring users to type CLI flags

## [2.3.0] - 2026-02-25

### Added
- Per-plugin configuration support via FerrisPad Settings dialog
- `ruff_args` config parameter for extra ruff command-line arguments
- `pyright_args` config parameter for extra pyright command-line arguments

### Changed
- Updated to use FerrisPad 0.9.1 config API (`api:get_config()`)

## [2.2.0] - 2026-02-25

### Added
- Individual tool toggles: Toggle Ruff, Toggle Pyright menu items
- Run specific tool: Run Ruff, Run Pyright menu items
- Improved status messages when tools not found

### Changed
- Refactored to match rust-lint plugin architecture
- Both tools enabled by default, can be toggled independently

## [2.1.0] - 2026-02-24

### Added
- Custom menu item: "Run Lint" (Ctrl+Shift+P) for on-demand linting
- `on_menu_action` hook support for FerrisPad 0.9.1

### Changed
- Updated to use FerrisPad 0.9.1 plugin API with menu_items support

## [2.0.0] - 2025-02-24

### Added
- Pyright integration for type checking
- Auto-detection of project virtual environments (`.venv/`, `venv/`)
- URL extraction from ruff diagnostics for quick reference
- Inline highlights with color coding (red=error, yellow=warning, blue=info)

### Changed
- Replaced mypy with pyright for better performance
- Improved JSON parsing for ruff output (handles nested location fields)
- Updated to use FerrisPad 0.9.0 plugin API

### Fixed
- Fixed parsing of ruff JSON output with complex fix.edits structures

## [1.5.0] - 2025-02-22

### Added
- Initial ruff integration
- Basic mypy support
- Diagnostic panel integration

## [1.0.0] - 2025-02-20

### Added
- Initial release
- Basic Python linting with ruff
