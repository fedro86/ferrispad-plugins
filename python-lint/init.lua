-- Python Linter Plugin for FerrisPad v2.1.0
local M = {
    name = "Python Lint",
    version = "2.1.0",
    description = "Run ruff/pyright on Python files (supports project venv)"
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

-- Main lint function
function M.on_document_lint(api, path, content)
    if api:get_file_extension() ~= "py" or not path then
        return { diagnostics = {}, highlights = {} }
    end

    local all_diagnostics = {}
    local ruff_cmd = find_command(api, "ruff")
    local pyright_cmd = find_command(api, "pyright")

    if ruff_cmd then
        local result = api:run_command(ruff_cmd, "check", "--output-format=json", path)
        if result and result.stdout and #result.stdout > 2 then
            for _, d in ipairs(parse_ruff_output(result.stdout, api)) do
                table.insert(all_diagnostics, d)
            end
        end
    end

    if pyright_cmd then
        local result = api:run_command(pyright_cmd, "--outputjson", path)
        if result and result.stdout and #result.stdout > 2 then
            for _, d in ipairs(parse_pyright_output(result.stdout, api)) do
                table.insert(all_diagnostics, d)
            end
        end
    end

    api:log("Total: " .. #all_diagnostics .. " diagnostics")

    if not ruff_cmd and not pyright_cmd then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Python Lint] No linters found" } }
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

-- Handle custom menu actions
function M.on_menu_action(api, action, path, content)
    if action == "lint" then
        return M.on_document_lint(api, path, content)
    end
    return {}
end

return M
