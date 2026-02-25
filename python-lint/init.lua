-- Python Linter Plugin for FerrisPad v2.5.0
local M = {
    name = "Python Lint",
    version = "2.5.0",
    description = "Run ruff/pyright on Python files (supports project venv)"
}

-- Helper to read boolean config (persisted across sessions)
local function is_ruff_enabled(api)
    local val = api:get_config("ruff_enabled")
    return val == nil or val == "true" or val == true
end

local function is_pyright_enabled(api)
    local val = api:get_config("pyright_enabled")
    return val == nil or val == "true" or val == true
end

-- Map ruff_select config to actual args
local RUFF_SELECT_ARGS = {
    default = {},
    all = {"--select=ALL"},
    ["E,W"] = {"--select=E,W"},
    ["E,W,F"] = {"--select=E,W,F"},
    custom = {}  -- User provides via extra args
}

-- Map ruff_line_length config to actual args
local RUFF_LINE_LENGTH_ARGS = {
    default = {},
    ["79"] = {"--line-length=79"},
    ["88"] = {"--line-length=88"},
    ["100"] = {"--line-length=100"},
    ["120"] = {"--line-length=120"},
    custom = {}  -- User provides via extra args
}

-- Map pyright_mode config to actual args
local PYRIGHT_MODE_ARGS = {
    default = {},
    off = {"--level=off"},
    basic = {"--level=basic"},
    standard = {"--level=standard"},
    strict = {"--level=strict"},
    all = {"--level=all"}
}

-- Parse ruff JSON output
local function parse_ruff_output(json_str, api)
    local diagnostics = {}

    -- Ruff JSON structure (alphabetically sorted fields):
    -- { "code": "...", "end_location": {...}, "filename": "...", "fix": {...},
    --   "location": {"column": N, "row": N}, "message": "...", "noqa_row": N, "url": "..." }
    -- Note: top-level "location" comes BEFORE "message" (between "fix" and "message")
    -- There are also nested "location" fields inside "fix.edits[]"

    local i = 1
    while i <= #json_str do
        local cs, ce, code = json_str:find('"code"%s*:%s*"([^"]+)"', i)
        if not cs then break end

        -- Find the message field for this diagnostic (comes AFTER location)
        local msg_start, msg_end = json_str:find('"message"%s*:', ce)
        if not msg_start then
            i = ce + 1
            break
        end

        -- The top-level "location" is right before "message" in the JSON
        -- Search the region between code and message for the LAST "location":{"column"
        local search_region = json_str:sub(ce, msg_start)

        -- Find the LAST occurrence of "location":{"column" in this region
        -- (to skip any inside fix.edits)
        local last_loc_pos = nil
        local search_start = 1
        while true do
            local pos = search_region:find('"location"%s*:', search_start)
            if not pos then break end
            last_loc_pos = pos
            search_start = pos + 1
        end

        local col, row
        if last_loc_pos then
            local loc_str = search_region:sub(last_loc_pos)
            _, _, col, row = loc_str:find('"column"%s*:%s*(%d+)%s*,%s*"row"%s*:%s*(%d+)')
        end

        -- Extract the message text
        local _, _, message = json_str:sub(msg_start, msg_start + 300):find('"message"%s*:%s*"([^"]*)"')

        api:log("ruff: code=" .. tostring(code) .. " row=" .. tostring(row) .. " col=" .. tostring(col) .. " msg=" .. tostring(message and message:sub(1,40)))

        if message and row then
            local level = "warning"
            if code == "invalid-syntax" or code:match("^F") or code:match("^E") then
                level = "error"
            end

            -- Extract URL (comes after message)
            local url_region = json_str:sub(msg_start, msg_start + 400)
            local _, _, url = url_region:find('"url"%s*:%s*"([^"]+)"')

            table.insert(diagnostics, {
                line = tonumber(row),
                column = tonumber(col),
                message = code .. ": " .. message,
                level = level,
                url = url
            })
        end

        i = msg_end + 1
    end

    api:log("ruff parsed " .. #diagnostics .. " diagnostics")
    return diagnostics
end

-- Parse pyright JSON output
local function parse_pyright_output(json_str, api)
    local diagnostics = {}

    -- Pyright structure:
    -- { "severity": "error", "message": "...", "range": { "start": {"line": N, "character": N}, "end": {...} } }

    local i = 1
    while i <= #json_str do
        local ss, se, severity = json_str:find('"severity"%s*:%s*"([^"]+)"', i)
        if not ss then break end

        local region = json_str:sub(ss, math.min(#json_str, ss + 500))

        -- Extract message
        local _, _, message = region:find('"message"%s*:%s*"(.-)"')

        -- Extract range.start - look for "start" followed by "line" then "character"
        local _, _, line, col = region:find('"start"%s*:%s*{%s*"line"%s*:%s*(%d+)%s*,%s*"character"%s*:%s*(%d+)')

        api:log("pyright: sev=" .. tostring(severity) .. " line=" .. tostring(line) .. " msg=" .. tostring(message and message:sub(1,30)))

        if message and line then
            local level = "info"
            if severity == "error" then
                level = "error"
            elseif severity == "warning" then
                level = "warning"
            end

            table.insert(diagnostics, {
                line = tonumber(line) + 1,
                column = tonumber(col) + 1,
                message = "[pyright] " .. message,
                level = level
            })
        end

        i = se + 1
    end

    api:log("pyright parsed " .. #diagnostics .. " diagnostics")
    return diagnostics
end

-- Find command in venv or system PATH
local function find_command(api, cmd_name)
    local file_dir = api:get_file_dir()
    if file_dir then
        local venv_paths = {
            file_dir .. "/.venv/bin/" .. cmd_name,
            file_dir .. "/venv/bin/" .. cmd_name,
            file_dir .. "/../.venv/bin/" .. cmd_name,
            file_dir .. "/../venv/bin/" .. cmd_name,
        }
        for _, p in ipairs(venv_paths) do
            if api:file_exists(p) then
                api:log("Found " .. cmd_name .. " in venv: " .. p)
                return p
            end
        end
    end
    if api:command_exists(cmd_name) then
        return cmd_name
    end
    return nil
end

-- Split a string by spaces (for extra args)
local function split_args(str)
    local args = {}
    for arg in str:gmatch("%S+") do
        table.insert(args, arg)
    end
    return args
end

-- Run ruff and collect diagnostics
local function run_ruff(api, path)
    local ruff_cmd = find_command(api, "ruff")
    if not ruff_cmd then
        return {}, false
    end

    api:log("Running ruff...")

    -- Build arguments: check --output-format=json <path> [select_args...] [line_length_args...] [extra_args...]
    local args = {"check", "--output-format=json", path}

    -- Add rule selection args from config
    local ruff_select = api:get_config("ruff_select") or "default"
    local select_args = RUFF_SELECT_ARGS[ruff_select] or {}
    for _, arg in ipairs(select_args) do
        table.insert(args, arg)
    end

    -- Add line length args from config
    local ruff_line_length = api:get_config("ruff_line_length") or "default"
    local length_args = RUFF_LINE_LENGTH_ARGS[ruff_line_length] or {}
    for _, arg in ipairs(length_args) do
        table.insert(args, arg)
    end

    -- Append extra arguments from config
    local extra_args = api:get_config("ruff_args") or ""
    if extra_args ~= "" then
        for _, arg in ipairs(split_args(extra_args)) do
            table.insert(args, arg)
        end
    end

    local result = api:run_command(ruff_cmd, table.unpack(args))
    if result and result.stdout and #result.stdout > 2 then
        return parse_ruff_output(result.stdout, api), true
    end
    return {}, true
end

-- Run pyright and collect diagnostics
local function run_pyright(api, path)
    local pyright_cmd = find_command(api, "pyright")
    if not pyright_cmd then
        return {}, false
    end

    api:log("Running pyright...")

    -- Build arguments: --outputjson [mode_args...] <path> [extra_args...]
    local args = {"--outputjson"}

    -- Add type checking mode args from config
    local pyright_mode = api:get_config("pyright_mode") or "default"
    local mode_args = PYRIGHT_MODE_ARGS[pyright_mode] or {}
    for _, arg in ipairs(mode_args) do
        table.insert(args, arg)
    end

    -- Add the path
    table.insert(args, path)

    -- Append extra arguments from config
    local extra_args = api:get_config("pyright_args") or ""
    if extra_args ~= "" then
        for _, arg in ipairs(split_args(extra_args)) do
            table.insert(args, arg)
        end
    end

    local result = api:run_command(pyright_cmd, table.unpack(args))
    if result and result.stdout and #result.stdout > 2 then
        return parse_pyright_output(result.stdout, api), true
    end
    return {}, true
end

-- Main lint function
function M.on_document_lint(api, path, content)
    if api:get_file_extension() ~= "py" or not path then
        return { diagnostics = {}, highlights = {} }
    end

    local all_diagnostics = {}
    local ruff_available = false
    local pyright_available = false

    -- Read enabled state from persistent config
    local ruff_enabled = is_ruff_enabled(api)
    local pyright_enabled = is_pyright_enabled(api)

    -- Run enabled tools
    if ruff_enabled then
        local diags, available = run_ruff(api, path)
        ruff_available = available
        for _, d in ipairs(diags) do
            table.insert(all_diagnostics, d)
        end
    end

    if pyright_enabled then
        local diags, available = run_pyright(api, path)
        pyright_available = available
        for _, d in ipairs(diags) do
            table.insert(all_diagnostics, d)
        end
    end

    api:log("Total: " .. #all_diagnostics .. " diagnostics")

    -- Show status if no tools are enabled
    if not ruff_enabled and not pyright_enabled then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Python Lint] All checks disabled" } }
    end

    -- Show status if no tools are available
    if not ruff_available and not pyright_available then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Python Lint] No linters found. Install via: pip install ruff pyright" } }
    end

    local highlights = {}
    for _, d in ipairs(all_diagnostics) do
        local color = d.level == "error" and "error" or (d.level == "warning" and "warning" or "info")
        table.insert(highlights, {
            line = d.line,
            inline = {{ start_col = d.column or 1, end_col = nil, color = color }}
        })
    end

    return { diagnostics = all_diagnostics, highlights = highlights }
end

function M.on_highlight_request(api, path, content)
    return M.on_document_lint(api, path, content)
end

-- Run only ruff (ignoring config for pyright_enabled)
local function run_ruff_only(api, path, content)
    if api:get_file_extension() ~= "py" or not path then
        return { diagnostics = {}, highlights = {} }
    end

    local diags, available = run_ruff(api, path)
    if not available then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Python Lint] ruff not found. Install via: pip install ruff" } }
    end

    local highlights = {}
    for _, d in ipairs(diags) do
        local color = d.level == "error" and "error" or (d.level == "warning" and "warning" or "info")
        table.insert(highlights, {
            line = d.line,
            inline = {{ start_col = d.column or 1, end_col = nil, color = color }}
        })
    end
    return { diagnostics = diags, highlights = highlights }
end

-- Run only pyright (ignoring config for ruff_enabled)
local function run_pyright_only(api, path, content)
    if api:get_file_extension() ~= "py" or not path then
        return { diagnostics = {}, highlights = {} }
    end

    local diags, available = run_pyright(api, path)
    if not available then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Python Lint] pyright not found. Install via: pip install pyright" } }
    end

    local highlights = {}
    for _, d in ipairs(diags) do
        local color = d.level == "error" and "error" or (d.level == "warning" and "warning" or "info")
        table.insert(highlights, {
            line = d.line,
            inline = {{ start_col = d.column or 1, end_col = nil, color = color }}
        })
    end
    return { diagnostics = diags, highlights = highlights }
end

-- Handle custom menu actions
function M.on_menu_action(api, action, path, content)
    if action == "lint" then
        -- Run all enabled checks (respects config toggles)
        return M.on_document_lint(api, path, content)

    elseif action == "run_ruff" then
        if api:get_file_extension() ~= "py" then
            return { status_message = { level = "warning", text = "Not a Python file" } }
        end
        return run_ruff_only(api, path, content)

    elseif action == "run_pyright" then
        if api:get_file_extension() ~= "py" then
            return { status_message = { level = "warning", text = "Not a Python file" } }
        end
        return run_pyright_only(api, path, content)
    end

    return {}
end

return M
