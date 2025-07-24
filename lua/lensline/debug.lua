local M = {}

local debug_file_path = nil
local session_id = nil

-- generate unique session id for this neovim instance
local function generate_session_id()
    return os.date("%Y%m%d_%H%M%S") .. "_" .. math.random(1000, 9999)
end

-- init debug logging for new session
function M.init()
    local config = require("lensline.config")
    local opts = config.get()
    
    if not opts.debug_mode then
        return
    end
    
    -- create debug dir in cache folder
    local cache_dir = vim.fn.stdpath("cache") .. "/lensline"
    vim.fn.mkdir(cache_dir, "p")
    
    -- generate new session id and file path
    session_id = generate_session_id()
    debug_file_path = cache_dir .. "/debug_" .. session_id .. ".log"
    
    -- cleanup old debug files  (keep only current session)
    local old_files = vim.fn.glob(cache_dir .. "/debug_*.log", true, true)
    for _, file in ipairs(old_files) do
        if file ~= debug_file_path then
            os.remove(file)
        end
    end
    
    -- write session header to file
    M.log("=== lensline debug session started ===")
    M.log("session id: " .. session_id)
    M.log("timestamp: " .. os.date("%Y-%m-%d %H:%M:%S"))
    M.log("neovim version: " .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)
    M.log("==========================================")
end

-- log a debug message to file
function M.log(message, level)
    local config = require("lensline.config")
    local opts = config.get()
    
    if not opts.debug_mode or not debug_file_path then
        return
    end
    
    level = level or "INFO"
    local timestamp = os.date("%H:%M:%S.") .. string.format("%03d", math.floor((os.clock() * 1000) % 1000))
    local log_line = string.format("[%s] [%s] %s\n", timestamp, level, message)
    
    -- write to the debug file
    local file = io.open(debug_file_path, "a")
    if file then
        file:write(log_line)
        file:close()
    end
end

-- log with context like function name, buffer etc
function M.log_context(context, message, level)
    local full_message = string.format("[%s] %s", context, message)
    M.log(full_message, level)
end

-- log lsp request/response data
function M.log_lsp_request(method, params, context)
    M.log_context(context or "LSP", "request: " .. method)
    M.log_context(context or "LSP", "params: " .. vim.inspect(params))
end

function M.log_lsp_response(method, results, context)
    M.log_context(context or "LSP", "response: " .. method)
    if results then
        local summary = {}
        for client_id, result in pairs(results) do
            if result.error then
                table.insert(summary, string.format("client %s: error - %s", client_id, vim.inspect(result.error)))
            elseif result.result then
                if type(result.result) == "table" then
                    table.insert(summary, string.format("client %s: %d results", client_id, #result.result))
                else
                    table.insert(summary, string.format("client %s: %s", client_id, vim.inspect(result.result)))
                end
            else
                table.insert(summary, string.format("client %s: no result", client_id))
            end
        end
        M.log_context(context or "LSP", "results: " .. table.concat(summary, ", "))
    else
        M.log_context(context or "LSP", "results: nil")
    end
end

-- get current debug file path
function M.get_debug_file()
    return debug_file_path
end

-- get session info for debugging
function M.get_session_info()
    return {
        id = session_id,
        file_path = debug_file_path,
        exists = debug_file_path and vim.fn.filereadable(debug_file_path) == 1
    }
end

return M