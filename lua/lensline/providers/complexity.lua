-- Code Complexity Provider
-- Estimates code complexity using simplified research-based heuristics
return {
  name = "complexity",
  event = { "BufWritePost", "TextChanged" },
  handler = function(bufnr, func_info, callback)
    -- Early exit guard: check if this provider is disabled
    local config = require("lensline.config")
    local opts = config.get()
    local provider_config = nil
    
    -- Find this provider's config
    for _, provider in ipairs(opts.providers) do
      if provider.name == "complexity" then
        provider_config = provider
        break
      end
    end
    
    -- Exit early if provider is disabled
    if provider_config and provider_config.enabled == false then
      callback(nil)
      return
    end
    
    local debug = require("lensline.debug")
    debug.log_context("Complexity", "analyzing function '" .. (func_info.name or "unknown") .. "' at line " .. func_info.line)
    
    -- Default configuration
    local min_level = (provider_config and provider_config.min_level) or "L"
    
    -- Complexity levels and their numeric values for filtering
    local level_values = {
      ["S"] = 1,
      ["M"] = 2,
      ["L"] = 3,
      ["XL"] = 4
    }
    
    local function format_complexity(label)
      return "Cx: " .. label
    end
    
    local function should_show_complexity(label)
      local current_value = level_values[label] or 0
      local min_value = level_values[min_level] or 3
      return current_value >= min_value
    end
    
    --- Estimate code complexity using simplified research-based heuristics
    ---@param text string
    ---@return string complexity_label, integer score
    local function estimate_complexity(text)
      local lines = vim.split(text, "\n")
      local LOC = #lines
      local max_indent = 0
      local branch_count, conditional_count, loop_count = 0, 0, 0

      for _, line in ipairs(lines) do
        local clean_line = line:gsub("%s*%-%-.*", ""):gsub("%s*#.*", ""):gsub("%s*//.*", "") -- Remove comments
        local indent = line:match("^(%s*)") or ""
        max_indent = math.max(max_indent, #indent)

        -- Control flow statements (the main driver of complexity)
        local branches = select(2, clean_line:gsub("%f[%w_](if|else|elif|elseif|case|switch|when|unless)%f[%W_]", ""))
        branch_count = branch_count + branches
        
        -- Loops add significant complexity
        local loops = select(2, clean_line:gsub("%f[%w_](for|while|do|repeat|each|map|filter|reduce)%f[%W_]", ""))
        loop_count = loop_count + loops

        -- Exception handling adds complexity
        local exceptions = select(2, clean_line:gsub("%f[%w_](try|catch|except|finally|rescue|ensure)%f[%W_]", ""))
        branch_count = branch_count + exceptions

        -- Logical operators (but only in conditional contexts, not assignments)
        if clean_line:match("%f[%w_](if|while|elsif|elseif|elif)%f[%W_]") then
          local conditionals = select(2, clean_line:gsub("%f[%w_](and|or|not|&&|%|%||%?|:)%f[%W_]", ""))
          conditional_count = conditional_count + conditionals
        end
      end

      -- Focus on control flow complexity, not line count
      local score =
          branch_count * 3.0 +        -- if/else/case statements
          loop_count * 4.0 +           -- loops are more complex
          conditional_count * 2.0 +    -- logical operators in conditions
          math.min(LOC, 20) * 0.1 +    -- minimal LOC contribution, capped at 20 lines
          max_indent * 0.5             -- deep nesting adds some complexity

      local label
      if score <= 5 then
        label = "S"
      elseif score <= 12 then
        label = "M"
      elseif score <= 20 then
        label = "L"
      else
        label = "XL"
      end

      return label, math.floor(score)
    end
    
    -- Get function content
    local start_line = func_info.line
    local end_line = func_info.end_line or start_line
    
    -- If we don't have end_line, try to estimate it by finding the function body
    if end_line == start_line then
      local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, -1, false)
      local brace_count = 0
      local found_opening = false
      
      for i, line in ipairs(lines) do
        -- Count braces to find function end
        local open_braces = select(2, line:gsub("[{(]", ""))
        local close_braces = select(2, line:gsub("[})]", ""))
        
        if open_braces > 0 then
          found_opening = true
        end
        
        if found_opening then
          brace_count = brace_count + open_braces - close_braces
          if brace_count <= 0 and i > 1 then
            end_line = start_line + i - 1
            break
          end
        end
        
        -- Safety limit to avoid analyzing huge chunks
        if i > 100 then
          end_line = start_line + i - 1
          break
        end
      end
    end
    
    local function_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    local text = table.concat(function_lines, "\n")
    
    debug.log_context("Complexity", "analyzing " .. #function_lines .. " lines for function '" .. (func_info.name or "unknown") .. "'")
    
    -- Calculate complexity using research-based heuristics
    local complexity_label, score = estimate_complexity(text)
    
    debug.log_context("Complexity", "function '" .. (func_info.name or "unknown") .. "' complexity: " .. complexity_label .. " (score: " .. score .. ")")
    
    -- Check if we should show this complexity level based on configuration
    if not should_show_complexity(complexity_label) then
      debug.log_context("Complexity", "skipping function '" .. (func_info.name or "unknown") .. "' - below min_level: " .. min_level)
      -- Return nil to indicate no lens should be shown
      callback(nil)
      return
    end
    
    local result = {
      line = func_info.line,
      text = format_complexity(complexity_label)
    }
    
    -- Always call callback (async-only)
    callback(result)
  end
}