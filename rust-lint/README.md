# Rust Lint Plugin for FerrisPad

Run `cargo clippy` and `cargo build` diagnostics directly in FerrisPad.

## Features

- **Clippy Integration**: Lint warnings, style suggestions, correctness checks
- **Build Check**: Compilation error detection
- **Individual Toggles**: Enable/disable each tool independently
- **Documentation Links**: Double-click clippy warnings to open docs

## Requirements

You need the Rust toolchain installed via [rustup](https://rustup.rs/):

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Add clippy component (usually included by default)
rustup component add clippy
```

**No project-local setup needed!** Unlike Python with virtual environments, Rust tools are installed globally via rustup.

## Installation

Copy the `rust-lint` folder to your FerrisPad plugins directory:

```bash
cp -r rust-lint ~/.config/ferrispad/plugins/
```

## Usage

### Automatic (on save)

Save any `.rs` file in a project with `Cargo.toml` - diagnostics appear automatically.

### Manual

- **Plugins > Rust Lint > Run Clippy** (Ctrl+Shift+R): Run clippy only
- **Plugins > Rust Lint > Run Build**: Run cargo build only

### Configuration

- **Plugins > Rust Lint > Toggle Clippy**: Enable/disable clippy on save
- **Plugins > Rust Lint > Toggle Build**: Enable/disable build check on save

## Diagnostic Display

| Level | Source | Example |
|-------|--------|---------|
| Error | `[build]` | Compilation errors, type mismatches |
| Warning | `[clippy]` | Unused variables, style suggestions |
| Hint | Both | Help messages, fix suggestions |

## Behavior

### When Linting Runs

- On `on_document_lint` hook (triggered by save or manual lint command)
- On `on_highlight_request` hook (Ctrl+Shift+L)

### What Happens

1. The plugin checks if the file has a `.rs` extension
2. It searches for `Cargo.toml` in:
   - Current directory
   - Up to 3 parent directories
3. Runs the enabled tools with JSON output
4. Parses diagnostics and returns them to FerrisPad

### Diagnostic Levels

| Tool | Level | Description |
|------|-------|-------------|
| clippy/build | error | Compilation errors |
| clippy/build | warning | Lint warnings |
| clippy/build | hint | Help/note messages |

## Comparison with Python Lint

| Feature | Python Lint | Rust Lint |
|---------|-------------|-----------|
| Environment | `.venv/` detection | Global rustup |
| Tools | ruff, pyright | clippy, cargo build |
| Config | pyproject.toml | Cargo.toml |
| Detection | Looks for venv in parent dirs | Looks for Cargo.toml |

## Troubleshooting

### No Cargo.toml Found

- Ensure you're editing a `.rs` file inside a Cargo project
- The plugin searches up to 3 parent directories for `Cargo.toml`

### Cargo Not Found

- Install Rust via rustup: https://rustup.rs/
- Ensure `~/.cargo/bin` is in your PATH
- Try: `source ~/.cargo/env` if just installed

### Clippy Not Found

```bash
rustup component add clippy
```

## Version

- Plugin version: 1.0.0
- Requires FerrisPad 0.9.1+
