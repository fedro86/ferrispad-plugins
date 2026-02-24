# Python Lint Plugin for FerrisPad

A linting plugin that integrates **ruff** and **pyright** for Python files.

## Features

- Real-time linting on document save/lint trigger
- Supports both ruff (fast linting) and pyright (type checking)
- Automatic venv detection (looks for `.venv/` or `venv/` in project)
- Diagnostics displayed in the editor with inline highlights
- Error/warning/info severity levels with color coding

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

- Plugin version: 2.0.0
- Requires FerrisPad 0.9.0+
