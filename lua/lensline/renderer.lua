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
  
  -- Skip re-render if content hasn't changed
  local existing = vim.api.nvim_buf_get_extmarks(bufnr, M.namespace, {line - 1, 0}, {line - 1, 0}, { details = true })[1]
  if existing and existing[4] and existing[4].virt_lines and vim.deep_equal(existing[4].virt_lines, {virt_text}) then
    return
  end
  
  local extmark_opts = {
    virt_lines = { virt_text },
    virt_lines_above = true,
  }
  
  -- If there's an existing extmark, use its ID to replace it
  if existing then
    extmark_opts.id = existing[1]
  end
  
  vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line - 1, 0, extmark_opts)
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

local function create_extmark_opts(placement, texts, separator, highlight, prefix, line_content)
  local combined_text = table.concat(texts, separator)
  
  if placement == "inline" then
    -- Inline: virtual text at end of line, no prefix
    return {
      virt_text = { { " " .. combined_text, highlight } },
      virt_text_pos = "eol"
    }
  else
    -- Above: virtual lines above function, with prefix and indentation
    local leading_whitespace = line_content:match("^%s*") or ""
    local virt_text = {}
    
    if leading_whitespace ~= "" then
      table.insert(virt_text, { leading_whitespace, highlight })
    end
    
    if prefix and prefix ~= "" then
      table.insert(virt_text, { prefix, highlight })
    end
    
    table.insert(virt_text, { combined_text, highlight })
    
    return {
      virt_lines = { virt_text },
      virt_lines_above = true
    }
  end
end

function M.render_combined_lenses(bufnr)
  if not utils.is_valid_buffer(bufnr) then
    return
  end
  
  -- Ensure initialization
  M.ensure_provider_data_initialized()
  
  if not M.provider_lens_data[bufnr] then
    return
  end
  
  local opts = config.get()
  local highlight = opts.style.highlight or "Comment"
  local prefix = opts.style.prefix or ""
  local separator = opts.style.separator or " • "
  
  -- Get existing extmarks for comparison
  local existing_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, M.namespace, 0, -1, { details = true })
  local existing_by_line = {}
  for _, mark in ipairs(existing_extmarks) do
    local line = mark[2]
    existing_by_line[line] = mark
  end
  
  -- Combine lens data from all providers
  local combined_lines = {}
  local lines_to_render = {}
  local data_to_iterate = M.provider_lens_data[bufnr] or {}
  
  -- Get provider order from config to preserve display sequence
  local provider_order = {}
  for _, provider_config in ipairs(opts.providers) do
    if provider_config.enabled ~= false and data_to_iterate[provider_config.name] then
      table.insert(provider_order, provider_config.name)
    end
  end
  
  -- Process providers in config order
  for _, provider_name in ipairs(provider_order) do
    local lens_items = data_to_iterate[provider_name]
    if lens_items and type(lens_items) == "table" then
      -- Robust iteration: handle sparse arrays (nil gaps) while preserving numeric order
      local numeric_indices = {}
      for k, _ in pairs(lens_items) do
        if type(k) == "number" then
          table.insert(numeric_indices, k)
        end
      end
      table.sort(numeric_indices)
      for _, idx in ipairs(numeric_indices) do
        local item = lens_items[idx]
        if item and item.line and item.text then
          if not combined_lines[item.line] then
            combined_lines[item.line] = {}
          end
          table.insert(combined_lines[item.line], item.text)
        end
      end
    end
  end
  
  local placement = opts.style.placement or "above"
  local lines_to_render = {}
  local extmark_operations = {}
  
  -- Only update lines with changed content
  for line, texts in pairs(combined_lines) do
    lines_to_render[line - 1] = true
    
    local line_content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
    local extmark_opts = create_extmark_opts(placement, texts, separator, highlight, prefix, line_content)
    
    -- Check if content has changed
    local existing = existing_by_line[line - 1]
    local content_key = placement == "inline" and "virt_text" or "virt_lines"
    local expected_content = placement == "inline" and extmark_opts.virt_text or extmark_opts.virt_lines
    
    if not (existing and existing[4] and existing[4][content_key] and vim.deep_equal(existing[4][content_key], expected_content)) then
      if existing then
        extmark_opts.id = existing[1]
      end
      
      local col = placement == "inline" and #line_content or 0
      table.insert(extmark_operations, {
        line = line - 1,
        col = col,
        opts = extmark_opts
      })
    end
  end
  
  -- Apply all extmark updates
  for _, op in ipairs(extmark_operations) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, M.namespace, op.line, op.col, op.opts)
  end
  
  -- Clean up extmarks for lines that no longer have lens data
  local extmarks_to_delete = {}
  for line, mark in pairs(existing_by_line) do
    if not lines_to_render[line] then
      table.insert(extmarks_to_delete, mark[1])
    end
  end
  
  -- Remove obsolete extmarks
  for _, extmark_id in ipairs(extmarks_to_delete) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.namespace, extmark_id)
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
  
  -- Prepare extmark operations
  local extmark_operations = {}
  
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
    
    -- Skip if content hasn't changed
    local existing = vim.api.nvim_buf_get_extmarks(bufnr, M.namespace, {line - 1, 0}, {line - 1, 0}, { details = true })[1]
    if not (existing and existing[4] and existing[4].virt_lines and vim.deep_equal(existing[4].virt_lines, {virt_text})) then
      local extmark_opts = {
        virt_lines = { virt_text },
        virt_lines_above = true,
      }
      
      if existing then
        extmark_opts.id = existing[1]
      end
      
      table.insert(extmark_operations, {
        line = line - 1,
        opts = extmark_opts
      })
    end
  end
  
  -- Apply all extmark updates
  for _, op in ipairs(extmark_operations) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, M.namespace, op.line, 0, op.opts)
  end
end

return M