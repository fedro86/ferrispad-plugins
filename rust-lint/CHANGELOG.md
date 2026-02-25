# Changelog

All notable changes to the Rust Lint plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-02-25

### Added
- `clippy_level` dropdown setting with options: Default, Pedantic, All Warnings, Nursery
- `build_profile` dropdown setting: Debug or Release build
- Improved settings dialog with dropdown choices for common options

### Changed
- Settings now use dropdown menus for better UX instead of requiring users to type CLI flags

## [1.1.0] - 2026-02-25

### Added
- Per-plugin configuration support via FerrisPad Settings dialog
- `clippy_args` config parameter for extra clippy command-line arguments
- `build_args` config parameter for extra cargo build command-line arguments

### Changed
- Updated to use FerrisPad 0.9.1 config API (`api:get_config()`)

## [1.0.0] - 2026-02-24

### Added
- Initial release
- Clippy integration for lint warnings
- Cargo build integration for compilation errors
- Individual toggle menu items for each tool
- Run Clippy menu action (Ctrl+Shift+R)
- Run Build menu action
- Cargo.toml project detection
- Documentation URLs for clippy lints (double-click to open)
- Inline highlights with severity colors
- Clear status message when cargo is not installed
