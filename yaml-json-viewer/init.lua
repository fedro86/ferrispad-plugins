-- YAML/JSON Tree Viewer Plugin for FerrisPad v1.0.0
local M = {
    name = "yaml-json-viewer",
    version = "1.0.0",
    description = "Tree viewer for YAML and JSON files"
}

-- Supported file extensions
local SUPPORTED_EXTENSIONS = {
    yaml = true,
    yml = true,
    json = true,
}

-- Check if a file path has a supported extension
local function is_supported(path)
    if not path then return false end
    local ext = path:match("%.([^%.]+)$")
    if ext then ext = ext:lower() end
    return ext and SUPPORTED_EXTENSIONS[ext] or false
end

-- Get file extension label for tree title
local function ext_label(path)
    local ext = path:match("%.([^%.]+)$")
    if ext then ext = ext:upper() end
    return ext or "FILE"
end

-- Get filename from path
local function filename(path)
    return path:match("([^/\\]+)$") or path
end

-- Read expand depth from config (default 2)
local function get_expand_depth(api)
    local val = api:get_config("expand_depth")
    if val then return tonumber(val) or 2 end
    return 2
end

-- Read auto_open config (default true)
local function get_auto_open(api)
    local val = api:get_config("auto_open")
    return val ~= "false"
end

-- Build tree view result table
local function build_tree_result(api, path, content)
    local label = ext_label(path)
    local name = filename(path)
    local depth = get_expand_depth(api)

    return {
        tree_view = {
            title = string.format("[%s] %s", label, name),
            yaml_content = content,
            expand_depth = depth,
            click_mode = "single",
            on_click = "node_clicked",
            context_menu = {
                {
                    label = "Copy Value",
                    action = "copy_value",
                    target = "all",
                },
                {
                    label = "Copy Key Path",
                    action = "copy_path",
                    target = "all",
                },
            },
        }
    }
end

--- Called when a document is opened.
--- Auto-displays YAML/JSON files as a tree if auto_open is enabled.
function M.on_document_open(api, path)
    if not is_supported(path) then return nil end
    if not get_auto_open(api) then return nil end

    local content = api:get_text()
    if not content or content == "" then return nil end

    return build_tree_result(api, path, content)
end

--- Called when user triggers "View as Tree" from the menu.
function M.on_menu_action(api, action, path, content)
    if action ~= "view_tree" then return nil end

    if not is_supported(path) then
        return {
            status_message = {
                level = "warning",
                text = "View as Tree: not a YAML or JSON file"
            }
        }
    end

    if not content or content == "" then
        return {
            status_message = {
                level = "warning",
                text = "View as Tree: file is empty"
            }
        }
    end

    return build_tree_result(api, path, content)
end

-- Strip type indicator suffixes: "key {3}" → "key", "key [5]" → "key"
-- Also handles array index labels: "0 {4}" → "[0]", "12 [3]" → "[12]"
local function strip_type_suffix(segment)
    -- Strip " {N}" or " [N]" suffix
    local stripped = segment:match("^(.-)%s+[%{%[]%d+[%}%]]$") or segment
    return stripped
end

-- Extract the semantic key from a node_path segment.
-- Handles: "key: value" → "key", "key {3}" → "key", "[0]: value" → "[0]",
-- "0 {4}" → "[0]" (array index with children)
local function extract_key(segment)
    -- First strip type suffix
    local s = strip_type_suffix(segment)
    -- "key: value" → "key"
    local key = s:match("^([^:]+):%s") or s
    -- Bare number from array index with children: "0" → "[0]"
    if key:match("^%d+$") then
        key = "[" .. key .. "]"
    end
    return key
end

--- Called when user interacts with a tree node (click or context menu).
function M.on_widget_action(api, widget_type, action, session_id, data)
    if widget_type ~= "tree_view" then return nil end

    local node_path = data.node_path
    if not node_path or #node_path == 0 then return nil end

    if action == "copy_value" then
        -- Extract value from the last segment: "key: value" → "value"
        local last = node_path[#node_path]
        local value = last:match("^[^:]+:%s*(.+)$")
        if not value then
            value = strip_type_suffix(last)
        end
        return { clipboard_text = value }

    elseif action == "copy_path" then
        -- Build dot-separated key path from node_path segments
        local keys = {}
        for _, segment in ipairs(node_path) do
            keys[#keys + 1] = extract_key(segment)
        end
        return { clipboard_text = table.concat(keys, ".") }

    elseif action == "node_clicked" then
        -- Navigate to the line in the editor where this key appears.
        local text = api:get_text()
        if not text then return nil end

        -- Escape Lua pattern special characters in a key
        local function escape_pat(s)
            return s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        end

        -- Check if a line matches a given key (YAML unquoted, YAML quoted, JSON quoted)
        local function line_matches_key(line, raw_key)
            local esc = escape_pat(raw_key)
            return line:match("^%s*%-?%s*" .. esc .. "%s*:")
                or line:match("^%s*%-?%s*" .. esc .. "%s*$")
                or line:match('^%s*"' .. esc .. '"%s*:')
        end

        -- Split text into lines
        local lines = {}
        for line in text:gmatch("([^\n]*)\n?") do
            lines[#lines + 1] = line
        end

        -- Extract segments from full path (keys and array indices)
        local segments = {}
        for _, segment in ipairs(node_path) do
            segments[#segments + 1] = extract_key(segment)
        end
        if #segments == 0 then return nil end

        -- Sequential position tracker: walk segments, advancing pos
        local pos = 1

        for _, segment in ipairs(segments) do
            local idx = segment:match("^%[(%d+)%]$")

            if idx then
                -- Array index: find the (idx+1)th list-item marker ("- ")
                idx = tonumber(idx)
                local count = -1
                local target_indent = nil
                for i = pos, #lines do
                    local indent = lines[i]:match("^(%s*)%-")
                    if indent then
                        if target_indent and #indent < target_indent then break end
                        if not target_indent then target_indent = #indent end
                        if #indent == target_indent then
                            count = count + 1
                            if count == idx then
                                pos = i
                                break
                            end
                        end
                    end
                end
            else
                -- Regular key: find next occurrence at or after pos
                for i = pos, #lines do
                    if line_matches_key(lines[i], segment) then
                        pos = i
                        break
                    end
                end
            end
        end

        return { goto_line = pos }

    elseif action == "move" then
        -- Reorder: move node_path item to target_path position
        -- For structured data, this would mean reordering keys/elements
        -- Currently a no-op; plugins can implement YAML/JSON rewriting later
        return {}
    end

    return nil
end

return M
