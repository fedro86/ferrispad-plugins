# File Explorer Plugin for FerrisPad

Browse your project directory as a tree view directly in FerrisPad.

## Features

- **Tree View**: Shows project files and folders in a collapsible tree panel
- **Double-Click to Open**: Double-click any file to open it in the editor (including extensionless files like Makefile, LICENSE). Press Enter to open the selected file.
- **Context Menu**: Right-click files, folders, or empty area for contextual actions (New File, New Folder, Rename, Delete, Copy Path, Refresh)
- **File Management**: Create, rename, and delete files and folders directly from the tree
- **Configurable Position**: Show the explorer on the Left, Right, or Bottom (via plugin settings)
- **Hidden Files Toggle**: Show/hide dotfiles via plugin settings
- **Smart Filtering**: Automatically skips noise directories (`.git`, `node_modules`, `target`, `__pycache__`, `.venv`, etc.)
- **Refresh**: Re-scan the project directory via context menu, header button, or menu action

## Requirements

The following commands must be available (pre-installed on Linux and macOS):
- `find`, `test` — directory scanning and file type detection
- `touch`, `mkdir`, `mv`, `rm` — file management (create, rename, delete)

## Installation

Copy the `file-explorer` folder to your FerrisPad plugins directory:

```bash
cp -r file-explorer ~/.config/ferrispad/plugins/
```

## Usage

### Menu Actions

- **Plugins > file-explorer > Show File Explorer** (Ctrl+Shift+E): Scan and display the project tree
- **Plugins > file-explorer > Refresh Explorer**: Re-scan and update the tree
- **Plugins > file-explorer > Settings...**: Configure plugin options

### Context Menu (Right-Click)

| Target | Actions |
|--------|---------|
| **File** | Open, Copy Path, Rename, Delete |
| **Folder** | New File, New Folder, Copy Path, Rename, Delete |
| **Empty area** | New File, New Folder, Refresh |

### Opening Files

Double-click on any file node in the tree view to open it in the editor. You can also select a file and press Enter, or use "Open" from the right-click context menu. Directory nodes expand/collapse on single click.

## Configuration

Access plugin settings via **Plugins > file-explorer > Settings...** in FerrisPad.

| Parameter | Description | Default |
|-----------|-------------|---------|
| Show Hidden Files | Include dotfiles and dot-directories in the tree | Disabled |
| Panel Position | Where to display the explorer: Left, Right, or Bottom | Left |

**Note:** Changing the panel position requires restarting FerrisPad.

## Behavior

### How It Works

1. The plugin detects the project root from the current document (uses `.git`, `Cargo.toml`, `package.json`, etc. as markers)
2. Runs `find` with a max depth of 5 levels to list files and directories
3. Filters out noise directories and (optionally) hidden files
4. Builds a nested tree: folders first (alphabetical), then files (alphabetical)
5. Displays the tree in FerrisPad's tree view panel

### Security

File open requests are validated against the project root using FerrisPad's path security system. Symlinks are resolved and checked. Files outside the project root are blocked.

### Filtered Directories

These directories are always excluded from the tree:

| Directory | Reason |
|-----------|--------|
| `.git` | Version control internals |
| `node_modules` | JavaScript dependencies |
| `target` | Rust build output |
| `__pycache__` | Python bytecode cache |
| `.venv` / `venv` | Python virtual environments |
| `.mypy_cache` | mypy type checker cache |
| `.pytest_cache` | pytest cache |
| `.tox` | tox testing environments |
| `dist` / `build` | Build output directories |
| `.eggs` / `.cache` | Miscellaneous caches |

### Filtered File Extensions

These file types are excluded:

- `*.pyc` - Python compiled bytecode
- `*.o` - Object files
- `*.so` - Shared libraries

## Troubleshooting

### No Project Root Found

- Open a file that belongs to a project (one with `.git`, `Cargo.toml`, `package.json`, etc.)
- The plugin cannot scan without a project root

### Tree Is Empty

- Check that the project has files within 5 directory levels
- If hidden files are expected, enable "Show Hidden Files" in settings

### File Won't Open on Click

- Ensure the file exists and is a regular file (not a directory)
- Directory nodes expand/collapse instead of opening

## Version

- Plugin version: 0.3.0
- Requires FerrisPad 0.9.1+
