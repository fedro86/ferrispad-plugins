-- File Explorer Plugin for FerrisPad v0.4.0
-- Uses native cross-platform filesystem API (no shell commands)
local M = {
    name = "file-explorer",
    version = "0.4.0",
    description = "File explorer tree view for project directories"
}

-- Directories to always skip
local SKIP_DIRS = {
    [".git"] = true,
    ["node_modules"] = true,
    ["target"] = true,
    ["__pycache__"] = true,
    [".venv"] = true,
    ["venv"] = true,
    [".mypy_cache"] = true,
    [".pytest_cache"] = true,
    [".tox"] = true,
    ["dist"] = true,
    ["build"] = true,
    [".eggs"] = true,
    [".cache"] = true,
}

-- File extensions to skip (compiled/binary artifacts)
local SKIP_EXTENSIONS = {
    ["pyc"] = true,
    ["o"] = true,
    ["so"] = true,
}

-- Check if a name is hidden (starts with .)
local function is_hidden(name)
    return name:sub(1, 1) == "."
end

-- Get file extension from name
local function get_extension(name)
    return name:match("%.([^%.]+)$")
end

-- Read boolean config
local function show_hidden(api)
    local val = api:get_config("show_hidden_files")
    return val == "true" or val == true
end

-- Scan project directory and build tree view data
local function scan_project(api)
    local project_root = api:get_project_root()
    if not project_root then
        return nil, "No project root found. Open a file in a project first."
    end

    local include_hidden = show_hidden(api)

    -- Use native scan_dir API (cross-platform, no shell commands)
    local raw_entries = api:scan_dir(project_root, 5)
    if not raw_entries then
        return nil, "Failed to scan project directory"
    end

    -- Filter entries
    local entries = {}
    for _, entry in ipairs(raw_entries) do
        local dominated_by_skip = false
        local dominated_by_hidden = false

        -- Check each path component for skip dirs and hidden dirs
        for component in entry.rel_path:gmatch("[^/]+") do
            if SKIP_DIRS[component] then
                dominated_by_skip = true
                break
            end
            if not include_hidden and is_hidden(component) then
                dominated_by_hidden = true
                break
            end
        end

        -- Skip binary artifact extensions for files
        local skip_ext = false
        if not entry.is_dir then
            local ext = get_extension(entry.name)
            if ext and SKIP_EXTENSIONS[ext] then
                skip_ext = true
            end
        end

        if not dominated_by_skip and not dominated_by_hidden and not skip_ext then
            table.insert(entries, {
                path = entry.rel_path,
                parent = entry.rel_path:match("^(.+)/[^/]+$") or "",
                name = entry.name,
                is_dir = entry.is_dir,
            })
        end
    end

    -- Sort: directories first, then files, all alphabetical
    table.sort(entries, function(a, b)
        if a.is_dir ~= b.is_dir then
            return a.is_dir
        end
        return a.path < b.path
    end)

    -- Build tree structure
    local root_children = {}
    local node_map = {}

    local function get_or_create_dir(dir_path, dir_name)
        if node_map[dir_path] then
            return node_map[dir_path]
        end

        local node = {
            label = dir_name or dir_path:match("([^/]+)$") or dir_path,
            icon = "folder",
            children = {},
        }
        node_map[dir_path] = node

        local parent_path = dir_path:match("^(.+)/[^/]+$")
        if parent_path then
            local parent_name = parent_path:match("([^/]+)$")
            local parent_node = get_or_create_dir(parent_path, parent_name)
            table.insert(parent_node.children, node)
        else
            table.insert(root_children, node)
        end

        return node
    end

    -- Process all entries
    for _, entry in ipairs(entries) do
        if entry.is_dir then
            get_or_create_dir(entry.path, entry.name)
        else
            local file_node = {
                label = entry.name,
                icon = "file",
                data = project_root .. "/" .. entry.path,
            }

            if entry.parent ~= "" then
                local parent_node = get_or_create_dir(entry.parent, nil)
                table.insert(parent_node.children, file_node)
            else
                table.insert(root_children, file_node)
            end
        end
    end

    -- Sort children recursively: folders first, then files
    local function sort_children(children)
        table.sort(children, function(a, b)
            local a_is_dir = (a.children ~= nil)
            local b_is_dir = (b.children ~= nil)
            if a_is_dir ~= b_is_dir then
                return a_is_dir
            end
            return a.label < b.label
        end)
        for _, child in ipairs(children) do
            if child.children then
                sort_children(child.children)
            end
        end
    end

    sort_children(root_children)

    -- Get project directory name for title
    local project_name = project_root:match("([^/\\]+)$") or "Project"

    return {
        title = project_name,
        root = {
            label = project_name,
            icon = "folder",
            expanded = true,
            children = root_children,
        },
        context_path = project_root,
        context_menu = {
            -- Folder items
            { label = "New File...",   action = "new_file",   target = "folder", input = "New file name:" },
            { label = "New Folder...", action = "new_folder", target = "folder", input = "New folder name:" },
            { label = "Copy Path",    target = "folder", clipboard = true },
            { label = "Rename...",    action = "rename",     target = "folder", input = "Rename to:", prefill_name = true },
            { label = "Delete",       action = "delete",     target = "folder", confirm = "Delete this folder and all contents?" },
            -- File items
            { label = "Open",         action = "node_clicked", target = "file" },
            { label = "Copy Path",    target = "file", clipboard = true },
            { label = "Rename...",    action = "rename",     target = "file", input = "Rename to:", prefill_name = true },
            { label = "Delete",       action = "delete",     target = "file", confirm = "Delete this file?" },
            -- Empty area items
            { label = "New File...",   action = "new_file",   target = "empty", input = "New file name:" },
            { label = "New Folder...", action = "new_folder", target = "empty", input = "New folder name:" },
            { label = "Refresh",      action = "refresh",    target = "empty" },
        },
    }, nil
end

-- Reconstruct the full filesystem path from a node_path array
local function reconstruct_path(api, node_path)
    local project_root = api:get_project_root()
    if not project_root then return nil, nil end
    if not node_path or #node_path == 0 then
        return project_root, project_root
    end
    return project_root .. "/" .. table.concat(node_path, "/"), project_root
end

-- Refresh the tree and return it as a widget result
local function refresh_tree(api)
    local tree_data, err = scan_project(api)
    if not tree_data then
        return {
            status_message = {
                level = "warning",
                text = "[File Explorer] " .. (err or "Unknown error"),
            }
        }
    end
    tree_data.on_click = "open_file"
    return { tree_view = tree_data }
end

-- Handle menu actions
function M.on_menu_action(api, action, path, content)
    if action == "show_explorer" or action == "refresh" then
        local tree_data, err = scan_project(api)

        if not tree_data then
            return {
                status_message = {
                    level = "warning",
                    text = "[File Explorer] " .. (err or "Unknown error")
                }
            }
        end

        api:log("File explorer: built tree with title '" .. tree_data.title .. "'")

        -- Add on_click handler so tree node clicks trigger on_widget_action
        tree_data.on_click = "open_file"

        return {
            tree_view = tree_data
        }
    end

    return {}
end

-- Handle widget interactions (tree view node clicks and context actions)
function M.on_widget_action(api, widget_type, action, session_id, data)
    if widget_type ~= "tree_view" then
        return {}
    end

    local node_path = data.node_path or {}

    if action == "node_clicked" then
        if #node_path == 0 then
            return {}
        end

        local full_path, _ = reconstruct_path(api, node_path)
        if not full_path then return {} end

        api:log("File explorer: trying path: " .. full_path)

        -- Check if it's a regular file (not a directory) and open it
        if api:is_file(full_path) then
            api:log("File explorer: opening " .. full_path)
            return { open_file = full_path }
        end

    elseif action == "new_file" then
        local input_text = data.input_text
        if not input_text or input_text == "" then return {} end

        local parent_path, _ = reconstruct_path(api, node_path)
        if not parent_path then return {} end

        local new_path = parent_path .. "/" .. input_text
        api:log("File explorer: creating file " .. new_path)

        local ok, err = api:create_file(new_path)
        if not ok then
            return {
                status_message = {
                    level = "error",
                    text = "[File Explorer] Failed to create file: " .. (err or input_text),
                }
            }
        end

        local tree_result = refresh_tree(api)
        tree_result.open_file = new_path
        return tree_result

    elseif action == "new_folder" then
        local input_text = data.input_text
        if not input_text or input_text == "" then return {} end

        local parent_path, _ = reconstruct_path(api, node_path)
        if not parent_path then return {} end

        local new_path = parent_path .. "/" .. input_text
        api:log("File explorer: creating folder " .. new_path)

        local ok, err = api:create_dir(new_path)
        if not ok then
            return {
                status_message = {
                    level = "error",
                    text = "[File Explorer] Failed to create folder: " .. (err or input_text),
                }
            }
        end

        return refresh_tree(api)

    elseif action == "rename" then
        local input_text = data.input_text
        if not input_text or input_text == "" then return {} end

        local old_path, _ = reconstruct_path(api, node_path)
        if not old_path then return {} end

        -- Build new path: same parent directory + new name
        local parent_dir = old_path:match("^(.+)/[^/]+$") or ""
        local new_path = parent_dir .. "/" .. input_text
        api:log("File explorer: renaming " .. old_path .. " -> " .. new_path)

        local ok, err = api:rename(old_path, new_path)
        if not ok then
            return {
                status_message = {
                    level = "error",
                    text = "[File Explorer] Failed to rename: " .. (err or "unknown error"),
                }
            }
        end

        return refresh_tree(api)

    elseif action == "delete" then
        local target_path, _ = reconstruct_path(api, node_path)
        if not target_path then return {} end

        api:log("File explorer: deleting " .. target_path)

        local ok, err = api:remove(target_path)
        if not ok then
            return {
                status_message = {
                    level = "error",
                    text = "[File Explorer] Failed to delete: " .. (err or "unknown error"),
                }
            }
        end

        return refresh_tree(api)

    elseif action == "refresh" then
        return refresh_tree(api)
    end

    return {}
end

return M
