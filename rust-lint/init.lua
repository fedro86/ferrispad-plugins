-- Rust Lint Plugin for FerrisPad v1.3.0
local M = {
    name = "Rust Lint",
    version = "1.3.0",
    description = "Run clippy/cargo build on Rust files"
}

-- Helper to read boolean config (persisted across sessions)
local function is_clippy_enabled(api)
    local val = api:get_config("clippy_enabled")
    return val == nil or val == "true" or val == true
end

local function is_build_enabled(api)
    local val = api:get_config("build_enabled")
    return val == nil or val == "true" or val == true
end

-- Map clippy_level config to actual args
local CLIPPY_LEVEL_ARGS = {
    default = {},
    pedantic = {"-W", "clippy::pedantic"},
    all = {"-W", "clippy::all"},
    nursery = {"-W", "clippy::nursery"}
}

-- Parse cargo's JSON diagnostic output
-- Cargo outputs one JSON object per line with --message-format=json
local function parse_cargo_output(json_output, api, source_prefix)
    local diagnostics = {}

    -- Each line is a separate JSON message
    for line in json_output:gmatch("[^\r\n]+") do
        -- We're interested in "reason": "compiler-message"
        if line:match('"reason"%s*:%s*"compiler%-message"') then
            -- Extract the nested message object
            local level = line:match('"level"%s*:%s*"([^"]+)"')
            local message_text = line:match('"message"%s*:%s*"([^"]*)"')

            -- Extract spans (file location info)
            local line_start = line:match('"line_start"%s*:%s*(%d+)')
            local column_start = line:match('"column_start"%s*:%s*(%d+)')

            -- Extract code (e.g., "dead_code", "unused_variable")
            local code = line:match('"code"%s*:%s*{%s*"code"%s*:%s*"([^"]+)"')

            if message_text and line_start then
                -- Map cargo levels to FerrisPad levels
                local diag_level = "info"
                if level == "error" then
                    diag_level = "error"
                elseif level == "warning" then
                    diag_level = "warning"
                elseif level == "note" or level == "help" then
                    diag_level = "hint"
                end

                -- Build the message
                local full_message = source_prefix
                if code then
                    full_message = full_message .. code .. ": "
                end
                full_message = full_message .. message_text

                -- Generate documentation URL for clippy lints
                local url = nil
                if code and source_prefix == "[clippy] " then
                    url = "https://rust-lang.github.io/rust-clippy/master/index.html#" .. code
                end

                table.insert(diagnostics, {
                    line = tonumber(line_start),
                    column = tonumber(column_start),
                    message = full_message,
                    level = diag_level,
                    url = url
                })

                api:log("rust: " .. diag_level .. " at line " .. line_start .. ": " .. message_text:sub(1, 50))
            end
        end
    end

    return diagnostics
end

-- Check if we're in a Rust project (has Cargo.toml)
local function is_rust_project(api)
    local project_root = api:get_project_root()
    if project_root and api:file_exists(project_root .. "/Cargo.toml") then
        return true
    end

    -- Also check relative to file directory
    local file_dir = api:get_file_dir()
    if file_dir then
        -- Check current dir and up to 3 parent dirs
        local dirs = {
            file_dir,
            file_dir .. "/..",
            file_dir .. "/../..",
            file_dir .. "/../../.."
        }
        for _, dir in ipairs(dirs) do
            if api:file_exists(dir .. "/Cargo.toml") then
                return true
            end
        end
    end

    return false
end

-- Split a string by spaces (for extra args)
local function split_args(str)
    local args = {}
    for arg in str:gmatch("%S+") do
        table.insert(args, arg)
    end
    return args
end

-- Run clippy and collect diagnostics
local function run_clippy(api, path)
    api:log("Running cargo clippy...")

    -- Build arguments: clippy --message-format=json --quiet [level_args...] [extra_args...]
    local args = {"clippy", "--message-format=json", "--quiet"}

    -- Add clippy warning level args from config
    local clippy_level = api:get_config("clippy_level") or "default"
    local level_args = CLIPPY_LEVEL_ARGS[clippy_level] or {}
    for _, arg in ipairs(level_args) do
        table.insert(args, arg)
    end

    -- Append extra arguments from config
    local extra_args = api:get_config("clippy_args") or ""
    if extra_args ~= "" then
        for _, arg in ipairs(split_args(extra_args)) do
            table.insert(args, arg)
        end
    end

    local result = api:run_command("cargo", table.unpack(args))

    if result and result.stdout then
        return parse_cargo_output(result.stdout, api, "[clippy] ")
    end

    if result and result.stderr then
        api:log("clippy stderr: " .. result.stderr:sub(1, 200))
    end

    return {}
end

-- Run cargo build and collect diagnostics
local function run_build(api, path)
    api:log("Running cargo build...")

    -- Build arguments: build --message-format=json --quiet [--release] [extra_args...]
    local args = {"build", "--message-format=json", "--quiet"}

    -- Add release flag if configured
    local build_profile = api:get_config("build_profile") or "debug"
    if build_profile == "release" then
        table.insert(args, "--release")
    end

    -- Append extra arguments from config
    local extra_args = api:get_config("build_args") or ""
    if extra_args ~= "" then
        for _, arg in ipairs(split_args(extra_args)) do
            table.insert(args, arg)
        end
    end

    local result = api:run_command("cargo", table.unpack(args))

    if result and result.stdout then
        return parse_cargo_output(result.stdout, api, "[build] ")
    end

    if result and result.stderr then
        api:log("build stderr: " .. result.stderr:sub(1, 200))
    end

    return {}
end

-- Main lint function
function M.on_document_lint(api, path, content)
    if api:get_file_extension() ~= "rs" or not path then
        return nil
    end

    -- Check if cargo is installed (similar to Python lint checking for ruff/pyright)
    if not api:command_exists("cargo") then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Rust Lint] cargo not found. Install via: rustup.rs" } }
    end

    if not is_rust_project(api) then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "info", text = "[Rust Lint] No Cargo.toml found" } }
    end

    local all_diagnostics = {}

    -- Read enabled state from persistent config
    local clippy_enabled = is_clippy_enabled(api)
    local build_enabled = is_build_enabled(api)

    -- Run enabled tools
    if clippy_enabled then
        local diags = run_clippy(api, path)
        for _, d in ipairs(diags) do
            table.insert(all_diagnostics, d)
        end
    end

    if build_enabled then
        local diags = run_build(api, path)
        for _, d in ipairs(diags) do
            table.insert(all_diagnostics, d)
        end
    end

    api:log("Total: " .. #all_diagnostics .. " diagnostics")

    -- Show status if no tools are enabled
    if not clippy_enabled and not build_enabled then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Rust Lint] All checks disabled" } }
    end

    -- Generate highlights
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

-- Run only clippy (ignoring config for build_enabled)
local function run_clippy_only(api, path, content)
    if api:get_file_extension() ~= "rs" or not path then
        return nil
    end

    if not api:command_exists("cargo") then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Rust Lint] cargo not found" } }
    end

    if not is_rust_project(api) then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "info", text = "[Rust Lint] No Cargo.toml found" } }
    end

    local diags = run_clippy(api, path)
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

-- Run only build (ignoring config for clippy_enabled)
local function run_build_only(api, path, content)
    if api:get_file_extension() ~= "rs" or not path then
        return nil
    end

    if not api:command_exists("cargo") then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "warning", text = "[Rust Lint] cargo not found" } }
    end

    if not is_rust_project(api) then
        return { diagnostics = {}, highlights = {},
            status_message = { level = "info", text = "[Rust Lint] No Cargo.toml found" } }
    end

    local diags = run_build(api, path)
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

-- Handle menu actions
function M.on_menu_action(api, action, path, content)
    if action == "lint" then
        -- Run all enabled checks (respects config toggles)
        return M.on_document_lint(api, path, content)

    elseif action == "run_clippy" then
        if api:get_file_extension() ~= "rs" then
            return { status_message = { level = "warning", text = "Not a Rust file" } }
        end
        return run_clippy_only(api, path, content)

    elseif action == "run_build" then
        if api:get_file_extension() ~= "rs" then
            return { status_message = { level = "warning", text = "Not a Rust file" } }
        end
        return run_build_only(api, path, content)
    end

    return {}
end

return M
