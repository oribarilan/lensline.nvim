local M = {}

-- LRU cache for function discovery results per buffer
-- Only caches document symbols (safe)
local function_cache = {}
local buffer_changedtick = {}
local cache_access_order = {} -- Track access order for LRU eviction
local MAX_CACHE_SIZE = 50 -- Limit cache to 50 buffers maximum

-- Expose cache for stale data access (used by executor for immediate rendering)
M.function_cache = function_cache

-- LRU cache management functions
local function update_access_order(bufnr)
  -- Remove bufnr from current position if it exists
  for i, cached_bufnr in ipairs(cache_access_order) do
    if cached_bufnr == bufnr then
      table.remove(cache_access_order, i)
      break
    end
  end
  -- Add to end (most recently used)
  table.insert(cache_access_order, bufnr)
end

local function evict_lru_if_needed()
  while #cache_access_order > MAX_CACHE_SIZE do
    local lru_bufnr = table.remove(cache_access_order, 1) -- Remove least recently used
    function_cache[lru_bufnr] = nil
    buffer_changedtick[lru_bufnr] = nil
  end
end

-- Helper to get lsp clients (works with newer and older nvim versions)
function M.get_lsp_clients(bufnr)
  if vim.lsp.get_clients then
    return vim.lsp.get_clients({ bufnr = bufnr })
  else
    return vim.lsp.get_active_clients({ bufnr = bufnr })
  end
end

-- Check if any LSP client supports a specific method for the buffer
function M.has_lsp_capability(bufnr, method)
  local clients = M.get_lsp_clients(bufnr)
  if not clients or #clients == 0 then
    return false
  end
  
  for _, client in ipairs(clients) do
    -- Check if client supports the method
    if client.server_capabilities then
      -- Only check the methods we actually use in this plugin
      local capability_map = {
        ["textDocument/references"] = "referencesProvider",
        ["textDocument/documentSymbol"] = "documentSymbolProvider",
      }
      
      local capability_key = capability_map[method]
      if capability_key and client.server_capabilities[capability_key] then
        return true
      end
    end
  end
  
  return false
end

-- Main function discovery API - discovers functions in a given range (async)
function M.discover_functions_async(bufnr, start_line, end_line, callback)
  -- Apply limits truncation to end_line
  local limits = require("lensline.limits")
  local truncated_end_line = limits.get_truncated_end_line(bufnr, end_line)
  
  if truncated_end_line == 0 then
    -- File should be skipped entirely
    callback({})
    return
  end
  
  -- Only use LSP document symbols - no fallbacks
  M.find_functions_via_lsp_async(bufnr, start_line, truncated_end_line, callback)
end

-- Backward compatibility: sync wrapper (for potential fallback use)
function M.discover_functions(bufnr, start_line, end_line)
  -- Apply limits truncation to end_line
  local limits = require("lensline.limits")
  local truncated_end_line = limits.get_truncated_end_line(bufnr, end_line)
  
  if truncated_end_line == 0 then
    -- File should be skipped entirely
    return {}
  end
  
  -- Only use LSP document symbols - no fallbacks
  return M.find_functions_via_lsp(bufnr, start_line, truncated_end_line)
end

-- Use LSP document symbols to find functions (async version - eliminates UI hang)
function M.find_functions_via_lsp_async(bufnr, start_line, end_line, callback)
  local debug = require("lensline.debug")
  debug.log_context("Performance", "ASYNC FUNCTION DISCOVERY CALLED for buffer " .. bufnr .. " (lines " .. start_line .. "-" .. end_line .. ")")
  
  local clients = M.get_lsp_clients(bufnr)
  if not clients or #clients == 0 then
    debug.log_context("Performance", "ASYNC FUNCTION DISCOVERY SKIPPED - no LSP clients")
    callback({})
    return
  end
  
  -- Check if any LSP client supports document symbols
  if not M.has_lsp_capability(bufnr, "textDocument/documentSymbol") then
    callback({})
    return
  end
  
  -- Check cache validity using buffer's changedtick
  local current_changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache_key = bufnr
  
  if function_cache[cache_key] and buffer_changedtick[cache_key] == current_changedtick then
    -- Cache hit - update LRU order and filter functions for requested range
    update_access_order(cache_key)
    local cached_functions = function_cache[cache_key]
    local filtered_functions = {}
    for _, func in ipairs(cached_functions) do
      if func.line >= start_line and func.line <= end_line then
        table.insert(filtered_functions, func)
      end
    end
    callback(filtered_functions)
    return
  end
  
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr)
  }
  
  -- Add timing logs around the async LSP call
  local start_time = vim.loop.hrtime()
  debug.log_context("Performance", "ASYNC LSP CALL START - textDocument/documentSymbol for buffer " .. bufnr)
  
  vim.lsp.buf_request(bufnr, "textDocument/documentSymbol", params, function(err, results)
    local end_time = vim.loop.hrtime()
    local duration_ms = (end_time - start_time) / 1000000  -- Convert to milliseconds
    debug.log_context("Performance", "ASYNC LSP CALL END - duration: " .. string.format("%.2f", duration_ms) .. "ms")
    
    if err or not results then
      debug.log_context("Performance", "ASYNC LSP CALL FAILED - err: " .. tostring(err) .. ", results: " .. tostring(results ~= nil))
      callback({})
      return
    end
    
    local functions = {}
    
    -- Process async results - different format than sync version
    -- In async callback, 'results' is the direct LSP response, not wrapped in client responses
    debug.log_context("Performance", "ASYNC PROCESSING - results type: " .. type(results) .. ", length: " .. (results and #results or 0))
    
    if results and type(results) == "table" then
      M.extract_symbols_recursive(results, functions, 1, math.huge)
    end
    
    debug.log_context("Performance", "ASYNC SYMBOL EXTRACTION - found " .. #functions .. " functions")
    
    -- Cache the complete function list for this buffer with LRU management
    -- NOTE: Race condition possible here - if rapid saves occur, an older
    -- request might overwrite newer cache data. This causes temporary stale
    -- lenses until next edit. Can add changedtick validation if needed:
    -- if vim.api.nvim_buf_get_changedtick(bufnr) == current_changedtick then
    function_cache[cache_key] = functions
    buffer_changedtick[cache_key] = current_changedtick
    update_access_order(cache_key)
    evict_lru_if_needed()
    
    -- Return filtered results for the requested range
    local filtered_functions = {}
    for _, func in ipairs(functions) do
      if func.line >= start_line and func.line <= end_line then
        table.insert(filtered_functions, func)
      end
    end
    
    callback(filtered_functions)
  end)
end

-- Use LSP document symbols to find functions (sync version - kept for backward compatibility)
function M.find_functions_via_lsp(bufnr, start_line, end_line)
  local debug = require("lensline.debug")
  debug.log_context("Performance", "FUNCTION DISCOVERY CALLED for buffer " .. bufnr .. " (lines " .. start_line .. "-" .. end_line .. ")")
  
  local clients = M.get_lsp_clients(bufnr)
  if not clients or #clients == 0 then
    debug.log_context("Performance", "FUNCTION DISCOVERY SKIPPED - no LSP clients")
    return {}
  end
  
  -- Check if any LSP client supports document symbols
  if not M.has_lsp_capability(bufnr, "textDocument/documentSymbol") then
    return {}
  end
  
  -- Check cache validity using buffer's changedtick
  local current_changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache_key = bufnr
  
  if function_cache[cache_key] and buffer_changedtick[cache_key] == current_changedtick then
    -- Cache hit - update LRU order and filter functions for requested range
    update_access_order(cache_key)
    local cached_functions = function_cache[cache_key]
    local filtered_functions = {}
    for _, func in ipairs(cached_functions) do
      if func.line >= start_line and func.line <= end_line then
        table.insert(filtered_functions, func)
      end
    end
    return filtered_functions
  end
  
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr)
  }
  
  -- Add timing logs around the sync LSP call
  local start_time = vim.loop.hrtime()
  debug.log_context("Performance", "SYNC LSP CALL START - textDocument/documentSymbol for buffer " .. bufnr)
  
  local ok, results = pcall(vim.lsp.buf_request_sync, bufnr, "textDocument/documentSymbol", params, 1000)
  
  local end_time = vim.loop.hrtime()
  local duration_ms = (end_time - start_time) / 1000000  -- Convert to milliseconds
  debug.log_context("Performance", "SYNC LSP CALL END - duration: " .. string.format("%.2f", duration_ms) .. "ms")
  
  if not ok or not results then
    debug.log_context("Performance", "SYNC LSP CALL FAILED - ok: " .. tostring(ok) .. ", results: " .. tostring(results ~= nil))
    return {}
  end
  
  local functions = {}
  
  -- Process results from all clients (get ALL functions for caching)
  for _, result in pairs(results) do
    if result.result then
      M.extract_symbols_recursive(result.result, functions, 1, math.huge)
    end
  end
  
  -- Cache the complete function list for this buffer with LRU management
  function_cache[cache_key] = functions
  buffer_changedtick[cache_key] = current_changedtick
  update_access_order(cache_key)
  evict_lru_if_needed()
  
  -- Return filtered results for the requested range
  local filtered_functions = {}
  for _, func in ipairs(functions) do
    if func.line >= start_line and func.line <= end_line then
      table.insert(filtered_functions, func)
    end
  end
  
  return filtered_functions
end

-- Recursively extract function/method symbols from LSP response
-- Helper function to identify legitimately named functions (not anonymous)
local function is_named_function(symbol)
  -- Only check Functions, not Methods or Constructors
  if symbol.kind ~= vim.lsp.protocol.SymbolKind.Function then
    return false
  end
  
  -- Must have a name
  if not symbol.name then
    return false
  end
  
  -- Name must not be empty/whitespace
  if not symbol.name:match("%S") then
    return false
  end
  
  -- Skip generic names that indicate anonymous functions
  local lower_name = symbol.name:lower()
  if lower_name == "function" or
     lower_name == "lambda" or
     lower_name == "anonymous" or
     symbol.name:match("^function%(") or    -- Lua-style "function(" pattern
     symbol.name:match("^vim%.") then       -- Skip Neovim API wrappers
    return false
  end
  
  return true
end

function M.extract_symbols_recursive(symbols, functions, start_line, end_line)
  for _, symbol in ipairs(symbols) do
    -- Identify symbol kinds we care about (function / method / constructor)
    local symbol_kinds = {
      [vim.lsp.protocol.SymbolKind.Function] = true,
      [vim.lsp.protocol.SymbolKind.Method] = true,
      [vim.lsp.protocol.SymbolKind.Constructor] = true,
    }

    if symbol_kinds[symbol.kind] then
      local include = true
      -- Only add plain Functions if they are "named" per our heuristic
      if symbol.kind == vim.lsp.protocol.SymbolKind.Function and not is_named_function(symbol) then
        include = false -- (previously used Lua 5.2 goto to "continue"; rewritten for 5.1 portability)
      end

      if include then
        local line_num
        local end_line_num
        local character

        -- Handle both DocumentSymbol and SymbolInformation formats
        if symbol.range then
          -- DocumentSymbol format
          line_num = symbol.range.start.line + 1 -- Convert to 1-indexed
          end_line_num = symbol.range["end"].line + 1 -- Convert to 1-indexed
          character = symbol.range.start.character
        elseif symbol.location then
          -- SymbolInformation format
          line_num = symbol.location.range.start.line + 1
          end_line_num = symbol.location.range["end"].line + 1
          character = symbol.location.range.start.character
        end

        if line_num and line_num >= start_line and line_num <= end_line then
          table.insert(functions, {
            line = line_num,
            end_line = end_line_num,
            character = character,
            name = symbol.name,
            kind = symbol.kind
          })
        end
      end
    end
    -- Recursively process children if they exist
    if symbol.children then
      M.extract_symbols_recursive(symbol.children, functions, start_line, end_line)
    end
  end
end

-- Cleanup function cache
function M.cleanup_cache()
  local debug = require("lensline.debug")
  debug.log_context("LensExplorer", "cleaning up function discovery cache")
  
  function_cache = {}
  buffer_changedtick = {}
  cache_access_order = {}
end

return M