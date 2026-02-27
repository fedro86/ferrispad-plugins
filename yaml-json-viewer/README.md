# YAML/JSON Tree Viewer

A FerrisPad plugin that displays YAML and JSON files as collapsible tree views.

## Features

- **Auto-open**: Automatically displays a tree view when opening `.yaml`, `.yml`, or `.json` files
- **Menu action**: Manually trigger via Plugins > View as Tree (`Ctrl+Shift+Y`)
- **Collapsible nodes**: Expand/collapse sections of the tree
- **Search**: Filter tree nodes using the search bar in the tree panel header
- **Copy Value**: Right-click a node to copy its value to the clipboard
- **Copy Key Path**: Right-click a node to copy the dot-separated key path (e.g., `server.port`)

## Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `expand_depth` | Choice | `2` | Levels to auto-expand: 1, 2, 3, or All |
| `auto_open` | Boolean | `true` | Auto-open tree when a YAML/JSON file is opened |

Configure via Edit > Plugin Settings > yaml-json-viewer.

## Supported File Types

- `.yaml`
- `.yml`
- `.json`

## Version

1.0.1
