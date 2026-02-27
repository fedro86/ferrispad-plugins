# Contributing to FerrisPad Plugins

Thank you for your interest in contributing to FerrisPad's plugin ecosystem!

## Table of Contents

- [Plugin Structure](#plugin-structure)
- [Plugin Configuration](#plugin-configuration)
- [UI Widgets Reference](#ui-widgets-reference)
- [Linter Plugin Guidelines](#linter-plugin-guidelines)
- [Diagnostic Format](#diagnostic-format)
- [Menu Items](#menu-items)
- [Testing Your Plugin](#testing-your-plugin)
- [Plugin Verification & Signing](#plugin-verification--signing)
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

## Plugin Configuration

Plugins can define configurable parameters that users can edit via `Plugins → {Plugin Name} → Settings...`. Configuration values are stored in FerrisPad's `settings.json` and persist across plugin updates.

### Defining Config Parameters in plugin.toml

Add a `[config]` section with `[[config.params]]` entries:

```toml
[config]
[[config.params]]
key = "extra_args"
label = "Extra Arguments"
type = "string"
default = ""
placeholder = "--verbose"

[[config.params]]
key = "max_line_length"
label = "Max Line Length"
type = "number"
default = "88"

[[config.params]]
key = "auto_fix"
label = "Auto-fix on Save"
type = "boolean"
default = "false"

[[config.params]]
key = "output_format"
label = "Output Format"
type = "choice"
options = ["json|JSON Format", "text|Plain Text", "markdown|Markdown"]
default = "json"
```

| Field | Required | Description |
|-------|----------|-------------|
| `key` | Yes | Identifier used in `api:get_config(key)` |
| `label` | Yes | Display name shown in Settings dialog |
| `type` | Yes | `"string"`, `"number"`, `"boolean"`, or `"choice"` |
| `default` | Yes | Default value (always a string) |
| `placeholder` | No | Hint text shown in empty input fields |
| `options` | No | Required for `choice` type. Array of `"value"` or `"value|Label"` strings |
| `validate` | No | Validation rule: `"cli_args"` or `"regex:PATTERN"` |

### Choice Type Options Format

For `choice` type parameters, options can be specified in two formats:

1. **Simple**: `"value"` - The value is used as both the stored value and display label
2. **With label**: `"value|Display Label"` - The value before `|` is stored, the label after `|` is shown in UI

Example:
```toml
[[config.params]]
key = "lint_level"
label = "Lint Strictness"
type = "choice"
options = ["default|Default", "warn|Warnings Only", "strict|Strict Mode"]
default = "default"
```

When the user selects "Warnings Only", the value `"warn"` is stored and returned by `api:get_config("lint_level")`.

### Validation Rules

Use the `validate` field to add input validation:

#### `cli_args` - CLI Argument Validation

Blocks shell metacharacters that could enable command injection:
```toml
[[config.params]]
key = "extra_args"
label = "Extra Arguments"
type = "string"
default = ""
validate = "cli_args"
```

Blocked characters: `; & | $ \` ( ) { } < > \n \r \ " ' ! * ? [ ] # ~ ^`

**Always use `validate = "cli_args"` for parameters that will be passed to command-line tools.**

#### `regex:PATTERN` - Regex Validation

Validates input against a regex pattern:
```toml
[[config.params]]
key = "version"
label = "Python Version"
type = "string"
default = "3.11"
validate = "regex:^[0-9]+\\.[0-9]+$"
```

### Reading Config Values in Lua

Use the `api:get_config()` family of methods:

```lua
-- Get string value (returns nil if not set)
local args = api:get_config("extra_args") or ""

-- Get number value (returns nil if not a valid number)
local max_len = api:get_config_number("max_line_length") or 88

-- Get boolean value (returns false if not set or not "true")
local auto_fix = api:get_config_bool("auto_fix")
```

### Example: Using Config in a Linter

```lua
local function run_tool(api, path)
    local args = {"check", path}

    -- Append extra arguments from config
    local extra_args = api:get_config("extra_args") or ""
    if extra_args ~= "" then
        for arg in extra_args:gmatch("%S+") do
            table.insert(args, arg)
        end
    end

    local result = api:run_command("tool", table.unpack(args))
    -- ...
end
```

### User Experience

1. Users access config via `Plugins → {Plugin} → Settings...`
2. A dialog appears with dynamic fields based on `[[config.params]]` definitions
3. Values are saved to `~/.config/ferrispad/settings.json`
4. Config persists across FerrisPad restarts and plugin updates
5. Keyboard shortcuts are managed centrally via `Edit → Key Shortcuts...`

### Best Practices

- **Use sensible defaults**: The plugin should work without any configuration
- **Document parameters**: Explain what each parameter does in your README
- **Validate at runtime**: Handle invalid config values gracefully
- **Keep it simple**: Only expose parameters that users actually need to change

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
    },

    -- Modified Content → Replace editor buffer contents
    modified_content = "new file content here",

    -- Split View → Side-by-side comparison panel
    split_view = {
        title = "Diff View",
        left = {
            content = "original text",
            label = "Original",
            line_numbers = true,
            highlights = {
                { line = 1, color = "removed" }
            }
        },
        right = {
            content = "modified text",
            label = "Modified",
            line_numbers = true,
            highlights = {
                { line = 1, color = "added" }
            }
        },
        actions = {
            { label = "Accept", action = "accept" },
            { label = "Reject", action = "reject" }
        }
    },

    -- Tree View → Collapsible tree panel (e.g., file explorer, outline)
    tree_view = {
        title = "Project Files",
        root = {
            label = "src",
            icon = "folder",
            children = {
                { label = "main.rs", icon = "file", data = "/path/to/main.rs" },
                { label = "lib.rs", icon = "file", data = "/path/to/lib.rs" }
            }
        },
        expand_depth = 1,          -- levels to auto-expand (0 = none, -1 = all)
        on_click = "node_clicked", -- action name sent to on_widget_action
        click_mode = "double"      -- "single" or "double" (default: "double")
    },

    -- Open File → Request FerrisPad to open a file in the editor
    open_file = "/absolute/path/to/file.rs",

    -- Clipboard Text → Copy a string to the system clipboard
    clipboard_text = "text to copy",

    -- Go To Line → Navigate the editor cursor to a line (1-indexed)
    goto_line = 42
}
```

All fields are optional — return only the ones your plugin needs.

### 5. Split View

**Location**: Bottom panel, side-by-side panes

**Purpose**: Show comparisons (diffs, AI suggestions, before/after)

The `on_widget_action` hook is called when the user clicks an action button:

```lua
function M.on_widget_action(api, widget_type, action, session_id, data)
    if widget_type == "split_view" and action == "accept" then
        -- data.right_content contains the right pane text
        return { modified_content = data.right_content }
    end
    return {}
end
```

**Highlight colors**: `"added"` (green), `"removed"` (red), `"modified"` (yellow)

### 6. Tree View

**Location**: Left/right/bottom panel (configurable in settings), collapsible tree

**Purpose**: Show hierarchical data (file browsers, outlines, YAML viewers)

**Tree view request fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `title` | No | Header title (default: "Tree View") |
| `root` | Yes* | Root tree node (*or use `yaml_content`) |
| `yaml_content` | No | YAML string to parse into a tree (alternative to `root`) |
| `on_click` | No | Action name sent to `on_widget_action` when a node is activated |
| `expand_depth` | No | Levels to auto-expand: 0 = none, -1 = all (default: 1) |
| `click_mode` | No | `"single"` or `"double"` (default: `"double"`). Use `"single"` for YAML/JSON viewers, `"double"` for file explorers |
| `context_path` | No | Base directory path used to resolve node paths for context menu actions (e.g., project root) |
| `context_menu` | No | Array of context menu item tables (see [Context Menu Items](#context-menu-items) below) |

**Each tree node supports:**

| Field | Required | Description |
|-------|----------|-------------|
| `label` | Yes | Display text for the node |
| `icon` | No | Icon hint: `"file"`, `"folder"`, `"error"`, etc. |
| `data` | No | Arbitrary string payload (e.g., file path) |
| `children` | No | Array of child nodes (presence makes it a branch) |
| `expanded` | No | Whether the node starts expanded (default: false) |

The `on_widget_action` hook is called when the user activates a node (single-click or double-click depending on `click_mode`) or selects a context menu action. `api:get_text()` is available in this hook (the current document's content is read automatically from the file path):

```lua
function M.on_widget_action(api, widget_type, action, session_id, data)
    if widget_type == "tree_view" and action == "node_clicked" then
        -- data.node_path is an array of labels from root to clicked node
        -- e.g., {"src", "app", "state.rs"}
        local file = reconstruct_path(data.node_path)
        return { open_file = file }
        -- Or navigate to a line: return { goto_line = 42 }
    end
    return {}
end
```

**`data` fields for tree view actions:**

| Field | Description |
|-------|-------------|
| `data.node_path` | Array of labels from root to the clicked/right-clicked node |
| `data.input_text` | User's input from an input dialog (only present for `input`-type context menu items) |

#### Context Menu Items

Plugins can define right-click context menus for tree view nodes. Each item specifies which node types it appears for and what happens when clicked.

**Context menu item fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `label` | Yes | Display text (e.g., `"New File..."`, `"Delete"`) |
| `action` | No* | Action name sent to `on_widget_action` (*required unless `clipboard = true`) |
| `target` | No | Node type filter: `"folder"`, `"file"`, `"empty"`, `"all"` (default: `"all"`) |
| `input` | No | If set, show an input dialog with this prompt before sending the action |
| `confirm` | No | If set, show a confirmation dialog with this message before sending |
| `prefill_name` | No | If `true`, pre-fill the input dialog with the current node name (for rename) |
| `clipboard` | No | If `true`, copy the node's full path to clipboard (built-in, no action sent to plugin) |

**Target types:**

| Target | When shown |
|--------|------------|
| `"file"` | Right-click on a leaf node (file) |
| `"folder"` | Right-click on a branch node (folder) |
| `"empty"` | Right-click on empty area (no node) |
| `"all"` | Always shown regardless of click target |

**Three item behaviors:**

1. **Plain action** — Click sends the action to the plugin immediately
2. **Input action** (`input` field set) — Click shows an input dialog; user's text is sent as `data.input_text`
3. **Confirm action** (`confirm` field set) — Click shows a confirmation dialog; action sent only if confirmed

**Example:**

```lua
return {
    tree_view = {
        title = "Project Files",
        root = root_node,
        context_path = project_root,
        on_click = "node_clicked",
        context_menu = {
            -- Folder items
            { label = "New File...",   action = "new_file",   target = "folder", input = "New file name:" },
            { label = "New Folder...", action = "new_folder", target = "folder", input = "New folder name:" },
            { label = "Copy Path",    target = "folder", clipboard = true },
            { label = "Rename...",    action = "rename",     target = "folder", input = "Rename to:", prefill_name = true },
            { label = "Delete",       action = "delete",     target = "folder", confirm = "Delete this folder?" },

            -- File items
            { label = "Open",         action = "node_clicked", target = "file" },
            { label = "Copy Path",    target = "file", clipboard = true },
            { label = "Rename...",    action = "rename",     target = "file", input = "Rename to:", prefill_name = true },
            { label = "Delete",       action = "delete",     target = "file", confirm = "Delete this file?" },

            -- Empty area items
            { label = "Refresh",      action = "refresh",    target = "empty" },
        }
    }
}
```

**Handling context menu actions in `on_widget_action`:**

```lua
function M.on_widget_action(api, widget_type, action, session_id, data)
    if widget_type == "tree_view" then
        if action == "new_file" and data.input_text then
            -- data.node_path = path segments to the right-clicked folder
            -- data.input_text = user's input from the dialog
            local parent = resolve_path(data.node_path)
            api:run_command("touch", parent .. "/" .. data.input_text)
            return refresh_tree()
        elseif action == "rename" and data.input_text then
            local old_path = resolve_path(data.node_path)
            local new_path = parent_dir(old_path) .. "/" .. data.input_text
            api:run_command("mv", old_path, new_path)
            return refresh_tree()
        elseif action == "delete" then
            local target_path = resolve_path(data.node_path)
            api:run_command("rm", "-rf", target_path)
            return refresh_tree()
        end
    end
    return {}
end
```

Alternatively, use `yaml_content` instead of `root` to display parsed YAML as a tree:

```lua
return {
    tree_view = {
        title = "Config",
        yaml_content = "key: value\nnested:\n  child: 1"
    }
}
```

### 7. Open File

**Purpose**: Request FerrisPad to open a file in the editor

```lua
return { open_file = "/absolute/path/to/file.rs" }
```

**Security**: The path is validated against the project root. Files outside the project root are blocked. Symlinks are resolved before validation.

### 8. Modified Content

**Purpose**: Replace the current editor buffer contents (e.g., formatting, auto-fix)

```lua
return { modified_content = "new file content" }
```

Use this from `on_menu_action` or `on_widget_action` (e.g., accepting a split view suggestion).

### 9. Clipboard Text

**Purpose**: Copy a string to the system clipboard

```lua
return { clipboard_text = "text to copy" }
```

Use this from `on_widget_action` to copy values from tree nodes, or from any hook that needs to put text on the clipboard. Unlike the `clipboard = true` context menu field (which copies the filesystem path), `clipboard_text` lets you copy arbitrary text.

### 10. Go To Line

**Purpose**: Navigate the editor cursor to a specific line number (1-indexed)

```lua
return { goto_line = 42 }
```

Use this from `on_widget_action` to jump to a line when the user clicks a tree node. For example, a YAML tree viewer can search the document text for the clicked key and return the matching line number:

```lua
elseif action == "node_clicked" then
    local text = api:get_text()
    if not text then return nil end
    local key = extract_key(node_path)
    local line_num = find_key_line(text, key)
    if line_num then
        return { goto_line = line_num }
    end
end
```

**Note**: `api:get_text()` is available in `on_widget_action` — the file content is read automatically from the current document path.

### 11. Returning Values from `on_document_open`

The `on_document_open` hook can return the same result table as other hooks. This enables auto-displaying widgets when a file is opened:

```lua
function M.on_document_open(api, path)
    if should_show_tree(path) then
        local content = api:get_text()  -- file content is available
        return {
            tree_view = {
                title = "My Viewer",
                yaml_content = content,
                expand_depth = 2,
                click_mode = "single"
            }
        }
    end
    return nil  -- returning nil skips this plugin
end
```

**Note**: `api:get_text()` returns the file content in `on_document_open` (the file is read automatically). The `path` parameter is also passed as a separate argument.

### Widget Decision Tree

```
What does the plugin need to show or do?
├── Linting results
│   └── Return `diagnostics` + `highlights`
│       (Diagnostic panel + editor highlights)
│
├── Error/warning feedback
│   └── Return `status_message` with level="warning" or "error"
│       (Toast notification)
│
├── User action confirmed (toggle)
│   └── Return `status_message` with level="info"
│       (Toast notification)
│
├── Side-by-side comparison
│   └── Return `split_view` with left/right panes
│       (Split panel with Accept/Reject buttons)
│
├── Hierarchical data
│   └── Return `tree_view` with root node
│       (Collapsible tree panel)
│
├── Open a file
│   └── Return `open_file` with absolute path
│       (Opens in editor tab, validated against project root)
│
├── Replace editor content
│   └── Return `modified_content` with new text
│       (Replaces current buffer)
│
├── Copy text to clipboard
│   └── Return `clipboard_text` with the text
│       (Copies to system clipboard)
│
├── Navigate to a line
│   └── Return `goto_line` with line number (1-indexed)
│       (Moves editor cursor and scrolls to line)
│
├── Auto-display on file open
│   └── Return widget from `on_document_open`
│       (e.g., tree_view for YAML/JSON files)
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

| Plugin | Shortcut |
|--------|----------|
| Python Lint | `Ctrl+Shift+P` |
| Rust Lint | `Ctrl+Shift+R` |
| JavaScript Lint | `Ctrl+Shift+J` |
| Go Lint | `Ctrl+Shift+G` |
| File Explorer | `Ctrl+Shift+E` |
| YAML/JSON Viewer | `Ctrl+Shift+Y` |

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

## Plugin Verification & Signing

FerrisPad uses ed25519 digital signatures to verify plugin authenticity. This helps users identify official plugins from the FerrisPad team.

### Verification Status

When users browse plugins in FerrisPad's Plugin Manager, they see one of these badges:

| Badge | Meaning |
|-------|---------|
| **Verified** | Signed by the FerrisPad maintainer, checksums match |
| **Unverified** | No signature provided (third-party or community plugin) |
| **Invalid** | Signature exists but doesn't match (tampered or corrupted) |

### For Contributors

**You cannot sign plugins yourself.** The signing key is held by the FerrisPad maintainer.

When you submit a plugin via pull request:

1. Your plugin will initially show as **"Unverified"** - this is expected
2. After review and merge, the maintainer will:
   - Review your code for security issues
   - Sign the plugin with the official key
   - Update `plugins.json` with checksums and signature
3. Your plugin will then show as **"Verified"** in the Plugin Manager

### What Gets Signed

The signature covers:
- `init.lua` content (SHA-256 checksum)
- `plugin.toml` content (SHA-256 checksum)
- Plugin version number

**Any change to these files invalidates the signature.** After updating your plugin, request a re-sign via a new pull request.

### Can Users Still Install Unverified Plugins?

Yes. Unverified plugins can still be installed - users just see a warning badge. This allows:
- Testing plugins during development
- Installing community plugins before official review
- Using local/custom plugins

The verification system is informational, not restrictive.

---

## Submission Checklist

Before submitting a pull request:

- [ ] `init.lua` - Main plugin logic
- [ ] `plugin.toml` - Metadata with permissions, menu items, and config params
- [ ] `README.md` - Installation and usage instructions (including config options)
- [ ] `CHANGELOG.md` - Version history
- [ ] Tool detection with helpful error messages
- [ ] Project/environment detection appropriate for the language
- [ ] JSON output parsing
- [ ] Individual tool toggles
- [ ] Documentation URLs (if available)
- [ ] Configurable parameters (if applicable) with sensible defaults
- [ ] Tested all menu actions
- [ ] Tested configuration via Settings dialog
- [ ] Updated `plugins.json` registry
- [ ] Updated main `README.md` available plugins table

---

## Questions?

Open an issue at [ferrispad-plugins](https://github.com/fedro86/ferrispad-plugins/issues) or check the [FerrisPad Plugin API Documentation](https://github.com/fedro86/ferrispad/blob/main/docs/temp/0.9.1/07_DIAGNOSTIC_PANEL_ENHANCEMENTS.md).
