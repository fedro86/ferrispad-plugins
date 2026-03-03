# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.1.0] - 2026-03-03

### Added

- Line alignment: deleted lines show a blank filler on the right, inserted lines show a blank filler on the left
- Intraline (word-level) diff highlighting for replacement lines
- Uses new `api:diff_text()` Rust API for accurate, fast diff computation

### Removed

- `parse_diff_highlights()` Lua function (replaced by Rust-side `api:diff_text()`)

## [1.0.0] - 2026-03-01

### Added

- Split view diff showing HEAD vs working copy
- Diff highlighting: removed lines (red) in left pane, added lines (green) in right pane
- "Revert to HEAD" action to replace editor buffer with committed version
- Edge case handling: untracked files, binary files, no changes, git not found, not a repo
- Unified diff parser for accurate line-level highlights
