local config = require("lensline.config")
local utils = require("lensline.utils")

local M = {}

M.namespace = vim.api.nvim_create_namespace("lensline")

function M.clear_buffer(bufnr)
    if not utils.is_valid_buffer(bufnr) then
        return
    end
    vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
end

function M.render_lens(bufnr, line, text_parts, character)
    if not utils.is_valid_buffer(bufnr) or not text_parts or #text_parts == 0 then
        return
    end
    
    local opts = config.get()
    local separator = opts.style.separator
    local highlight = opts.style.highlight
    local prefix = opts.style.prefix
    
    local virt_text = {}
    
    -- calculate indentation based on character position
    local indent = ""
    if character and character > 0 then
        -- get the actual line content to determine whitespace style
        local line_content = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
        -- extract the leading whitespace
        local leading_whitespace = line_content:match("^%s*") or ""
        indent = leading_whitespace
    end
    
    -- add indentation first
    if indent ~= "" then
        table.insert(virt_text, { indent, highlight })
    end
    
    -- add prefix if configured
    if prefix and prefix ~= "" then
        table.insert(virt_text, { prefix, highlight })
    end
    
    -- sort text_parts by order first, then extract text
    local sorted_parts = {}
    for _, part in ipairs(text_parts) do
        if type(part) == "table" and part.text then
            -- new format with order
            table.insert(sorted_parts, part)
        else
            -- legacy format - treat as order 0 for backward compatibility
            table.insert(sorted_parts, { text = part, order = 0 })
        end
    end
    
    table.sort(sorted_parts, function(a, b) return a.order < b.order end)
    
    for i, part in ipairs(sorted_parts) do
        if i > 1 and separator then
            table.insert(virt_text, { separator, highlight })
        end
        table.insert(virt_text, { part.text, highlight })
    end
    
    vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line, 0, {
        virt_lines = { virt_text },
        virt_lines_above = true,
    })
end

function M.render_buffer_lenses(bufnr, lens_data)
    if not utils.is_valid_buffer(bufnr) then
        return
    end
    
    M.clear_buffer(bufnr)
    
    for _, lens in ipairs(lens_data) do
        if lens.line and lens.text_parts then
            M.render_lens(bufnr, lens.line, lens.text_parts, lens.character)
        end
    end
end

return M