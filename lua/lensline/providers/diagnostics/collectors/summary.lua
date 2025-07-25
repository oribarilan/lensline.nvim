-- diagnostics function level collector
-- this was extracted from the old diagnostics.lua provider

-- helper function to get diagnostic icons based on config
local function get_diagnostic_icons()
    local config = require("lensline.config")
    local opts = config.get()
    
    return {
        [vim.diagnostic.severity.ERROR] = opts.use_nerdfonts and "" or "E",
        [vim.diagnostic.severity.WARN] = opts.use_nerdfonts and "" or "W",
        [vim.diagnostic.severity.INFO] = opts.use_nerdfonts and "" or "I",
        [vim.diagnostic.severity.HINT] = opts.use_nerdfonts and "" or "H",
    }
end

-- helper function to format diagnostic counts into a string (from old provider)
local function format_diagnostic_counts(counts)
    local parts = {}
    local icons = get_diagnostic_icons()
    
    -- add each severity type if count > 0, in order of severity
    local severities = {
        vim.diagnostic.severity.ERROR,
        vim.diagnostic.severity.WARN,
        vim.diagnostic.severity.INFO,
        vim.diagnostic.severity.HINT,
    }
    
    for _, severity in ipairs(severities) do
        local count = counts[severity]
        if count and count > 0 then
            table.insert(parts, count .. icons[severity])
        end
    end
    
    if #parts == 0 then
        return nil
    end
    
    return table.concat(parts, "  ")  -- double space between different severities
end

-- helper to check if diagnostic is within function range
local function is_in_function_range(diagnostic, func_range)
    if not func_range then
        return false
    end
    
    local diag_line = diagnostic.lnum
    local diag_col = diagnostic.col or 0
    
    local start_line = func_range.start.line
    local end_line = func_range["end"].line
    local start_char = func_range.start.character
    local end_char = func_range["end"].character
    
    if diag_line > start_line and diag_line < end_line then
        return true
    elseif diag_line == start_line and diag_col >= start_char then
        return true
    elseif diag_line == end_line and diag_col <= end_char then
        return true
    end
    
    return false
end

return function(diagnostics_context, function_info)
    local counts = {
        [vim.diagnostic.severity.ERROR] = 0,
        [vim.diagnostic.severity.WARN] = 0,
        [vim.diagnostic.severity.INFO] = 0,
        [vim.diagnostic.severity.HINT] = 0,
    }
    
    local total_count = 0
    
    for _, diagnostic in ipairs(diagnostics_context.diagnostics) do
        if is_in_function_range(diagnostic, function_info.range) then
            if counts[diagnostic.severity] then
                counts[diagnostic.severity] = counts[diagnostic.severity] + 1
                total_count = total_count + 1
            end
        end
    end
    
    if total_count == 0 then
        return nil, nil
    end
    
    local text = format_diagnostic_counts(counts)
    if text then
        return "%s", text
    end
    
    return nil, nil
end