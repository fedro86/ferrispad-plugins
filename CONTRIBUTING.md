# Contributing to FerrisPad Plugins

Thank you for your interest in contributing to FerrisPad's plugin ecosystem!

## Table of Contents

- [Plugin Structure](#plugin-structure)
- [UI Widgets Reference](#ui-widgets-reference)
- [Linter Plugin Guidelines](#linter-plugin-guidelines)
- [Diagnostic Format](#diagnostic-format)
- [Menu Items](#menu-items)
- [Testing Your Plugin](#testing-your-plugin)
- [Submission Checklist](#submission-checklist)

---

## Plugin Structure

Every plugin must include these files:

```
plugin-name/
├── init.lua       # Main plugin logic (required)
├── plugin.toml    # Metadata and permissions (required)
├── README.md      # User documentation (required)
└── CHANGELOG.md   # Version history (required)
```

### plugin.toml

```toml
name = "Plugin Name"
version = "1.0.0"
description = "Short description"

[permissions]
execute = ["tool1", "tool2"]  # Commands this plugin can run

[[menu_items]]
label = "Run Tool"
action = "run_tool"
shortcut = "Ctrl+Shift+X"  # Optional
```

---

## UI Widgets Reference

FerrisPad provides several UI widgets that plugins can use to display information. Understanding these is essential for creating effective linter plugins.

### Widget Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  FerrisPad                                          [─][□][×]   │
├─────────────────────────────────────────────────────────────────┤
│  File  Edit  View  Plugins  Help                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    1 │ import os                    ← Inline Highlight (red)   │
│    2 │ import sys                                               │
│    3 │                                                          │
│    4 │ def main():                                              │
│    5 │     x = 1     ← Inline Highlight (yellow underline)      │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  ⊗ 2 errors  ⚠ 1 warning           ← Diagnostic Panel Header   │
├─────────────────────────────────────────────────────────────────┤
│  ⊗ Line 1: F401: os imported but unused                        │
│  ⊗ Line 2: F401: sys imported but unused    ← Diagnostic List  │
│  ⚠ Line 5: W0612: unused variable 'x'                          │
└─────────────────────────────────────────────────────────────────┘
        ┌──────────────────────────────┐
        │ [Rust Lint] Clippy disabled  │  ← Toast (upper right)
        └──────────────────────────────┘
```

### 1. Toast Notifications (Status Message)

**Location**: Upper-right corner, auto-dismisses after ~3 seconds

**Purpose**: Quick feedback for user actions (toggle, tool not found, etc.)

```lua
return {
    status_message = {
        level = "info",      -- "info" | "warning" | "error"
        text = "[Plugin] message here"
    }
}
```

| Level | Color | Use For |
|-------|-------|---------|
| `info` | Blue | Success, toggle confirmations |
| `warning` | Yellow | Tool not found, all checks disabled |
| `error` | Red | Command failed, permission denied |

**When to use:**
- Tool not installed: `{ level = "warning", text = "[Rust Lint] cargo not found. Install via: rustup.rs" }`
- Toggle feedback: `{ level = "info", text = "[Rust Lint] Clippy disabled" }`
- No project found: `{ level = "info", text = "[Rust Lint] No Cargo.toml found" }`

**When NOT to use:**
- Success with 0 issues (just return empty diagnostics, no toast)
- Linting completed (the diagnostic panel shows results)

### 2. Diagnostic Panel

**Location**: Bottom of editor, collapsible

**Purpose**: Show list of errors/warnings with details

The diagnostic panel has two parts:

#### 2a. Header (Summary Bar)

Shows count of issues by severity with color-coded badges:
```
⊗ 2 errors  ⚠ 3 warnings  ℹ 1 info
```

This is automatically generated from your `diagnostics` array.

#### 2b. Diagnostic List (Detail View)

Each diagnostic shows:
- Icon based on level (⊗ error, ⚠ warning, ℹ info, • hint)
- Line number
- Message text

**Interactions:**
- **Single click**: Jump to that line in editor
- **Double click**: Open documentation URL in browser (if `url` provided)
- **Hover**: Show tooltip with fix suggestion and URL

```lua
return {
    diagnostics = {
        {
            line = 10,                              -- Required: line number
            message = "F401: os imported unused",   -- Required: message text
            level = "error",                        -- Required: error/warning/info/hint
            column = 8,                             -- Optional: column number
            url = "https://docs.astral.sh/...",     -- Optional: double-click opens this
            fix_message = "Remove unused import"    -- Optional: shown in tooltip
        }
    }
}
```

**Tooltip on hover:**
```
Line 10: F401: os imported but unused
Source: Python Lint

Fix: Remove unused import
Docs: https://docs.astral.sh/...  (double-click to open)
```

### 3. Inline Highlights (Editor Annotations)

**Location**: In the editor, on specific lines/columns

**Purpose**: Visual indication of where issues are

```lua
return {
    highlights = {
        {
            line = 10,
            inline = {
                {
                    start_col = 8,       -- 1-indexed, where highlight starts
                    end_col = 15,        -- 1-indexed exclusive, or nil for end of line
                    color = "error"      -- Semantic color name
                }
            }
        }
    }
}
```

**Available Colors:**

| Color Name | Appearance | Use For |
|------------|------------|---------|
| `error` | Red | Compilation errors, syntax errors |
| `warning` | Yellow/Orange | Lint warnings, style issues |
| `info` | Blue | Informational highlights |
| `hint` | Gray | Notes, suggestions |
| `added` | Green | Git: added lines |
| `modified` | Yellow | Git: modified lines |
| `deleted` | Red | Git: deleted lines |

**Shorthand for linter highlights:**

```lua
local highlights = {}
for _, d in ipairs(diagnostics) do
    local color = d.level == "error" and "error"
                  or (d.level == "warning" and "warning" or "info")
    table.insert(highlights, {
        line = d.line,
        inline = {{ start_col = d.column or 1, end_col = nil, color = color }}
    })
end
```

### 4. Gutter Marks (Full-Line Background)

**Location**: Left gutter + full line background

**Purpose**: Mark entire lines (used for git diff, code coverage)

```lua
return {
    highlights = {
        {
            line = 10,
            gutter = { color = "added" },  -- Full line green background
            inline = {}
        }
    }
}
```

**Note**: For linters, inline highlights are usually preferred over gutter marks.

### Complete Return Structure

```lua
return {
    -- Diagnostics → Diagnostic Panel
    diagnostics = {
        { line = 10, message = "...", level = "error", column = 5, url = "...", fix_message = "..." }
    },

    -- Highlights → Editor inline colors
    highlights = {
        { line = 10, inline = {{ start_col = 5, end_col = 20, color = "error" }} }
    },

    -- Status Message → Toast notification (upper right)
    status_message = {
        level = "warning",
        text = "[Plugin] Tool not found"
    }
}
```

### Widget Decision Tree

```
Is there feedback for the user?
├── Yes, linting results
│   └── Return `diagnostics` array + `highlights` array
│       (Diagnostic panel + editor highlights)
│
├── Yes, something went wrong
│   └── Return `status_message` with level="warning" or "error"
│       (Toast notification)
│
├── Yes, user action confirmed (toggle)
│   └── Return `status_message` with level="info"
│       (Toast notification)
│
└── No issues found
    └── Return empty `diagnostics` and `highlights`
        (Clears panel, no toast needed)
```

---

## Linter Plugin Guidelines

Linter plugins integrate external tools (ruff, clippy, eslint, etc.) with FerrisPad's diagnostic system. Follow these guidelines to ensure consistency across all linter plugins.

### 1. Tool Detection

**Check if required tools are installed before running:**

```lua
function M.on_document_lint(api, path, content)
    -- Check file extension first
    if api:get_file_extension() ~= "py" then
        return { diagnostics = {}, highlights = {} }
    end

    -- Check if tool is available
    if not api:command_exists("ruff") then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Plugin] ruff not found. Install via: pip install ruff" } }
    end

    -- Continue with linting...
end
```

**Provide helpful installation instructions** in the status message.

### 2. Project Detection

**Detect project context before running tools:**

| Language | Project Indicator | Example Detection |
|----------|-------------------|-------------------|
| Python | `pyproject.toml`, `.venv/`, `venv/` | Look for venv in current/parent dirs |
| Rust | `Cargo.toml` | Look in current/parent dirs |
| JavaScript | `package.json`, `node_modules/` | Look for node_modules |
| Go | `go.mod` | Look in current/parent dirs |

```lua
local function is_project(api, marker_file)
    local file_dir = api:get_file_dir()
    if file_dir then
        local dirs = { file_dir, file_dir .. "/..", file_dir .. "/../.." }
        for _, dir in ipairs(dirs) do
            if api:file_exists(dir .. "/" .. marker_file) then
                return true
            end
        end
    end
    return false
end
```

### 3. Environment Detection (Language-Specific)

**Python**: Detect virtual environments

```lua
local function find_command(api, cmd_name)
    local file_dir = api:get_file_dir()
    if file_dir then
        local venv_paths = {
            file_dir .. "/.venv/bin/" .. cmd_name,
            file_dir .. "/venv/bin/" .. cmd_name,
            file_dir .. "/../.venv/bin/" .. cmd_name,
        }
        for _, p in ipairs(venv_paths) do
            if api:file_exists(p) then
                return p
            end
        end
    end
    if api:command_exists(cmd_name) then
        return cmd_name
    end
    return nil
end
```

**Rust/Go/etc**: Tools are globally installed, just check PATH.

### 4. JSON Output Parsing

**Always request JSON output from tools when available:**

| Tool | JSON Flag |
|------|-----------|
| ruff | `--output-format=json` |
| pyright | `--outputjson` |
| clippy | `--message-format=json` |
| eslint | `--format=json` |
| golangci-lint | `--out-format=json` |

**Parse line by line** for tools that output newline-delimited JSON:

```lua
for line in json_output:gmatch("[^\r\n]+") do
    -- Parse each JSON object
end
```

### 5. Diagnostic Levels

Map tool-specific levels to FerrisPad levels:

| FerrisPad Level | Use For |
|-----------------|---------|
| `error` | Compilation errors, syntax errors, type errors |
| `warning` | Lint warnings, style issues, unused code |
| `info` | Informational messages, suggestions |
| `hint` | Help messages, notes |

```lua
local function map_level(tool_level)
    if tool_level == "error" then return "error"
    elseif tool_level == "warning" then return "warning"
    elseif tool_level == "note" or tool_level == "help" then return "hint"
    else return "info"
    end
end
```

### 6. Documentation URLs

**Provide documentation links when possible:**

```lua
-- Clippy lints
url = "https://rust-lang.github.io/rust-clippy/master/index.html#" .. lint_code

-- Ruff rules
url = "https://docs.astral.sh/ruff/rules/" .. rule_code

-- ESLint rules
url = "https://eslint.org/docs/rules/" .. rule_code
```

Users can double-click diagnostics to open these URLs.

### 7. Individual Tool Toggles

**Allow users to enable/disable each tool independently:**

```lua
local tool1_enabled = true
local tool2_enabled = true

function M.on_menu_action(api, action, path, content)
    if action == "toggle_tool1" then
        tool1_enabled = not tool1_enabled
        local state = tool1_enabled and "enabled" or "disabled"
        return { status_message = { level = "info", text = "[Plugin] Tool1 " .. state } }
    end
end
```

**Note**: Toggle state is in-memory and resets on restart (acceptable limitation).

### 8. Menu Structure

Every linter plugin should have these menu items:

```toml
[[menu_items]]
label = "Run All"           # Run all enabled tools
action = "run_all"
shortcut = "Ctrl+Shift+X"   # Language-specific shortcut

[[menu_items]]
label = "Run Tool1"         # Run specific tool only
action = "run_tool1"

[[menu_items]]
label = "Run Tool2"
action = "run_tool2"

[[menu_items]]
label = "Toggle Tool1"      # Enable/disable tool
action = "toggle_tool1"

[[menu_items]]
label = "Toggle Tool2"
action = "toggle_tool2"
```

### 9. Status Messages

**Always provide feedback to users:**

| Situation | Message Type | Example |
|-----------|--------------|---------|
| Tool not found | `warning` | `[Plugin] ruff not found. Install via: pip install ruff` |
| No project found | `info` | `[Plugin] No pyproject.toml found` |
| All checks disabled | `warning` | `[Plugin] All checks disabled` |
| Success (0 issues) | None | Don't show a message, just clear diagnostics |

### 10. Line Highlights

**Generate inline highlights for each diagnostic:**

```lua
local highlights = {}
for _, d in ipairs(diagnostics) do
    local color = d.level == "error" and "error"
                  or (d.level == "warning" and "warning" or "info")
    table.insert(highlights, {
        line = d.line,
        inline = {{ start_col = d.column or 1, end_col = nil, color = color }}
    })
end
```

---

## Diagnostic Format

Return diagnostics in this format:

```lua
return {
    diagnostics = {
        {
            line = 10,                    -- Required: 1-indexed line number
            message = "E401: unused import", -- Required: diagnostic message
            level = "error",              -- Required: error/warning/info/hint
            column = 5,                   -- Optional: 1-indexed column
            url = "https://...",          -- Optional: documentation URL
            fix_message = "Remove import" -- Optional: suggested fix
        }
    },
    highlights = {...},                   -- Line highlights
    status_message = {                    -- Optional: toast notification
        level = "warning",
        text = "[Plugin] message"
    }
}
```

---

## Menu Items

Keyboard shortcut conventions:

| Language | Run All Shortcut |
|----------|------------------|
| Python | `Ctrl+Shift+P` |
| Rust | `Ctrl+Shift+R` |
| JavaScript | `Ctrl+Shift+J` |
| Go | `Ctrl+Shift+G` |

---

## Testing Your Plugin

1. **Symlink for development:**
   ```bash
   ln -s /path/to/your/plugin ~/.config/ferrispad/plugins/your-plugin
   ```

2. **Test scenarios:**
   - [ ] Tool not installed - shows helpful message
   - [ ] No project file - shows info message
   - [ ] File with errors - shows diagnostics
   - [ ] Clean file - clears diagnostics
   - [ ] Toggle tools - shows confirmation toast
   - [ ] Run individual tool - runs only that tool
   - [ ] Double-click diagnostic - opens docs URL

3. **Check logs:**
   Run FerrisPad from terminal to see `api:log()` output.

---

## Submission Checklist

Before submitting a pull request:

- [ ] `init.lua` - Main plugin logic
- [ ] `plugin.toml` - Metadata with permissions and menu items
- [ ] `README.md` - Installation and usage instructions
- [ ] `CHANGELOG.md` - Version history
- [ ] Tool detection with helpful error messages
- [ ] Project/environment detection appropriate for the language
- [ ] JSON output parsing
- [ ] Individual tool toggles
- [ ] Documentation URLs (if available)
- [ ] Tested all menu actions
- [ ] Updated `plugins.json` registry
- [ ] Updated main `README.md` available plugins table

---

## Questions?

Open an issue at [ferrispad-plugins](https://github.com/fedro86/ferrispad-plugins/issues) or check the [FerrisPad Plugin API Documentation](https://github.com/fedro86/ferrispad/blob/main/docs/temp/0.9.1/07_DIAGNOSTIC_PANEL_ENHANCEMENTS.md).
