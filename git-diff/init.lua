-- Git Diff Plugin for FerrisPad v1.1.0
local M = {
    name = "git-diff",
    version = "1.1.0",
    description = "Show git diff in a split view with revert capability"
}

-- Cache HEAD content by file path (persists across hook calls)
local head_cache = {}

-- Check if git is available
local function git_available(api)
    local result = api:run_command("git", "--version")
    return result and result.success
end

-- Get the git repo root for a file's directory.
-- Returns root path (trimmed) or nil.
local function git_root(api, path)
    local dir = path:match("(.+)/[^/]+$") or "."
    local result = api:run_command("git", "-C", dir, "rev-parse", "--show-toplevel")
    if result and result.success then
        return result.stdout:match("^(.-)%s*$")
    end
    return nil
end

-- Get the relative path of a file within its git repo
local function relative_path(root, path)
    if path:sub(1, #root) == root then
        local rel = path:sub(#root + 1)
        if rel:sub(1, 1) == "/" then rel = rel:sub(2) end
        return rel
    end
    return nil
end

-- Check if file is tracked by git
local function is_tracked(api, root, rel)
    local result = api:run_command("git", "-C", root, "ls-files", "--error-unmatch", rel)
    return result and result.success
end

-- Check if file is binary
local function is_binary(api, root, rel)
    local result = api:run_command("git", "-C", root, "diff", "HEAD", "--numstat", "--", rel)
    if result and result.success and result.stdout then
        if result.stdout:match("^%-\t%-\t") then
            return true
        end
    end
    return false
end

-- Get file content from HEAD
local function get_head_content(api, root, rel)
    local result = api:run_command("git", "-C", root, "show", "HEAD:" .. rel)
    if result and result.success then
        return result.stdout
    end
    return nil
end

--- Called when user triggers "Show Git Diff" from the menu.
function M.on_menu_action(api, action, path, content)
    if action ~= "show_diff" then return nil end

    -- Validate: file must be open
    if not path or path == "" then
        return { status_message = { level = "warning", text = "[Git Diff] No file open" } }
    end

    -- Validate: git available
    if not git_available(api) then
        return { status_message = { level = "warning", text = "[Git Diff] git not found" } }
    end

    -- Resolve repo root (also validates we're inside a git repo)
    local root = git_root(api, path)
    if not root then
        return { status_message = { level = "warning", text = "[Git Diff] Not a git repository" } }
    end

    -- Resolve relative path within the repo
    local rel = relative_path(root, path)
    if not rel then
        return { status_message = { level = "warning", text = "[Git Diff] Cannot resolve file path" } }
    end

    -- Validate: file is tracked
    if not is_tracked(api, root, rel) then
        return { status_message = { level = "info", text = "[Git Diff] File not tracked by git" } }
    end

    -- Validate: not binary
    if is_binary(api, root, rel) then
        return { status_message = { level = "warning", text = "[Git Diff] Binary file, cannot diff" } }
    end

    -- Get HEAD version
    local head_content = get_head_content(api, root, rel)
    if not head_content then
        return { status_message = { level = "warning", text = "[Git Diff] Cannot read HEAD version (initial commit?)" } }
    end

    -- Compare: if identical, no diff to show
    if head_content == content then
        return { status_message = { level = "info", text = "[Git Diff] No changes from HEAD" } }
    end

    -- Compute aligned diff with intraline highlights via Rust API
    local diff = api:diff_text(head_content, content)

    -- Cache HEAD content for revert action (original, not aligned)
    head_cache[path] = head_content

    -- Get filename for labels
    local filename = path:match("([^/\\]+)$") or path

    -- Read display mode from plugin config
    local display_mode = api:get_config("display_mode") or "panel"

    return {
        split_view = {
            display_mode = display_mode,
            title = "Git Diff: " .. filename,
            left = {
                content = diff.left_content,
                label = "HEAD",
                line_numbers = true,
                highlights = diff.left_highlights,
            },
            right = {
                content = diff.right_content,
                label = "Working Copy",
                line_numbers = true,
                highlights = diff.right_highlights,
            },
            actions = {
                { label = "Revert to HEAD", action = "accept" },
            },
        }
    }
end

--- Called when user clicks an action button in the split view.
function M.on_widget_action(api, widget_type, action, session_id, data)
    if widget_type ~= "split_view" then return {} end

    if action == "accept" then
        -- Revert: find cached HEAD content for the current file
        local path = api:get_file_path()
        if path and head_cache[path] then
            local content = head_cache[path]
            head_cache[path] = nil
            return { modified_content = content }
        end
    elseif action == "reject" then
        -- Close: clean up cache
        local path = api:get_file_path()
        if path then
            head_cache[path] = nil
        end
    end

    return {}
end

return M
