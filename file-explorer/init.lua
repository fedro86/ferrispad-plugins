-- File Explorer Plugin for FerrisPad v0.7.2
-- Uses native cross-platform filesystem API (no shell commands)
-- Git status indicators: modified (amber), added/untracked (green), conflict (red)
local M = {
    name = "file-explorer",
    version = "0.7.2",
    description = "File explorer tree view for project directories"
}

-- Whether the tree panel is currently shown (for on_document_lint refresh)
local tree_shown = false

-- Default ignored folders (used when config is not yet available)
local DEFAULT_IGNORE = ".git,node_modules,target,__pycache__,.venv,venv,.mypy_cache,.pytest_cache,.tox,dist,build,.eggs,.cache"

-- Parse comma-separated ignore patterns into a lookup table and a sequence list.
-- The lookup table is used for Lua-side filtering (hidden files etc.).
-- The sequence list is passed to scan_dir so Rust skips these dirs during the walk.
local function parse_ignore_patterns(csv)
    local lookup = {}
    local list = {}
    for entry in (csv or DEFAULT_IGNORE):gmatch("[^,]+") do
        local trimmed = entry:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            lookup[trimmed] = true
            list[#list + 1] = trimmed
        end
    end
    return lookup, list
end

-- File extensions to skip (compiled/binary artifacts)
local SKIP_EXTENSIONS = {
    ["pyc"] = true,
    ["o"] = true,
    ["so"] = true,
}

-- Map git status codes to semantic label_color values
local STATUS_COLORS = {
    ["M"]  = "modified",
    ["MM"] = "modified",
    ["A"]  = "added",
    ["AM"] = "added",
    ["??"] = "untracked",
    ["UU"] = "conflict",
    ["D"]  = "modified",
    ["R"]  = "modified",
    ["!!"] = "ignored",
}

-- Context menu items shared by initial scan and lazy expand responses
local CONTEXT_MENU = {
    { label = "New File...",   action = "new_file",   target = "folder", input = "New file name:" },
    { label = "New Folder...", action = "new_folder", target = "folder", input = "New folder name:" },
    { label = "Copy Path",    target = "folder", clipboard = true },
    { label = "Rename...",    action = "rename",     target = "folder", input = "Rename to:", prefill_name = true },
    { label = "Delete",       action = "delete",     target = "folder", confirm = "Delete this folder and all contents?" },
    { label = "Open",         action = "node_clicked", target = "file" },
    { label = "Copy Path",    target = "file", clipboard = true },
    { label = "Rename...",    action = "rename",     target = "file", input = "Rename to:", prefill_name = true },
    { label = "Delete",       action = "delete",     target = "file", confirm = "Delete this file?" },
    { label = "New File...",   action = "new_file",   target = "empty", input = "New file name:" },
    { label = "New Folder...", action = "new_folder", target = "empty", input = "New folder name:" },
    { label = "Refresh",      action = "refresh",    target = "empty" },
}

-- Priority for folder status propagation (higher = more important)
local COLOR_PRIORITY = {
    ignored = 0,
    untracked = 1,
    added = 2,
    modified = 3,
    conflict = 4,
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

-- Apply git status colors to tree nodes and propagate to parent folders.
-- Returns the highest-priority color found in this subtree (for propagation).
local function apply_git_colors(node, git_lookup)
    local max_color = nil
    local max_priority = 0

    -- Apply color to file nodes
    if not node.children then
        local color = git_lookup[node.data]
        if color then
            node.label_color = color
            return color
        end
        return nil
    end

    -- Recurse into children and propagate highest priority color
    for _, child in ipairs(node.children) do
        local child_color = apply_git_colors(child, git_lookup)
        if child_color then
            local p = COLOR_PRIORITY[child_color] or 0
            if p > max_priority then
                max_priority = p
                max_color = child_color
            end
        end
    end

    if max_color then
        node.label_color = max_color
    end
    return max_color
end

-- Scan project directory and build tree view data
local function scan_project(api)
    local project_root = api:get_project_root()
    if not project_root then
        return nil, "No project root found. Open a file in a project first."
    end

    local include_hidden = show_hidden(api)
    local ignore_csv = api:get_config("ignore_patterns") or DEFAULT_IGNORE
    local skip_dirs, skip_dirs_list = parse_ignore_patterns(ignore_csv)

    -- Use native scan_dir API with skip_dirs for Rust-side filtering
    local raw_entries = api:scan_dir(project_root, 5, skip_dirs_list)
    if not raw_entries then
        return nil, "Failed to scan project directory"
    end

    -- Filter remaining entries (hidden files, binary extensions)
    local entries = {}
    for _, entry in ipairs(raw_entries) do
        local skip = false

        -- Check for hidden path components
        if not include_hidden then
            for component in entry.rel_path:gmatch("[^/]+") do
                if is_hidden(component) then
                    skip = true
                    break
                end
            end
        end

        -- Skip binary artifact extensions for files
        if not skip and not entry.is_dir then
            local ext = get_extension(entry.name)
            if ext and SKIP_EXTENSIONS[ext] then
                skip = true
            end
        end

        if not skip then
            table.insert(entries, {
                path = entry.rel_path,
                parent = entry.rel_path:match("^(.+)/[^/]+$") or "",
                name = entry.name,
                is_dir = entry.is_dir,
                has_children = entry.has_children,
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
            local dir_node = get_or_create_dir(entry.path, entry.name)
            -- Mark boundary directories with children as lazy-loadable
            if entry.has_children and #dir_node.children == 0 then
                dir_node.lazy = true
                dir_node._full_path = project_root .. "/" .. entry.path
            end
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

    local root_node = {
        label = project_name,
        icon = "folder",
        expanded = true,
        children = root_children,
    }

    -- Query git status and apply colors
    local git_statuses = api:git_status(project_root)
    if git_statuses then
        -- Build lookup: full_path -> semantic color name
        local git_lookup = {}
        for rel_path, status_code in pairs(git_statuses) do
            local color = STATUS_COLORS[status_code]
            if color then
                git_lookup[project_root .. "/" .. rel_path] = color
            end
        end
        -- Walk tree and apply colors; propagate to folders
        apply_git_colors(root_node, git_lookup)
    end

    -- Cache the tree and metadata for lazy expansion
    M._cached_tree = root_node
    M._cached_project_root = project_root
    M._cached_node_map = node_map

    return {
        title = project_name,
        root = root_node,
        context_path = project_root,
        context_menu = CONTEXT_MENU,
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

-- Walk a tree node by label path segments, returning the node or nil.
local function find_node(root, labels)
    local current = root
    for _, label in ipairs(labels) do
        local found = false
        if current.children then
            for _, child in ipairs(current.children) do
                if child.label == label then
                    current = child
                    found = true
                    break
                end
            end
        end
        if not found then return nil end
    end
    return current
end

-- Scan a single directory and build tree children.
-- Used by both lazy expand (node_expanded) and refresh restore.
local function scan_and_build_children(api, full_path, project_root)
    local include_hidden = show_hidden(api)
    local ignore_csv = api:get_config("ignore_patterns") or DEFAULT_IGNORE
    local skip_dirs, skip_dirs_list = parse_ignore_patterns(ignore_csv)

    local raw_entries = api:scan_dir(full_path, 5, skip_dirs_list)
    if not raw_entries then return nil end

    local new_children = {}
    local sub_node_map = {}

    local function get_or_create_sub(dir_path, dir_name)
        if sub_node_map[dir_path] then
            return sub_node_map[dir_path]
        end
        local node = {
            label = dir_name or dir_path:match("([^/]+)$") or dir_path,
            icon = "folder",
            children = {},
        }
        sub_node_map[dir_path] = node
        local parent_path = dir_path:match("^(.+)/[^/]+$")
        if parent_path then
            local parent_name = parent_path:match("([^/]+)$")
            local parent_node = get_or_create_sub(parent_path, parent_name)
            table.insert(parent_node.children, node)
        else
            table.insert(new_children, node)
        end
        return node
    end

    for _, entry in ipairs(raw_entries) do
        local skip = false
        if not include_hidden then
            for component in entry.rel_path:gmatch("[^/]+") do
                if is_hidden(component) then skip = true; break end
            end
        end
        if not skip and not entry.is_dir then
            local ext = get_extension(entry.name)
            if ext and SKIP_EXTENSIONS[ext] then skip = true end
        end
        if not skip then
            if entry.is_dir then
                local dir_node = get_or_create_sub(entry.rel_path, entry.name)
                if entry.has_children and #dir_node.children == 0 then
                    dir_node.lazy = true
                    dir_node._full_path = full_path .. "/" .. entry.rel_path
                end
            else
                local file_node = {
                    label = entry.name,
                    icon = "file",
                    data = full_path .. "/" .. entry.rel_path,
                }
                local parent_rel = entry.rel_path:match("^(.+)/[^/]+$")
                if parent_rel then
                    local parent_node = get_or_create_sub(parent_rel, nil)
                    table.insert(parent_node.children, file_node)
                else
                    table.insert(new_children, file_node)
                end
            end
        end
    end

    local function sort_children(children)
        table.sort(children, function(a, b)
            local a_is_dir = (a.children ~= nil)
            local b_is_dir = (b.children ~= nil)
            if a_is_dir ~= b_is_dir then return a_is_dir end
            return a.label < b.label
        end)
        for _, child in ipairs(children) do
            if child.children then sort_children(child.children) end
        end
    end
    sort_children(new_children)

    return new_children
end

-- After rebuilding the tree (depth 5), re-scan any previously expanded lazy
-- directories so deep folders show fresh content across refreshes.
local function restore_lazy_subtrees(new_root, old_root, api, project_root)
    if not old_root or not new_root then return end

    local function walk(new_node, old_node)
        if not new_node.children or not old_node.children then return end
        for _, new_child in ipairs(new_node.children) do
            -- Find matching child in old tree
            local old_child = nil
            for _, oc in ipairs(old_node.children) do
                if oc.label == new_child.label then
                    old_child = oc
                    break
                end
            end
            if old_child then
                if new_child.lazy and not old_child.lazy and old_child.children then
                    -- Boundary: new tree is lazy here, old tree was expanded.
                    -- Re-scan fresh instead of grafting stale data.
                    local dir_path = new_child._full_path or old_child._full_path
                    if dir_path then
                        local fresh_children = scan_and_build_children(api, dir_path, project_root)
                        if fresh_children then
                            new_child.children = fresh_children
                            new_child.lazy = false
                            -- Recurse to restore deeper lazy expansions
                            walk(new_child, old_child)
                        end
                    end
                elseif new_child.children and old_child.children then
                    walk(new_child, old_child)
                end
            end
        end
    end

    walk(new_root, old_root)
end

-- Refresh the tree and return it as a widget result
local function refresh_tree(api)
    local old_tree = M._cached_tree
    local tree_data, err = scan_project(api)
    if not tree_data then
        return {
            status_message = {
                level = "warning",
                text = "[File Explorer] " .. (err or "Unknown error"),
            }
        }
    end
    -- Re-scan any previously expanded lazy directories with fresh data
    if old_tree and tree_data.root then
        local project_root = M._cached_project_root
        restore_lazy_subtrees(tree_data.root, old_tree, api, project_root)
        -- Re-apply git colors to include re-scanned subtrees
        local git_statuses = api:git_status(project_root)
        if git_statuses then
            local function clear_colors(node)
                node.label_color = nil
                if node.children then
                    for _, child in ipairs(node.children) do clear_colors(child) end
                end
            end
            clear_colors(tree_data.root)
            local git_lookup = {}
            for rel_path, status_code in pairs(git_statuses) do
                local color = STATUS_COLORS[status_code]
                if color then
                    git_lookup[project_root .. "/" .. rel_path] = color
                end
            end
            apply_git_colors(tree_data.root, git_lookup)
        end
        M._cached_tree = tree_data.root
    end
    tree_data.on_click = "open_file"
    tree_data.persistent = true
    return { tree_view = tree_data }
end

-- Handle menu actions
function M.on_menu_action(api, action, path, content)
    if action == "show_explorer" or action == "refresh" then
        tree_shown = true
        return refresh_tree(api)
    end

    return {}
end

-- Handle document lint results (fires after save — update git colors only).
-- Does NOT rebuild the tree, so lazily-loaded deep folders stay open.
function M.on_document_lint(api, path, content)
    if not tree_shown or not M._cached_tree or not M._cached_project_root then
        return nil
    end

    local project_root = M._cached_project_root

    -- Re-query git status and re-apply colors to the cached tree
    local git_statuses = api:git_status(project_root)
    if git_statuses then
        -- Reset all colors first
        local function clear_colors(node)
            node.label_color = nil
            if node.children then
                for _, child in ipairs(node.children) do
                    clear_colors(child)
                end
            end
        end
        clear_colors(M._cached_tree)

        local git_lookup = {}
        for rel_path, status_code in pairs(git_statuses) do
            local color = STATUS_COLORS[status_code]
            if color then
                git_lookup[project_root .. "/" .. rel_path] = color
            end
        end
        apply_git_colors(M._cached_tree, git_lookup)
    end

    local project_name = project_root:match("([^/\\]+)$") or "Project"
    return {
        tree_view = {
            title = project_name,
            root = M._cached_tree,
            context_path = project_root,
            context_menu = CONTEXT_MENU,
            on_click = "open_file",
            persistent = true,
            expand_depth = 0,
        }
    }
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

    elseif action == "move" then
        if #node_path == 0 then return {} end
        local target_path_parts = data.target_path or {}

        local source_path, project_root = reconstruct_path(api, node_path)
        local target_dir, _ = reconstruct_path(api, target_path_parts)
        if not source_path or not target_dir then return {} end

        -- If target is a file, use its parent directory
        if api:is_file(target_dir) then
            target_dir = target_dir:match("^(.+)/[^/]+$") or project_root
        end

        -- Build new path: target_dir + source filename
        local source_name = source_path:match("([^/]+)$")
        local new_path = target_dir .. "/" .. source_name

        if source_path == new_path then return {} end

        api:log("File explorer: move source=" .. source_path .. " target_dir=" .. target_dir .. " new_path=" .. new_path)

        local ok, err = api:rename(source_path, new_path)
        if not ok then
            return {
                status_message = {
                    level = "error",
                    text = "[File Explorer] Failed to move: " .. (err or "unknown error"),
                }
            }
        end

        return refresh_tree(api)

    elseif action == "node_expanded" then
        -- Lazy-load: scan the expanded directory and graft into cached tree
        if #node_path == 0 or not M._cached_tree or not M._cached_project_root then
            return {}
        end

        local full_path, project_root = reconstruct_path(api, node_path)
        if not full_path then return {} end

        api:log("Lazy expand: " .. full_path)

        -- Find the node in the cached tree by walking the path
        local current = find_node(M._cached_tree, node_path)
        if not current then
            api:log("Lazy expand: node not found in cache")
            return {}
        end

        -- Scan and build fresh children
        local new_children = scan_and_build_children(api, full_path, project_root)
        if not new_children then return {} end

        -- Apply git colors to new children
        local git_statuses = api:git_status(project_root)
        if git_statuses then
            local git_lookup = {}
            for rel_path, status_code in pairs(git_statuses) do
                local color = STATUS_COLORS[status_code]
                if color then
                    git_lookup[project_root .. "/" .. rel_path] = color
                end
            end
            for _, child in ipairs(new_children) do
                apply_git_colors(child, git_lookup)
            end
        end

        -- Graft into cached tree: replace lazy placeholder with real children
        current.children = new_children
        current.lazy = false

        -- Return the full updated cached tree
        local project_name = project_root:match("([^/\\]+)$") or "Project"
        return {
            tree_view = {
                title = project_name,
                root = M._cached_tree,
                context_path = project_root,
                context_menu = CONTEXT_MENU,
                on_click = "open_file",
                persistent = true,
                expand_depth = 0,
            }
        }

    elseif action == "refresh" then
        return refresh_tree(api)
    end

    return {}
end

return M
