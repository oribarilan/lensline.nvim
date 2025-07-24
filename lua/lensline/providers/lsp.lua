local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")

local M = {}

-- recursively extract function symbols from lsp document symbols
local function get_function_symbols(symbols, results)
    results = results or {}
    
    for _, symbol in ipairs(symbols) do
        -- check if this is a function, method or constructor
        if symbol.kind == vim.lsp.protocol.SymbolKind.Function or
           symbol.kind == vim.lsp.protocol.SymbolKind.Method or
           symbol.kind == vim.lsp.protocol.SymbolKind.Constructor then
            -- try to use selection range (function name) if available, fallback to range start
            local position
            if symbol.selectionRange then
                position = {
                    line = symbol.selectionRange.start.line,
                    character = symbol.selectionRange.start.character,
                }
            else
                position = {
                    line = symbol.range.start.line,
                    character = symbol.range.start.character,
                }
            end
            
            table.insert(results, {
                name = symbol.name,
                line = position.line,
                character = position.character,
            })
        end
        
        -- recurse into children if they exist
        if symbol.children then
            get_function_symbols(symbol.children, results)
        end
    end
    
    return results
end

local function collect_functions(bufnr, callback)
    local clients = utils.get_lsp_clients(bufnr)
    
    debug.log_context("LSP", "Checking LSP clients for buffer " .. bufnr)
    debug.log_context("LSP", "Found " .. (clients and #clients or 0) .. " LSP clients")
    
    for i, client in ipairs(clients or {}) do
        debug.log_context("LSP", "Client " .. i .. " name: " .. client.name .. " id: " .. client.id)
    end
    
    if not clients or #clients == 0 then
        debug.log_context("LSP", "No LSP clients available", "WARN")
        callback({})
        return
    end
    
    -- check root directory detection using .git folder
    local root_dir = vim.fs.find(".git", { upward = true, type = "directory" })
    if not root_dir or #root_dir == 0 then
        debug.log_context("LSP", "no .git root directory found", "WARN")
        callback({})
        return
    end
    
    debug.log_context("LSP", "found root directory: " .. root_dir[1])
    
    -- check if any client supports textDocument/references
    local supports_references = false
    for _, client in ipairs(clients) do
        if client.supports_method("textDocument/references") then
            supports_references = true
            debug.log_context("LSP", "client " .. client.name .. " supports textDocument/references")
        else
            debug.log_context("LSP", "client " .. client.name .. " does NOT support textDocument/references", "WARN")
        end
    end
    
    if not supports_references then
        debug.log_context("LSP", "no lsp clients support textDocument/references", "ERROR")
        callback({})
        return
    end
    
    debug.log_lsp_request("textDocument/documentSymbol", {
        textDocument = vim.lsp.util.make_text_document_params(bufnr)
    }, "LSP")
    
    vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", {
        textDocument = vim.lsp.util.make_text_document_params(bufnr)
    }, function(results)
        local functions = {}
        
        debug.log_context("LSP", "Got document symbol results from " .. (results and vim.tbl_count(results) or 0) .. " clients")
        
        for client_id, result in pairs(results) do
            if result.error then
                debug.log_context("LSP", "Client " .. client_id .. " returned error: " .. vim.inspect(result.error), "ERROR")
            elseif result.result then
                debug.log_context("LSP", "Client " .. client_id .. " returned " .. #result.result .. " symbols")
            else
                debug.log_context("LSP", "Client " .. client_id .. " returned no result", "WARN")
            end
            
            if result.result then
                local symbols = get_function_symbols(result.result)
                for _, symbol in ipairs(symbols) do
                    table.insert(functions, symbol)
                end
            end
        end
        
        debug.log_context("LSP", "Found " .. #functions .. " total functions")
        callback(functions)
    end)
end

local function count_references(bufnr, position, callback)
    debug.log_context("LSP", "requesting references for position " .. vim.inspect(position))
    
    -- check that we have lsp clients that support references
    local clients = utils.get_lsp_clients(bufnr)
    if not clients or #clients == 0 then
        debug.log_context("LSP", "no lsp clients available for reference request", "WARN")
        callback(0)
        return
    end
    
    -- create proper position params using the specific position passed to this function
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = position,
        context = { includeDeclaration = false }
    }
    
    debug.log_lsp_request("textDocument/references", params, "LSP")
    
    -- set a timeout to detect if the request hangs
    local timeout_timer = vim.fn.timer_start(5000, function()
        debug.log_context("LSP", "reference request timed out after 5 seconds", "ERROR")
        callback(0)
    end)
    
    vim.lsp.buf_request_all(bufnr, "textDocument/references", params, function(results)
        -- cancel timeout since we got a response
        vim.fn.timer_stop(timeout_timer)
        
        local total_count = 0
        
        debug.log_lsp_response("textDocument/references", results, "LSP")
        
        -- count refs from all lsp clients
        for client_id, result in pairs(results) do
            if result.result and type(result.result) == "table" then
                total_count = total_count + #result.result
            end
        end
        
        debug.log_context("LSP", "total reference count: " .. total_count)
        
        -- no need to subtract 1 since we set includeDeclaration = false
        
        callback(total_count)
    end)
end

function M.get_lens_data(bufnr, callback)
    debug.log_context("LSP", "get_lens_data called for buffer " .. bufnr)
    
    if not utils.is_valid_buffer(bufnr) then
        debug.log_context("LSP", "Buffer " .. bufnr .. " is not valid", "WARN")
        callback({})
        return
    end
    
    collect_functions(bufnr, function(functions)
        debug.log_context("LSP", "Found " .. #functions .. " functions")
        for _, func in ipairs(functions) do
            debug.log_context("LSP", "Function: " .. func.name .. " at line " .. func.line)
        end
        
        if #functions == 0 then
            debug.log_context("LSP", "No functions found, returning empty lens data")
            callback({})
            return
        end
        
        local lens_data = {}
        local pending_requests = #functions
        
        for _, func in ipairs(functions) do
            count_references(bufnr, {
                line = func.line,
                character = func.character
            }, function(count)
                debug.log_context("LSP", "Function " .. func.name .. " has " .. count .. " references")
                
                table.insert(lens_data, {
                    line = func.line,
                    character = func.character,
                    text_parts = { utils.format_reference_count(count) }
                })
                
                pending_requests = pending_requests - 1
                if pending_requests == 0 then
                    table.sort(lens_data, function(a, b) return a.line < b.line end)
                    debug.log_context("LSP", "All reference requests completed, returning " .. #lens_data .. " lens items")
                    callback(lens_data)
                end
            end)
        end
    end)
end

-- add debug command to show trace file
vim.api.nvim_create_user_command("LenslineDebug", function()
    local session_info = debug.get_session_info()
    
    if not session_info.exists then
        print("lensline debug: no debug session active or debug_mode is disabled")
        print("enable debug mode with: require('lensline').setup({ debug_mode = true })")
        return
    end
    
    print("lensline debug session info:")
    print("  session id: " .. (session_info.id or "n/a"))
    print("  debug file: " .. (session_info.file_path or "n/a"))
    print("")
    
    -- open the debug file in a new buffer
    vim.cmd("tabnew " .. vim.fn.fnameescape(session_info.file_path))
    vim.bo.filetype = "log"
    vim.bo.readonly = true
    vim.bo.modifiable = false
    
    print("debug trace opened in new tab. file: " .. session_info.file_path)
end, {})

return M