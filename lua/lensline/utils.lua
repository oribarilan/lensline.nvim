local M = {}

-- LRU cache for function discovery results per buffer
-- Only caches document symbols (safe)
local function_cache = {}
local buffer_changedtick = {}
local cache_access_order = {} -- Track access order for LRU eviction
local MAX_CACHE_SIZE = 50 -- Limit cache to 50 buffers maximum

function M.debounce(fn, delay)
    local timer = vim.loop.new_timer()
    return function(...)
        local args = { ... }
        timer:stop()
        timer:start(delay, 0, function()
            vim.schedule(function()
                fn(unpack(args))
            end)
        end)
    end, timer  -- Return timer for proper cleanup
end

function M.is_valid_buffer(bufnr)
    return bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

-- helper to get lsp clients  (works with newer and older nvim versions)
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


-- LSP-only function discovery using document symbols
function M.find_functions_in_range(bufnr, start_line, end_line)
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

-- Use LSP document symbols to find functions (most reliable approach)
function M.find_functions_via_lsp(bufnr, start_line, end_line)
  local clients = M.get_lsp_clients(bufnr)
  if not clients or #clients == 0 then
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
  
  local ok, results = pcall(vim.lsp.buf_request_sync, bufnr, "textDocument/documentSymbol", params, 1000)
  if not ok or not results then
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
function M.extract_symbols_recursive(symbols, functions, start_line, end_line)
  for _, symbol in ipairs(symbols) do
    -- Check if this symbol is a function, method, or constructor
    local symbol_kinds = {
      [vim.lsp.protocol.SymbolKind.Function] = true,
      [vim.lsp.protocol.SymbolKind.Method] = true,
      [vim.lsp.protocol.SymbolKind.Constructor] = true,
    }
    
    if symbol_kinds[symbol.kind] then
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
    
    -- Recursively process children if they exist
    if symbol.children then
      M.extract_symbols_recursive(symbol.children, functions, start_line, end_line)
    end
  end
end

-- Language-agnostic treesitter approach using common patterns
function M.find_functions_via_treesitter(bufnr, start_line, end_line)
  if not vim.treesitter.get_parser then
    return {}
  end
  
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return {}
  end
  
  local lang = parser:lang()
  local functions = {}
  local tree = parser:parse()[1]
  if not tree then
    return {}
  end
  
  -- Language-specific queries for better accuracy
  local language_queries = {
    python = [[
      (function_definition name: (identifier) @func.name) @func.def
      (async_function_definition name: (identifier) @func.name) @func.def
    ]],
    javascript = [[
      (function_declaration name: (identifier) @func.name) @func.def
      (method_definition name: (property_identifier) @func.name) @func.def
      (arrow_function) @func.def
    ]],
    typescript = [[
      (function_declaration name: (identifier) @func.name) @func.def
      (method_definition name: (property_identifier) @func.name) @func.def
      (arrow_function) @func.def
    ]],
    c_sharp = [[
      (method_declaration name: (identifier) @func.name) @func.def
      (constructor_declaration name: (identifier) @func.name) @func.def
      (operator_declaration) @func.def
    ]],
    java = [[
      (method_declaration name: (identifier) @func.name) @func.def
      (constructor_declaration name: (identifier) @func.name) @func.def
    ]],
    go = [[
      (function_declaration name: (identifier) @func.name) @func.def
      (method_declaration name: (field_identifier) @func.name) @func.def
    ]],
    rust = [[
      (function_item name: (identifier) @func.name) @func.def
      (impl_item (function_item name: (identifier) @func.name)) @func.def
    ]],
    lua = [[
      (function_statement name: (identifier) @func.name) @func.def
      (local_function_statement name: (identifier) @func.name) @func.def
    ]]
  }
  
  local query_string = language_queries[lang]
  if not query_string then
    -- Generic fallback query that works for many C-style languages
    query_string = [[
      (function_declaration name: (identifier) @func.name) @func.def
      (method_declaration name: (_) @func.name) @func.def
      (function_definition name: (identifier) @func.name) @func.def
    ]]
  end
  
  local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not ok_query then
    return {}
  end
  
  for id, node, metadata in query:iter_captures(tree:root(), bufnr, start_line - 1, end_line) do
    if query.captures[id] == "func.def" then
      local row, col = node:start()
      local line_num = row + 1 -- Convert to 1-indexed
      
      if line_num >= start_line and line_num <= end_line then
        table.insert(functions, {
          line = line_num,
          character = col,
          node = node
        })
      end
    end
  end
  
  return functions
end

-- Enhanced generic function detection with more language patterns
function M.find_functions_generic(bufnr, start_line, end_line)
  local functions = {}
  
  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  
  -- Expanded patterns for more languages
  local patterns = {
    -- Python
    "^%s*def%s+([%w_]+)",
    "^%s*async%s+def%s+([%w_]+)",
    -- JavaScript/TypeScript
    "^%s*function%s+([%w_]+)",
    "^%s*([%w_]+)%s*:%s*function",
    "^%s*([%w_]+)%s*=%s*function",
    "^%s*([%w_]+)%s*=%s*%([^%)]*%)%s*=>",
    -- C#
    "^%s*public%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    "^%s*private%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    "^%s*protected%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    "^%s*internal%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    "^%s*static%s+[%w%s]*%s+([%w_]+)%s*%(.*%)",
    -- Java
    "^%s*public%s+[%w%s<>%[%]]*%s+([%w_]+)%s*%(.*%)",
    "^%s*private%s+[%w%s<>%[%]]*%s+([%w_]+)%s*%(.*%)",
    "^%s*protected%s+[%w%s<>%[%]]*%s+([%w_]+)%s*%(.*%)",
    -- Go
    "^%s*func%s+([%w_]+)",
    "^%s*func%s*%(.*%)%s*([%w_]+)",
    -- Rust
    "^%s*fn%s+([%w_]+)",
    "^%s*pub%s+fn%s+([%w_]+)",
    -- Lua
    "^%s*function%s+([%w_.]+)",
    "^%s*local%s+function%s+([%w_]+)",
  }
  
  for i, line in ipairs(lines) do
    for _, pattern in ipairs(patterns) do
      local func_name = line:match(pattern)
      if func_name then
        local line_num = start_line + i - 1
        -- Try to find a better character position by locating the function name
        local char_pos = line:find(func_name, 1, true) or 0
        table.insert(functions, {
          line = line_num,
          character = char_pos - 1, -- Convert to 0-indexed
          name = func_name
        })
        break
      end
    end
  end
  
  return functions
end

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

function M.clear_function_cache(bufnr)
  if bufnr then
    -- Clear cache for specific buffer
    function_cache[bufnr] = nil
    buffer_changedtick[bufnr] = nil
    -- Remove from access order
    for i, cached_bufnr in ipairs(cache_access_order) do
      if cached_bufnr == bufnr then
        table.remove(cache_access_order, i)
        break
      end
    end
  else
    -- Clear entire cache
    function_cache = {}
    buffer_changedtick = {}
    cache_access_order = {}
  end
end

-- Clean up cache for invalid buffers to prevent memory leaks
function M.cleanup_function_cache()
  local valid_access_order = {}
  for bufnr, _ in pairs(function_cache) do
    if not vim.api.nvim_buf_is_valid(bufnr) then
      function_cache[bufnr] = nil
      buffer_changedtick[bufnr] = nil
    else
      -- Keep valid buffers in access order
      for _, cached_bufnr in ipairs(cache_access_order) do
        if cached_bufnr == bufnr then
          table.insert(valid_access_order, bufnr)
          break
        end
      end
    end
  end
  cache_access_order = valid_access_order
  
  -- Apply LRU eviction after cleanup
  evict_lru_if_needed()
end

return M