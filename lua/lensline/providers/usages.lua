-- Usages Provider
-- Shows usage count aggregating references, definitions, and implementations
return {
  name = "usages",
  event = { "LspAttach", "BufWritePost" },
  handler = function(bufnr, func_info, provider_config, callback)
    local utils = require("lensline.utils")
    
    -- Use FIXED values for testing (will be replaced with LSP calls later)
    local fixed_counts = {
      refs = 5,
      defs = 1,
      impls = 2,
    }
    
    -- Get configuration values (all from config.lua, ZERO hardcoded config)
    local include = provider_config.include
    local breakdown = provider_config.breakdown
    local labels = provider_config.labels
    local icon_for_single = provider_config.icon_for_single
    local inner_separator = provider_config.inner_separator
    
    -- Calculate counts based on included attributes
    local total_count = 0
    local individual_counts = {}
    
    for _, attr in ipairs(include) do
      local count = fixed_counts[attr] or 0
      total_count = total_count + count
      individual_counts[attr] = count
    end
    
    -- Generate display text based on breakdown mode
    local text
    
    if breakdown then
      -- Show breakdown for each included attribute: "5 refs, 1 defs, 2 impls"
      local breakdown_parts = {}
      for _, attr in ipairs(include) do
        local count = individual_counts[attr]
        if count > 0 then  -- Only show attributes with non-zero counts
          local label = labels[attr] or attr
          table.insert(breakdown_parts, count .. " " .. label)
        end
      end
      text = table.concat(breakdown_parts, inner_separator)
    else
      -- Aggregate mode: show single count
      if #include == 1 then
        -- Single attribute: use nerdfont pattern like references provider
        local icon = utils.if_nerdfont_else("󰌹 ", "")
        local attr = include[1]
        local label = labels[attr] or attr
        local suffix = utils.if_nerdfont_else("", " " .. label)
        text = icon .. total_count .. suffix
      else
        -- Multiple attributes aggregated: use nerdfont pattern with "usages" label
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
}