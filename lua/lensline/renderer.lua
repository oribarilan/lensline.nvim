local config = require("lensline.config")
local utils = require("lensline.utils")

local M = {}

M.namespace = vim.api.nvim_create_namespace("lensline")

-- Per-provider namespaces for independent rendering
M.provider_namespaces = {}

function M.get_provider_namespace(provider_name)
  if not M.provider_namespaces[provider_name] then
    M.provider_namespaces[provider_name] = vim.api.nvim_create_namespace("lensline_" .. provider_name)
  end
  return M.provider_namespaces[provider_name]
end

function M.clear_buffer(bufnr)
  if not utils.is_valid_buffer(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
  
  -- Clear all provider-specific namespaces
  for _, ns in pairs(M.provider_namespaces) do
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
  
  -- DON'T clear lens data - we need it for rendering
end

function M.clear_provider(bufnr, provider_name)
  if not utils.is_valid_buffer(bufnr) then
    return
  end
  local ns = M.get_provider_namespace(provider_name)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

function M.render_lens_item(bufnr, line, text)
  if not utils.is_valid_buffer(bufnr) or not text or text == "" then
    return
  end
  
  local opts = config.get()
  local highlight = opts.style.highlight or "Comment"
  local prefix = opts.style.prefix or ""
  
  local virt_text = {}
  
  -- Calculate indentation based on the actual line content
  local line_content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  local leading_whitespace = line_content:match("^%s*") or ""
  
  -- Add indentation
  if leading_whitespace ~= "" then
    table.insert(virt_text, { leading_whitespace, highlight })
  end
  
  -- Add prefix if configured
  if prefix and prefix ~= "" then
    table.insert(virt_text, { prefix, highlight })
  end
  
  -- Add the lens text
  table.insert(virt_text, { text, highlight })
  
  vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line - 1, 0, {
    virt_lines = { virt_text },
    virt_lines_above = true,
  })
end

-- Store lens data from different providers
M.provider_lens_data = {}

-- Initialize provider_lens_data if not exists
function M.ensure_provider_data_initialized()
  if not M.provider_lens_data then
    M.provider_lens_data = {}
  end
end

function M.render_provider_lenses(bufnr, provider_name, lens_items)
  local debug = require("lensline.debug")
  
  debug.log_context("Renderer", "render_provider_lenses called for " .. provider_name .. " with " .. (lens_items and #lens_items or 0) .. " items")
  
  if not utils.is_valid_buffer(bufnr) then
    debug.log_context("Renderer", "buffer " .. bufnr .. " is not valid")
    return
  end
  
  -- Ensure initialization
  M.ensure_provider_data_initialized()
  
  debug.log_context("Renderer", "before storing - M.provider_lens_data exists: " .. tostring(M.provider_lens_data ~= nil))
  
  -- Store lens data for this provider
  if not M.provider_lens_data[bufnr] then
    M.provider_lens_data[bufnr] = {}
    debug.log_context("Renderer", "created new buffer entry for " .. bufnr)
  end
  M.provider_lens_data[bufnr][provider_name] = lens_items or {}
  
  debug.log_context("Renderer", "stored " .. #(lens_items or {}) .. " lens items for provider " .. provider_name)
  debug.log_context("Renderer", "after storing - buffer " .. bufnr .. " data: " .. vim.inspect(M.provider_lens_data[bufnr]))
  
  -- Render combined results from all providers
  M.render_combined_lenses(bufnr)
end

function M.render_combined_lenses(bufnr)
  local debug = require("lensline.debug")
  
  debug.log_context("Renderer", "render_combined_lenses called for buffer " .. bufnr)
  
  if not utils.is_valid_buffer(bufnr) then
    debug.log_context("Renderer", "buffer " .. bufnr .. " is not valid")
    return
  end
  
  -- Ensure initialization
  M.ensure_provider_data_initialized()
  
  debug.log_context("Renderer", "M.provider_lens_data exists: " .. tostring(M.provider_lens_data ~= nil))
  debug.log_context("Renderer", "M.provider_lens_data keys: " .. vim.inspect(M.provider_lens_data and vim.tbl_keys(M.provider_lens_data) or {}))
  debug.log_context("Renderer", "looking for buffer " .. bufnr .. " in lens data")
  
  if not M.provider_lens_data[bufnr] then
    debug.log_context("Renderer", "no lens data for buffer " .. bufnr)
    return
  end
  
  debug.log_context("Renderer", "provider lens data: " .. vim.inspect(M.provider_lens_data[bufnr]))
  
  -- Clear all previous renderings (only extmarks, not lens data)
  debug.log_context("Renderer", "clearing old extmarks")
  M.clear_buffer(bufnr)
  
  local opts = config.get()
  local highlight = opts.style.highlight or "Comment"
  local prefix = opts.style.prefix or ""
  local separator = opts.style.separator or " • "
  
  -- Combine all lens items from all providers by line
  local combined_lines = {}
  debug.log_context("Renderer", "M.provider_lens_data[bufnr] is nil: " .. tostring(M.provider_lens_data[bufnr] == nil))
  debug.log_context("Renderer", "raw M.provider_lens_data[bufnr]: " .. vim.inspect(M.provider_lens_data[bufnr]))
  local data_to_iterate = M.provider_lens_data[bufnr] or {}
  debug.log_context("Renderer", "about to iterate over: " .. vim.inspect(data_to_iterate))
  debug.log_context("Renderer", "pairs() will iterate over " .. vim.tbl_count(data_to_iterate) .. " providers")
  
  for provider_name, lens_items in pairs(data_to_iterate) do
    debug.log_context("Renderer", "processing provider " .. provider_name .. " with " .. (lens_items and #lens_items or 0) .. " items")
    if lens_items and type(lens_items) == "table" then
      for i, item in ipairs(lens_items) do
        debug.log_context("Renderer", "checking item " .. i .. ": " .. vim.inspect(item))
        if item and item.line and item.text then
          debug.log_context("Renderer", "adding item for line " .. item.line .. ": " .. item.text)
          if not combined_lines[item.line] then
            combined_lines[item.line] = {}
          end
          table.insert(combined_lines[item.line], item.text)
        else
          debug.log_context("Renderer", "item " .. i .. " failed validation - item: " .. tostring(item ~= nil) .. " line: " .. tostring(item and item.line) .. " text: " .. tostring(item and item.text))
        end
      end
    else
      debug.log_context("Renderer", "lens_items failed validation - exists: " .. tostring(lens_items ~= nil) .. " type: " .. type(lens_items or {}))
    end
  end
  
  debug.log_context("Renderer", "combined lines: " .. vim.inspect(combined_lines))
  
  -- Render each line with combined data
  debug.log_context("Renderer", "rendering " .. vim.tbl_count(combined_lines) .. " lines")
  for line, texts in pairs(combined_lines) do
    debug.log_context("Renderer", "rendering line " .. line .. " with texts: " .. vim.inspect(texts))
    
    local line_content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
    local leading_whitespace = line_content:match("^%s*") or ""
    
    local virt_text = {}
    
    -- Add indentation
    if leading_whitespace ~= "" then
      table.insert(virt_text, { leading_whitespace, highlight })
    end
    
    -- Add prefix if configured
    if prefix and prefix ~= "" then
      table.insert(virt_text, { prefix, highlight })
    end
    
    -- Join all texts from all providers with separator
    local combined_text = table.concat(texts, separator)
    table.insert(virt_text, { combined_text, highlight })
    
    debug.log_context("Renderer", "setting extmark for line " .. line .. " with virt_text: " .. vim.inspect(virt_text))
    
    local ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.namespace, line - 1, 0, {
      virt_lines = { virt_text },
      virt_lines_above = true,
    })
    
    if not ok then
      debug.log_context("Renderer", "failed to set extmark: " .. tostring(err), "ERROR")
    else
      debug.log_context("Renderer", "successfully set extmark for line " .. line)
    end
  end
end

function M.render_buffer_lenses(bufnr, lens_data)
  if not utils.is_valid_buffer(bufnr) then
    return
  end
  
  M.clear_buffer(bufnr)
  
  local opts = config.get()
  local highlight = opts.style.highlight or "Comment"
  local prefix = opts.style.prefix or ""
  local separator = opts.style.separator or " • "
  
  -- Group lens items by line
  local lines_data = {}
  for _, item in ipairs(lens_data) do
    if not lines_data[item.line] then
      lines_data[item.line] = {}
    end
    table.insert(lines_data[item.line], item.text)
  end
  
  -- Render each line
  for line, texts in pairs(lines_data) do
    local line_content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
    local leading_whitespace = line_content:match("^%s*") or ""
    
    local virt_text = {}
    
    -- Add indentation
    if leading_whitespace ~= "" then
      table.insert(virt_text, { leading_whitespace, highlight })
    end
    
    -- Add prefix if configured
    if prefix and prefix ~= "" then
      table.insert(virt_text, { prefix, highlight })
    end
    
    -- Join multiple texts with separator
    local combined_text = table.concat(texts, separator)
    table.insert(virt_text, { combined_text, highlight })
    
    vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line - 1, 0, {
      virt_lines = { virt_text },
      virt_lines_above = true,
    })
  end
end

return M