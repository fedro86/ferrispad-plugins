# Python Lint Plugin for FerrisPad

A linting plugin that integrates **ruff** and **pyright** for Python files.

## Features

- Real-time linting on document save/lint trigger
- Supports both ruff (fast linting) and pyright (type checking)
- Automatic venv detection (looks for `.venv/` or `venv/` in project)
- Diagnostics displayed in the editor with inline highlights
- Error/warning/info severity levels with color coding
- **Dropdown Settings**: Easy configuration with preset options

## Requirements

You need to install **ruff** and/or **pyright** in your project's virtual environment or globally.

### Option 1: Project Virtual Environment (Recommended)

```bash
# Create a virtual environment in your project
cd /path/to/your/python/project
python -m venv .venv

# Activate it
source .venv/bin/activate  # Linux/macOS
# or: .venv\Scripts\activate  # Windows

# Install linters
pip install ruff pyright
```

### Option 2: Global Installation

```bash
pip install ruff pyright
# or with pipx:
pipx install ruff
pipx install pyright
```

## Installation

Copy the `python-lint` folder to your FerrisPad plugins directory:

```bash
cp -r python-lint ~/.config/ferrispad/plugins/
```

## Behavior

### When Linting Runs

- On `on_document_lint` hook (triggered by save or manual lint command)
- On `on_highlight_request` hook

### What Happens

1. The plugin checks if the file has a `.py` extension
2. It searches for ruff/pyright in this order:
   - `<file_dir>/.venv/bin/ruff`
   - `<file_dir>/venv/bin/ruff`
   - `<file_dir>/../.venv/bin/ruff`
   - `<file_dir>/../venv/bin/ruff`
   - System PATH
3. Runs the found linters with JSON output
4. Parses diagnostics and returns them to FerrisPad

### Diagnostic Levels

| Linter | Code Pattern | Level |
|--------|-------------|-------|
| ruff | `F*` (Pyflakes) | error |
| ruff | `E*` (pycodestyle errors) | error |
| ruff | `invalid-syntax` | error |
| ruff | Other | warning |
| pyright | severity=error | error |
| pyright | severity=warning | warning |
| pyright | Other | info |

### Output

Diagnostics are shown with:
- **Line number** and **column** position
- **Message** with error code prefix
- **Inline highlights** in the editor (red for errors, yellow for warnings)

## Menu Actions

- **Plugins > Python Lint > Run Lint** (Ctrl+Shift+P): Run all enabled linters
- **Plugins > Python Lint > Run Ruff Only**: Run ruff regardless of config
- **Plugins > Python Lint > Run Pyright Only**: Run pyright regardless of config
- **Plugins > Python Lint > Settings...**: Configure plugin options

## Configuration

Access plugin settings via **Plugins > Python Lint > Settings...** in FerrisPad.

### Tool Toggles

| Parameter | Description | Default |
|-----------|-------------|---------|
| Run Ruff | Enable/disable ruff when running "Run Lint" | Enabled |
| Run Pyright | Enable/disable pyright when running "Run Lint" | Enabled |

### Optional Shortcuts

| Parameter | Description | Default |
|-----------|-------------|---------|
| Ruff Shortcut | Keyboard shortcut for "Run Ruff Only" | (none) |
| Pyright Shortcut | Keyboard shortcut for "Run Pyright Only" | (none) |

### Dropdown Settings

| Parameter | Options | Default |
|-----------|---------|---------|
| Ruff Rule Selection | Default, All Rules, E+W, E+W+F, Custom | Default |
| Ruff Line Length | Default (88), 79 (PEP 8), 88 (Black), 100, 120, Custom | Default |
| Pyright Type Checking Mode | Default, Off, Basic, Standard, Strict, All | Default |

### Text Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| Extra Ruff Arguments | Additional CLI flags for ruff | (empty) |
| Extra Pyright Arguments | Additional CLI flags for pyright | (empty) |

### Examples

**Extra Ruff Arguments:**
- `--ignore=E501` - Ignore specific rules
- `--fix` - Apply auto-fixes

**Extra Pyright Arguments:**
- `--pythonversion=3.11` - Specify Python version

Settings are saved in FerrisPad's configuration and persist across plugin updates.

## Troubleshooting

### No Linters Found

If you see `[Python Lint] No linters found`:
- Ensure ruff or pyright is installed
- Check that the venv is in the expected location (`.venv/` or `venv/`)
- Try installing globally: `pip install ruff pyright`

### Linters Not Running

Check FerrisPad logs for debug output:
- `Found ruff in venv: ...` - shows which ruff was found
- `ruff: code=... row=... msg=...` - shows parsed diagnostics
- `Total: N diagnostics` - summary of findings

## Version

- Plugin version: 2.5.0
- Requires FerrisPad 0.9.1+
