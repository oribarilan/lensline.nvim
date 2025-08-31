local M = {}

-- Combine provider data with proper ordering preservation
-- This consolidates the duplicate combination logic from renderer.lua and focused_renderer.lua
function M.combine_provider_data(provider_lens_data, provider_configs)
  local combined = {}
  if not provider_lens_data then 
    return combined 
  end
  
  -- Critical: preserve config order for consistent display sequence
  for _, provider_config in ipairs(provider_configs) do
    if provider_config.enabled ~= false then
      local lens_items = provider_lens_data[provider_config.name]
      if lens_items and type(lens_items) == "table" then
        -- Handle sparse arrays (preserving existing renderer.lua logic)
        -- This robust iteration handles nil gaps while preserving numeric order
        local numeric_indices = {}
        for k, _ in pairs(lens_items) do
          if type(k) == "number" then
            table.insert(numeric_indices, k)
          end
        end
        table.sort(numeric_indices)
        
        for _, idx in ipairs(numeric_indices) do
          local item = lens_items[idx]
          if item and item.line and item.text and item.text ~= "" then
            combined[item.line] = combined[item.line] or {}
            table.insert(combined[item.line], item.text)
          end
        end
      end
    end
  end
  
  return combined -- { [1-based line] = { "txt1", "txt2", ... } }
end

-- Complete extmark options builder that consolidates all duplication
-- Replaces create_extmark_opts() from renderer.lua and make_opts() from focused_renderer.lua
function M.compute_extmark_opts(args)
  -- args: { placement, texts, separator, highlight, prefix, line_content, ephemeral }
  local placement = args.placement or "above"
  local combined_text = table.concat(args.texts or {}, args.separator or " • ")
  local highlight = args.highlight or "Comment"
  local prefix = args.prefix or ""
  
  if placement == "inline" then
    -- Inline: virtual text at end of line, with prefix if configured
    local virt_text = {}
    
    -- Add prefix if configured
    if prefix ~= "" then
      table.insert(virt_text, { prefix, highlight })
    end
    
    table.insert(virt_text, { combined_text, highlight })
    
    -- Combine all parts into a single string with a leading space
    local inline_text = " " .. table.concat(vim.tbl_map(function(t) return t[1] end, virt_text), "")
    
    return {
      virt_text = { { inline_text, highlight } },
      virt_text_pos = "eol",
      ephemeral = args.ephemeral or false
    }
  else
    -- Above: virtual lines above function, with prefix and indentation
    -- Preserve exact indentation logic from current implementations
    local leading_whitespace = (args.line_content or ""):match("^%s*") or ""
    local virt_text = {}
    
    if leading_whitespace ~= "" then
      table.insert(virt_text, { leading_whitespace, highlight })
    end
    
    -- Combine prefix with text as single entry for consistency
    local display_text = prefix .. combined_text
    table.insert(virt_text, { display_text, highlight })
    
    return {
      virt_lines = { virt_text },
      virt_lines_above = true,
      ephemeral = args.ephemeral or false
    }
  end
end

return M