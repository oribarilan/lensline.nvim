local M = {}

local debug_file_path = nil
local session_id = nil

-- Log rotation constants
local MAX_LOG_SIZE = 512000  -- 500KB in bytes
local MAX_ROTATED_FILES = 2  -- Keep .log.1 and .log.2

-- Buffered logging state
local log_buffer = {}           -- Array of formatted log lines
local buffer_count = 0          -- Current buffer size (more efficient than #log_buffer)
local BUFFER_SIZE_LIMIT = 100   -- Flush threshold
local exit_handler_registered = false

-- generate unique session id for this neovim instance
local function generate_session_id()
    return os.date("%Y%m%d_%H%M%S") .. "_" .. math.random(1000, 9999)
end

-- get file size in bytes
local function get_file_size(filepath)
    local stat = vim.loop.fs_stat(filepath)
    return stat and stat.size or 0
end

-- rotate log files: .log -> .log.1 -> .log.2 -> delete
local function rotate_log_files()
    if not debug_file_path then
        return
    end
    
    -- Remove oldest rotated file (.log.2)
    local log2_path = debug_file_path .. ".2"
    if vim.fn.filereadable(log2_path) == 1 then
        os.remove(log2_path)
    end
    
    -- Move .log.1 to .log.2
    local log1_path = debug_file_path .. ".1"
    if vim.fn.filereadable(log1_path) == 1 then
        os.rename(log1_path, log2_path)
    end
    
    -- Move current .log to .log.1
    if vim.fn.filereadable(debug_file_path) == 1 then
        os.rename(debug_file_path, log1_path)
    end
end

-- check if log rotation is needed and rotate if necessary
local function rotate_if_needed()
    if not debug_file_path then
        return
    end
    
    local current_size = get_file_size(debug_file_path)
    if current_size >= MAX_LOG_SIZE then
        rotate_log_files()
    end
end

-- flush buffer to file (internal function)
local function flush_buffer_to_file()
    if buffer_count == 0 or not debug_file_path then
        return true -- Nothing to flush or debug disabled
    end
    
    -- Check if rotation needed before writing buffer
    rotate_if_needed()
    
    -- Atomic operation: copy buffer, reset state, then write
    local lines_to_write = {}
    for i = 1, buffer_count do
        lines_to_write[i] = log_buffer[i]
    end
    
    -- Reset buffer state immediately
    log_buffer = {}
    buffer_count = 0
    
    -- Write all lines in single file operation
    local file = io.open(debug_file_path, "a")
    if not file then
        -- Restore buffer on failure
        log_buffer = lines_to_write
        buffer_count = #lines_to_write
        return false
    end
    
    for _, line in ipairs(lines_to_write) do
        file:write(line)
    end
    file:close()
    return true
end

-- add log line to buffer and flush if needed
local function add_to_buffer(formatted_line)
    buffer_count = buffer_count + 1
    log_buffer[buffer_count] = formatted_line
    
    -- Flush if buffer limit reached
    if buffer_count >= BUFFER_SIZE_LIMIT then
        vim.schedule(function()
            flush_buffer_to_file()
        end)
    end
end

-- ensure exit handler is registered to flush on shutdown
local function ensure_exit_handler()
    if exit_handler_registered then
        return
    end
    
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            flush_buffer_to_file()
        end,
        desc = "Flush lensline debug buffer on exit"
    })
    exit_handler_registered = true
end

-- init debug logging for new session
function M.init()
    local config = require("lensline.config")
    local opts = config.get()
    
    if not opts.debug_mode then
        -- Ensure debug_file_path is nil when debug is disabled
        debug_file_path = nil
        session_id = nil
        return
    end
    
    -- create debug dir in cache folder
    local cache_dir = vim.fn.stdpath("cache") .. "/lensline"
    vim.fn.mkdir(cache_dir, "p")
    
    -- generate new session id and file path
    session_id = generate_session_id()
    debug_file_path = cache_dir .. "/debug_" .. session_id .. ".log"
    
    -- cleanup old debug files (keep only current session)
    -- This includes both main log files and rotated files (.log.1, .log.2)
    local old_files = vim.fn.glob(cache_dir .. "/debug_*.log*", true, true)
    local current_session_prefix = debug_file_path
    for _, file in ipairs(old_files) do
        -- Keep files that match current session pattern: debug_SESSION.log, debug_SESSION.log.1, debug_SESSION.log.2
        if not (file == debug_file_path or
                file == debug_file_path .. ".1" or
                file == debug_file_path .. ".2") then
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

-- log a debug message using buffered approach
function M.log(message, level)
    local config = require("lensline.config")
    local opts = config.get()
    
    if not opts.debug_mode then
        return
    end
    
    -- Lazy initialization: if debug_mode is true but debug system isn't initialized yet, do it now
    if not debug_file_path then
        M.init()
    end
    
    if not debug_file_path then
        return -- init failed, still no debug_file_path
    end
    
    -- Ensure exit handler is registered
    ensure_exit_handler()
    
    level = level or "INFO"
    local timestamp = os.date("%H:%M:%S.") .. string.format("%03d", math.floor((os.clock() * 1000) % 1000))
    local log_line = string.format("[%s] [%s] %s\n", timestamp, level, message)
    
    -- Add to buffer instead of immediate write
    add_to_buffer(log_line)
end

-- manually flush the log buffer (useful for testing)
function M.flush()
    if buffer_count > 0 then
        return flush_buffer_to_file()
    end
    return true
end

-- log with context like function name, buffer etc
function M.log_context(context, message, ...)
    local args = {...}
    local level = "INFO"
    local format_args = {}
    
    for i, arg in ipairs(args) do
        if i == #args and type(arg) == "string" and 
           (arg == "INFO" or arg == "WARN" or arg == "ERROR" or arg == "DEBUG") then
            level = arg
        else
            table.insert(format_args, arg)
        end
    end
    
    local formatted_message = message
    if #format_args > 0 then
        formatted_message = string.format(message, unpack(format_args))
    end
    
    local full_message = string.format("[%s] %s", context, formatted_message)
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
        exists = debug_file_path and vim.fn.filereadable(debug_file_path) == 1,
        buffer_count = buffer_count,  -- Add buffer state info
        buffer_limit = BUFFER_SIZE_LIMIT
    }
end

-- debug function to test lsp provider directly
function M.test_lsp_provider()
    local lsp_provider = require("lensline.providers.lsp")
    local bufnr = vim.api.nvim_get_current_buf()
    
    print("lensline: testing lsp provider for buffer", bufnr)
    lsp_provider.get_lens_data(bufnr, function(lens_data)
        print("lensline: got lens data with", #lens_data, "entries")
        for i, lens in ipairs(lens_data) do
            print("lensline:", i, "line", lens.line, "text:", vim.inspect(lens.text_parts))
        end
    end)
end

-- test manual reference request at cursor position
function M.test_manual_references()
    local bufnr = vim.api.nvim_get_current_buf()
    
    -- use proper position params as per guidelines
    local params = vim.lsp.util.make_position_params()
    params.context = { includeDeclaration = false }
    
    print("lensline: manual test with proper params:", vim.inspect(params))
    
    vim.lsp.buf_request_all(bufnr, "textDocument/references", params, function(results)
        print("lensline: manual reference results:")
        for client_id, result in pairs(results) do
            if result.error then
                print("lensline: client", client_id, "error:", vim.inspect(result.error))
            elseif result.result then
                print("lensline: client", client_id, "found", #result.result, "references")
                for i, ref in ipairs(result.result) do
                    print("lensline:   ", i, vim.inspect(ref))
                end
            else
                print("lensline: client", client_id, "no result")
            end
        end
    end)
end

return M