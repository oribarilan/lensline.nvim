-- Usages Provider
-- Shows usage count aggregating references, definitions, and implementations
return {
  name = "usages",
  event = { "LspAttach", "BufWritePost" },
  handler = function(bufnr, func_info, provider_config, callback)
    local utils = require("lensline.utils")
    
    -- Get configuration values (all from config.lua, ZERO hardcoded config)
    local include = provider_config.include
    local breakdown = provider_config.breakdown
    local show_zero = provider_config.show_zero
    local labels = provider_config.labels
    local icon_for_single = provider_config.icon_for_single
    local inner_separator = provider_config.inner_separator
    
    -- Track async operations and results
    local pending_requests = {}
    local results = {}
    local capabilities = {}  -- track which capabilities are actually supported
    local completed_requests = 0
    
    -- Helper function to check if all requests are complete and render
    local function check_completion()
      if completed_requests == #pending_requests then
        -- Calculate counts based on included attributes that are actually supported
        local total_count = 0
        local individual_counts = {}
        local supported_attrs = {}
        
        for _, attr in ipairs(include) do
          if capabilities[attr] then  -- Only include supported capabilities
            local count = results[attr] or 0
            total_count = total_count + count
            individual_counts[attr] = count
            table.insert(supported_attrs, attr)
          end
        end
        
        -- If no supported capabilities or no data available, don't show anything
        if #supported_attrs == 0 or (total_count == 0 and not show_zero) then
          callback(nil)
          return
        end
        
        -- Generate display text based on breakdown mode
        local text
        
        if breakdown then
          -- Show breakdown for each supported attribute: "5 refs, 1 defs, 2 impls"
          local breakdown_parts = {}
          for _, attr in ipairs(supported_attrs) do
            local count = individual_counts[attr]
            if count > 0 or show_zero then  -- Show zeros only if show_zero is true
              local label = labels[attr] or attr
              table.insert(breakdown_parts, count .. " " .. label)
            end
          end
          
          -- If no parts to show (all zeros and show_zero is false), don't show anything
          if #breakdown_parts == 0 then
            callback(nil)
            return
          end
          
          text = table.concat(breakdown_parts, inner_separator)
        else
          -- Aggregate mode: show single count
          if #supported_attrs == 1 then
            -- Single supported attribute: use nerdfont pattern like references provider
            local icon = utils.if_nerdfont_else("󰌹 ", "")
            local attr = supported_attrs[1]
            local label = labels[attr] or attr
            local suffix = utils.if_nerdfont_else("", " " .. label)
            text = icon .. total_count .. suffix
          else
            -- Multiple supported attributes aggregated: use nerdfont pattern with "usages" label
            local icon = utils.if_nerdfont_else("󰌹 ", "")
            local usages_label = labels.usages or "usages"
            local suffix = utils.if_nerdfont_else("", " " .. usages_label)
            text = icon .. total_count .. suffix
          end
        end
        
        callback({
          line = func_info.line,
          text = text
        })
      end
    end
    
    -- Make LSP requests for each included attribute, but only if capability is supported
    for _, attr in ipairs(include) do
      if attr == "refs" and utils.has_lsp_references_capability(bufnr) then
        table.insert(pending_requests, "refs")
        capabilities.refs = true
        utils.get_lsp_references(bufnr, func_info, function(references)
          results.refs = references and #references or 0
          completed_requests = completed_requests + 1
          check_completion()
        end)
      elseif attr == "defs" and utils.has_lsp_definitions_capability(bufnr) then
        table.insert(pending_requests, "defs")
        capabilities.defs = true
        utils.get_lsp_definitions(bufnr, func_info, function(definitions)
          results.defs = definitions and #definitions or 0
          completed_requests = completed_requests + 1
          check_completion()
        end)
      elseif attr == "impls" and utils.has_lsp_implementations_capability(bufnr) then
        table.insert(pending_requests, "impls")
        capabilities.impls = true
        utils.get_lsp_implementations(bufnr, func_info, function(implementations)
          results.impls = implementations and #implementations or 0
          completed_requests = completed_requests + 1
          check_completion()
        end)
      end
    end
    
    -- If no supported capabilities, return nothing
    if #pending_requests == 0 then
      callback(nil)
    end
  end
}