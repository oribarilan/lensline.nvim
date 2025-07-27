local utils = require("lensline.utils")

-- Reference Count Provider
-- Shows reference count for functions/methods using LSP
return {
  name = "ref_count",
  event = { "LspAttach", "BufWritePost" },
  debounce = 1000,
  handler = function(bufnr, start_line, end_line, callback)
    local debug = require("lensline.debug")
    
    debug.log_context("LSP", "handler called for buffer " .. bufnr .. " range " .. start_line .. "-" .. end_line)
    
    -- Get LSP clients for this buffer
    local clients = utils.get_lsp_clients(bufnr)
    debug.log_context("LSP", "found " .. (clients and #clients or 0) .. " LSP clients")
    if not clients or #clients == 0 then
      debug.log_context("LSP", "no LSP clients available")
      if callback then callback({}) end
      return {}
    end

    -- Find function definitions in the visible range using improved detection
    local functions = utils.find_functions_in_range(bufnr, start_line, end_line)
    debug.log_context("LSP", "found " .. (functions and #functions or 0) .. " functions")
    if not functions or #functions == 0 then
      debug.log_context("LSP", "no functions found in range")
      if callback then callback({}) end
      return {}
    end

    local lens_items = {}
    local pending_requests = #functions
    
    -- If no callback provided, fall back to synchronous mode (but still avoid fallbacks)
    if not callback then
      for _, func in ipairs(functions) do
        debug.log_context("LSP", "processing function '" .. (func.name or "unknown") .. "' at line " .. func.line)
        
        local ref_count = 0
        local char_pos = func.character or 0
        
        -- If we have a function name, try to find its exact position in the line
        if func.name then
          local line_content = vim.api.nvim_buf_get_lines(bufnr, func.line - 1, func.line, false)[1] or ""
          local name_start = line_content:find(func.name, 1, true)
          if name_start then
            char_pos = name_start - 1  -- Convert to 0-indexed
            debug.log_context("LSP", "found function name '" .. func.name .. "' at character " .. char_pos)
          end
        end
        
        -- Create LSP reference request
        local params = {
          textDocument = vim.lsp.util.make_text_document_params(bufnr),
          position = { line = func.line - 1, character = char_pos },
          context = { includeDeclaration = false }
        }
        
        debug.log_context("LSP", "requesting references at position " .. (func.line - 1) .. ":" .. char_pos)
        
        -- Single synchronous request only (no fallbacks to avoid blocking)
        local results = vim.lsp.buf_request_sync(bufnr, "textDocument/references", params, 1000)
        
        if results then
          for _, result in pairs(results) do
            if result.result and type(result.result) == "table" then
              ref_count = ref_count + #result.result
              debug.log_context("LSP", "found " .. #result.result .. " references")
            end
          end
        end
        
        debug.log_context("LSP", "total references for function '" .. (func.name or "unknown") .. "' at line " .. func.line .. ": " .. ref_count)
        
        -- Create lens item
        table.insert(lens_items, {
          line = func.line,
          text = "󰌹 " .. ref_count
        })
      end
      
      return lens_items
    end
    
    -- Async mode with callback and timeout handling
    local completed = false
    
    -- Timeout safety net
    vim.defer_fn(function()
      if not completed then
        completed = true
        debug.log_context("LSP", "async requests timed out after 3 seconds, calling callback with " .. #lens_items .. " items")
        callback(lens_items)
      end
    end, 3000)
    
    for _, func in ipairs(functions) do
      debug.log_context("LSP", "processing function '" .. (func.name or "unknown") .. "' at line " .. func.line)
      
      local char_pos = func.character or 0
      
      -- If we have a function name, try to find its exact position in the line
      if func.name then
        local line_content = vim.api.nvim_buf_get_lines(bufnr, func.line - 1, func.line, false)[1] or ""
        local name_start = line_content:find(func.name, 1, true)
        if name_start then
          char_pos = name_start - 1  -- Convert to 0-indexed
          debug.log_context("LSP", "found function name '" .. func.name .. "' at character " .. char_pos)
        end
      end
      
      -- Create LSP reference request
      local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = { line = func.line - 1, character = char_pos },
        context = { includeDeclaration = false }
      }
      
      debug.log_context("LSP", "requesting references async at position " .. (func.line - 1) .. ":" .. char_pos)
      
      -- Make async LSP request with timeout
      vim.lsp.buf_request(bufnr, "textDocument/references", params, function(err, result, ctx)
        if completed then
          return -- Already timed out
        end
        
        local ref_count = 0
        
        if result and type(result) == "table" then
          ref_count = #result
          debug.log_context("LSP", "async found " .. ref_count .. " references for " .. (func.name or "unknown"))
        elseif err then
          debug.log_context("LSP", "async request error: " .. vim.inspect(err))
        end
        
        -- Create lens item
        table.insert(lens_items, {
          line = func.line,
          text = "󰌹 " .. ref_count
        })
        
        pending_requests = pending_requests - 1
        if pending_requests == 0 and not completed then
          completed = true
          debug.log_context("LSP", "all async requests completed, calling callback with " .. #lens_items .. " items")
          callback(lens_items)
        end
      end)
    end
    
    -- Return empty initially for async mode
    return {}
  end
}