local M = {}

local function resolve_highlight(item_highlight, provider_highlight)
  if item_highlight and item_highlight ~= "" then
    return item_highlight
  end
  if provider_highlight and provider_highlight ~= "" then
    return provider_highlight
  end
  return nil
end

function M.combine_provider_data(provider_lens_data, provider_configs)
  local combined = {}
  if not provider_lens_data then
    return combined
  end

  for _, provider_config in ipairs(provider_configs) do
    if provider_config.enabled ~= false then
      local lens_items = provider_lens_data[provider_config.name]
      if lens_items and type(lens_items) == "table" then
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
            table.insert(combined[item.line], {
              text = item.text,
              highlight = resolve_highlight(item.highlight, provider_config.highlight)
            })
          end
        end
      end
    end
  end

  return combined
end

local function build_content_chunks(texts, separator, global_hl)
  local chunks = {}
  for i, entry in ipairs(texts) do
    if i > 1 then
      table.insert(chunks, { separator, global_hl })
    end
    local text, hl
    if type(entry) == "table" then
      text = entry.text or ""
      hl = entry.highlight or global_hl
    else
      text = entry
      hl = global_hl
    end
    table.insert(chunks, { text, hl })
  end
  return chunks
end

function M.compute_extmark_opts(args)
  local placement = args.placement or "above"
  local global_hl = args.highlight or "Comment"
  local prefix = args.prefix or ""
  local separator = args.separator or " • "
  local texts = args.texts or {}

  local chunks = build_content_chunks(texts, separator, global_hl)

  if placement == "inline" then
    local virt_text = {}
    local leader = " "
    if prefix ~= "" then
      leader = leader .. prefix
    end
    table.insert(virt_text, { leader, global_hl })
    for _, chunk in ipairs(chunks) do
      table.insert(virt_text, chunk)
    end

    return {
      virt_text = virt_text,
      virt_text_pos = "eol",
      hl_mode = "combine",
      ephemeral = args.ephemeral or false
    }
  else
    local leading_whitespace = (args.line_content or ""):match("^%s*") or ""
    local virt_text = {}

    if leading_whitespace ~= "" then
      table.insert(virt_text, { leading_whitespace, global_hl })
    end

    if prefix ~= "" then
      table.insert(virt_text, { prefix, global_hl })
    end

    for _, chunk in ipairs(chunks) do
      table.insert(virt_text, chunk)
    end

    if #virt_text == 0 then
      table.insert(virt_text, { "", global_hl })
    end

    return {
      virt_lines = { virt_text },
      virt_lines_above = true,
      ephemeral = args.ephemeral or false
    }
  end
end

return M
