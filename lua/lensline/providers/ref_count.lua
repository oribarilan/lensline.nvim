local utils = require("lensline.utils")

-- Reference Count Provider
-- Shows reference count for functions/methods using LSP
return {
  name = "ref_count",
  event = { "LspAttach", "BufWritePost" },
  handler = function(bufnr, func_info, callback)
    -- Early exit guard: check if this provider is disabled
    local config = require("lensline.config")
    local opts = config.get()
    local provider_config = nil
    
    -- Find this provider's config
    for _, provider in ipairs(opts.providers) do
      if provider.name == "ref_count" then
        provider_config = provider
        break
      end
    end
    
    -- Exit early if provider is disabled
    if provider_config and provider_config.enabled == false then
      if callback then
        callback(nil)
      end
      return nil
    end
    
    local debug = require("lensline.debug")
    debug.log_context("LSP", "handler called for function '" .. (func_info.name or "unknown") .. "' at line " .. func_info.line)
    
    -- Get LSP clients for this buffer
    local clients = utils.get_lsp_clients(bufnr)
    debug.log_context("LSP", "found " .. (clients and #clients or 0) .. " LSP clients")
    if not clients or #clients == 0 then
      debug.log_context("LSP", "no LSP clients available")
      if callback then callback(nil) end
      return nil
    end

    -- Check if any LSP client supports references
    if not utils.has_lsp_capability(bufnr, "textDocument/references") then
      debug.log_context("LSP", "no LSP client supports textDocument/references")
      if callback then callback(nil) end
      return nil
    end

    local char_pos = func_info.character or 0
    
    -- If we have a function name, try to find its exact position in the line
    if func_info.name then
      local line_content = vim.api.nvim_buf_get_lines(bufnr, func_info.line - 1, func_info.line, false)[1] or ""
      local name_start = line_content:find(func_info.name, 1, true)
      if name_start then
        char_pos = name_start - 1  -- Convert to 0-indexed
        debug.log_context("LSP", "found function name '" .. func_info.name .. "' at character " .. char_pos)
      end
    end
    
    -- Create LSP reference request
    local params = {
      textDocument = vim.lsp.util.make_text_document_params(bufnr),
      position = { line = func_info.line - 1, character = char_pos },
      context = { includeDeclaration = false }
    }
    
    debug.log_context("LSP", "requesting references at position " .. (func_info.line - 1) .. ":" .. char_pos)
    
    -- If no callback provided, run synchronously
    if not callback then
      debug.log_context("LSP", "running in synchronous mode")
      local ref_count = 0
      
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
      
      debug.log_context("LSP", "total references for function '" .. (func_info.name or "unknown") .. "' at line " .. func_info.line .. ": " .. ref_count)
      
      -- Create lens item
      local opts = config.get()
      local icon = opts.style.use_nerdfont and "󰌹 " or ""
      local result = {
        line = func_info.line,
        text = icon .. ref_count .. (opts.style.use_nerdfont and "" or " refs")
      }
      
      -- Handle both sync and async modes
      if callback then
        callback(result)
        return nil
      else
        return result
      end
    end
    
    -- Run asynchronously
    debug.log_context("LSP", "running in async mode for function '" .. (func_info.name or "unknown") .. "' at line " .. func_info.line)
    
    -- Make async LSP request with timeout
    vim.lsp.buf_request(bufnr, "textDocument/references", params, function(err, result, ctx)
      local ref_count = 0
      
      if result and type(result) == "table" then
        ref_count = #result
        debug.log_context("LSP", "async found " .. ref_count .. " references for " .. (func_info.name or "unknown"))
      elseif err then
        debug.log_context("LSP", "async request error: " .. vim.inspect(err))
      end
      
      -- Create and return lens item via callback
      local opts = config.get()
      local icon = opts.style.use_nerdfont and "󰌹 " or ""
      local result = {
        line = func_info.line,
        text = icon .. ref_count .. (opts.style.use_nerdfont and "" or " refs")
      }
      callback(result)
    end)
  end
}