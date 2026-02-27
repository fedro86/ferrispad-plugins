# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.0.1] - 2026-02-27

### Fixed
- Click-to-line navigation now correctly handles repeated YAML structures (e.g., 126 identical blocks under `items:`). Previously, array indices were stripped from the node path, causing all clicks to jump to the first occurrence. The new sequential position tracker uses array indices as occurrence counters and scopes dash-counting by indentation level to support nested arrays.

## [1.0.0] - 2026-02-27

### Added
- Tree view for YAML and JSON files with collapsible nodes
- Auto-open on file open (configurable)
- "View as Tree" menu action (Ctrl+Shift+Y)
- Copy Value context menu action (copies node value to clipboard)
- Copy Key Path context menu action (copies dot-separated key path)
- Configurable expand depth (1, 2, 3, or all)
- Search/filter support via tree panel search bar
