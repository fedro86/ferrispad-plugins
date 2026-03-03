# Git Diff Plugin

Show git diffs in a side-by-side split view with revert capability.

## Features

- **Split view diff**: HEAD version on the left, working copy on the right
- **Diff highlighting**: Removed lines shown in red (left), added lines in green (right)
- **Revert to HEAD**: One-click revert replaces the editor buffer with the HEAD version
- **Edge case handling**: Clear messages for untracked files, binary files, no changes, etc.

## Usage

1. Open a file that has uncommitted changes
2. Press **Ctrl+Shift+D** or go to **Plugins > git-diff > Show Git Diff**
3. The split view shows HEAD (left) vs. your working copy (right)
4. Click **Revert to HEAD** to replace your buffer with the committed version
5. Click **Close** to dismiss the diff view

## Requirements

- `git` must be installed and available in PATH
- The file must be inside a git repository and tracked by git

## Edge Cases

| Situation | Behavior |
|-----------|----------|
| No file open | Warning toast |
| git not installed | Warning toast |
| Not a git repo | Warning toast |
| Untracked file | Info toast |
| Binary file | Warning toast |
| No changes from HEAD | Info toast |
| Initial commit (no HEAD) | Warning toast |

## Version

- **1.0.0** - Initial release
