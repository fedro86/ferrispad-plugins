-- File Explorer Plugin for FerrisPad v0.1.0
local M = {
    name = "file-explorer",
    version = "0.1.0",
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

-- Check if a name is hidden (starts with .)
local function is_hidden(name)
    return name:sub(1, 1) == "."
end

-- Read boolean config
local function show_hidden(api)
    local val = api:get_config("show_hidden_files")
    return val == "true" or val == true
end

-- Build tree nodes from find output
-- find outputs paths like: ./src/main.rs, ./Cargo.toml, ./src/app/state.rs
local function parse_find_output(output, project_root, include_hidden)
    -- Collect all entries: { path = relative_path, is_dir = bool, name = basename }
    local entries = {}

    for line in output:gmatch("[^\r\n]+") do
        -- Strip leading ./ prefix
        local rel = line:gsub("^%./", "")
        if rel ~= "" and rel ~= "." then
            -- Determine if it's a directory by checking if it ends with /
            -- (find -type d outputs without /, but we check via path structure)
            local name = rel:match("([^/]+)/?$") or rel
            local parent = rel:match("^(.+)/[^/]+$") or ""

            -- Skip noise directories
            if not SKIP_DIRS[name] then
                -- Skip hidden files/dirs unless configured
                local dominated_by_hidden = false
                if not include_hidden then
                    -- Check if any path component is hidden
                    for component in rel:gmatch("[^/]+") do
                        if is_hidden(component) then
                            dominated_by_hidden = true
                            break
                        end
                    end
                end

                if not dominated_by_hidden then
                    table.insert(entries, {
                        path = rel,
                        parent = parent,
                        name = name,
                    })
                end
            end
        end
    end

    return entries
end

-- Build a nested tree structure from flat path entries
local function build_tree(entries, project_root)
    -- First pass: identify directories (any path that is a prefix of another)
    local dir_set = {}
    for _, entry in ipairs(entries) do
        -- Mark all parent directories
        local parts = {}
        for part in entry.path:gmatch("[^/]+") do
            table.insert(parts, part)
            if #parts < #entry.path:gsub("[^/]", "") + 1 then
                -- This is an intermediate component
                local dir_path = table.concat(parts, "/")
                dir_set[dir_path] = true
            end
        end
    end

    -- Separate into directories and files
    local dirs = {}
    local files = {}
    for _, entry in ipairs(entries) do
        if dir_set[entry.path] then
            table.insert(dirs, entry)
        else
            table.insert(files, entry)
        end
    end

    -- Sort: dirs first (alphabetical), then files (alphabetical)
    table.sort(dirs, function(a, b) return a.path < b.path end)
    table.sort(files, function(a, b) return a.path < b.path end)

    -- Build tree nodes recursively
    -- tree_view format: { title, children = { {label, children, icon, ...}, ... } }
    local root_children = {}

    -- Helper: find or create a directory node at a given path
    local node_map = {} -- path -> node table

    local function get_or_create_dir(dir_path)
        if node_map[dir_path] then
            return node_map[dir_path]
        end

        local name = dir_path:match("([^/]+)$") or dir_path
        local node = {
            label = name,
            icon = "folder",
            children = {},
        }
        node_map[dir_path] = node

        -- Find parent
        local parent_path = dir_path:match("^(.+)/[^/]+$")
        if parent_path then
            local parent_node = get_or_create_dir(parent_path)
            table.insert(parent_node.children, node)
        else
            table.insert(root_children, node)
        end

        return node
    end

    -- Create all directory nodes
    for _, dir in ipairs(dirs) do
        get_or_create_dir(dir.path)
    end

    -- Add files to their parent directory nodes
    for _, file in ipairs(files) do
        local file_node = {
            label = file.name,
            icon = "file",
            data = project_root .. "/" .. file.path,
        }

        if file.parent ~= "" then
            local parent_node = get_or_create_dir(file.parent)
            table.insert(parent_node.children, file_node)
        else
            table.insert(root_children, file_node)
        end
    end

    -- Sort children within each directory: folders first, then files, alphabetical
    local function sort_children(children)
        table.sort(children, function(a, b)
            local a_is_dir = a.children ~= nil and #a.children > 0 or a.icon == "folder"
            local b_is_dir = b.children ~= nil and #b.children > 0 or b.icon == "folder"
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

    return root_children
end

-- Scan project directory and build tree view data
local function scan_project(api)
    local project_root = api:get_project_root()
    if not project_root then
        return nil, "No project root found. Open a file in a project first."
    end

    local include_hidden = show_hidden(api)

    -- Use find to list all files and directories (maxdepth 5 to avoid huge trees)
    -- -not -path patterns skip noise directories
    local result = api:run_command("find", project_root,
        "-maxdepth", "5",
        "-not", "-path", "*/.git/*",
        "-not", "-path", "*/.git",
        "-not", "-path", "*/node_modules/*",
        "-not", "-path", "*/node_modules",
        "-not", "-path", "*/target/*",
        "-not", "-path", "*/target",
        "-not", "-path", "*/__pycache__/*",
        "-not", "-path", "*/__pycache__",
        "-not", "-path", "*/.venv/*",
        "-not", "-path", "*/.venv",
        "-not", "-path", "*/.mypy_cache/*",
        "-not", "-path", "*/.mypy_cache",
        "-not", "-path", "*/.pytest_cache/*",
        "-not", "-path", "*/.pytest_cache",
        "-not", "-name", "*.pyc",
        "-not", "-name", "*.o",
        "-not", "-name", "*.so",
        "-printf", "%P\t%y\n"
    )

    if not result or not result.stdout then
        return nil, "Failed to scan project directory"
    end

    -- Parse find output: each line is "relative_path\ttype" where type is d or f
    local entries = {}
    for line in result.stdout:gmatch("[^\r\n]+") do
        local rel_path, ftype = line:match("^(.-)\t(%a)$")
        if rel_path and rel_path ~= "" then
            local name = rel_path:match("([^/]+)$") or rel_path
            local parent = rel_path:match("^(.+)/[^/]+$") or ""

            -- Skip noise directories
            local dominated_by_skip = false
            for component in rel_path:gmatch("[^/]+") do
                if SKIP_DIRS[component] then
                    dominated_by_skip = true
                    break
                end
            end

            -- Skip hidden files/dirs unless configured
            local dominated_by_hidden = false
            if not include_hidden then
                for component in rel_path:gmatch("[^/]+") do
                    if is_hidden(component) then
                        dominated_by_hidden = true
                        break
                    end
                end
            end

            if not dominated_by_skip and not dominated_by_hidden then
                table.insert(entries, {
                    path = rel_path,
                    parent = parent,
                    name = name,
                    is_dir = (ftype == "d"),
                })
            end
        end
    end

    -- Build tree structure
    local root_children = {}
    local node_map = {}

    -- Sort: directories first, then files, all alphabetical
    table.sort(entries, function(a, b)
        if a.is_dir ~= b.is_dir then
            return a.is_dir
        end
        return a.path < b.path
    end)

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
    local project_name = project_root:match("([^/]+)$") or "Project"

    return {
        title = project_name,
        children = root_children,
    }, nil
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

        return {
            tree_view = tree_data
        }
    end

    return {}
end

-- Handle widget interactions (tree view node clicks)
function M.on_widget_action(api, widget_type, action, session_id, data)
    if widget_type == "tree_view" and action == "node_clicked" then
        local node_path = data.node_path
        if not node_path or #node_path == 0 then
            return {}
        end

        -- The last element is the clicked node label
        -- We need to reconstruct the file path from the node hierarchy
        -- The data field on file nodes contains the absolute path
        -- However, the node_path only gives us labels, not data fields

        -- For tree views, the node_path is the sequence of labels from root to clicked node
        -- e.g., {"src", "app", "state.rs"}
        -- We need to reconstruct the full path from the project root

        local project_root = api:get_project_root()
        if not project_root then
            return {}
        end

        -- Reconstruct path from node labels
        local rel_path = table.concat(node_path, "/")
        local full_path = project_root .. "/" .. rel_path

        -- Check if it's a file (not a directory) by checking if it has an extension
        -- or just try to open it - if it's a directory, the editor will handle it
        if api:file_exists(full_path) then
            -- Check it's not a directory by trying to detect extension
            local name = node_path[#node_path]
            if name:match("%.%w+$") then
                api:log("File explorer: opening " .. full_path)
                return { open_file = full_path }
            end
        end
    end

    return {}
end

return M
