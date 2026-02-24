# Changelog

All notable changes to the Python Lint plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
