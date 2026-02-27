# Changelog

All notable changes to the File Explorer plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-02-27

### Added
- **Plugin-defined context menus**: Right-click files, folders, or empty area for contextual actions
  - Files: Open, Copy Path, Rename, Delete
  - Folders: New File, New Folder, Copy Path, Rename, Delete
  - Empty area: New File, New Folder, Refresh
- **Refresh button** in tree panel header (re-scans same folder without changing project root)
- New file permissions: `touch`, `mkdir`, `mv`, `rm` for file management actions

### Changed
- Context menu items are now declared by the plugin via the `context_menu` API (no longer hardcoded in FerrisPad)

## [0.2.1] - 2026-02-27

### Fixed
- File opening now uses `check.success` instead of `check.exit_code` (matching the API)
- Double-click required to open files (prevents accidental opens when browsing)
- Enter key opens the selected file

### Added
- Debug logging for file path resolution

## [0.2.0] - 2026-02-26

### Fixed
- File opening: added missing `on_click` handler to tree_view return, fixing silent click ignoring
- Extensionless files (Makefile, Dockerfile, LICENSE) now open correctly via `test -f` check

### Added
- Configurable panel position: Left, Right, or Bottom (via Settings dropdown, requires restart)
- `test` command permission for file type detection

## [0.1.0] - 2026-02-26

### Added
- Initial release
- Tree view panel showing project files and folders
- Click-to-open files in the editor
- "Show File Explorer" menu action (Ctrl+Shift+E)
- "Refresh Explorer" menu action
- `show_hidden_files` configuration toggle
- Smart filtering of noise directories (.git, node_modules, target, __pycache__, .venv, etc.)
- Sorted tree: directories first, then files, both alphabetical
- Security validation for file open requests (path must be within project root)
