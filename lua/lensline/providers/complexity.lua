-- Code Complexity Provider
-- Estimates code complexity using language-aware research-based heuristics
return {
  name = "complexity",
  event = { "BufWritePost", "TextChanged" },
  handler = function(bufnr, func_info, provider_config, callback)
    -- Buffer validation like other providers
    local utils = require("lensline.utils")
    if not utils.is_valid_buffer(bufnr) then
      callback(nil)
      return
    end

    local debug = require("lensline.debug")
    
    -- File validation (similar to last_author)
    local filename = vim.api.nvim_buf_get_name(bufnr)
    if filename == "" then
      debug.log_context("Complexity", "skipping unsaved buffer")
      callback(nil)
      return
    end
    
    -- Configuration with defaults
    local min_level = (provider_config and provider_config.min_level) or "L"
    
    -- Get function content using utility (with validation)
    local function_lines = utils.get_function_lines(bufnr, func_info)
    if not function_lines or #function_lines == 0 then
      debug.log_context("Complexity", "no function content found for '" .. (func_info.name or "unknown") .. "'")
      callback(nil)
      return
    end
    
    debug.log_context("Complexity", "analyzing " .. #function_lines .. " lines for function '" .. (func_info.name or "unknown") .. "'")
    
    -- Language detection for better pattern matching
    local filetype = vim.bo[bufnr].filetype or "default"
    
    -- Calculate complexity using enhanced algorithm
    local complexity_label, score = estimate_complexity(function_lines, filetype)
    
    debug.log_context("Complexity", "complexity: " .. complexity_label .. " (score: " .. score .. ")")
    
    -- Check if we should show this complexity level based on configuration
    if not should_show_complexity(complexity_label, min_level) then
      debug.log_context("Complexity", "skipping - below min_level: " .. min_level)
      callback(nil)
      return
    end
    
    local result = {
      line = func_info.line,
      text = format_complexity(complexity_label)
    }
    
    callback(result)
  end
}

-- Helper functions
local function format_complexity(label)
  return "Cx: " .. label
end

local function should_show_complexity(label, min_level)
  local level_values = {
    ["S"] = 1,
    ["M"] = 2,
    ["L"] = 3,
    ["XL"] = 4
  }
  local current_value = level_values[label] or 0
  local min_value = level_values[min_level] or 3
  return current_value >= min_value
end

-- Language-specific patterns for better accuracy
local language_patterns = {
  lua = {
    control_flow = { "if", "elseif", "else", "while", "for", "repeat" },
    loops = { "for", "while", "repeat" },
    exceptions = { "pcall", "xpcall", "error" },
    comments = { "%-%-" },
    weight = 1.0
  },
  javascript = {
    control_flow = { "if", "else", "switch", "case", "try", "catch", "finally" },
    loops = { "for", "while", "do", "forEach", "map", "filter", "reduce" },
    exceptions = { "try", "catch", "throw", "finally" },
    comments = { "//", "/%*" },
    weight = 1.1
  },
  typescript = {
    control_flow = { "if", "else", "switch", "case", "try", "catch", "finally" },
    loops = { "for", "while", "do", "forEach", "map", "filter", "reduce" },
    exceptions = { "try", "catch", "throw", "finally" },
    comments = { "//", "/%*" },
    weight = 1.1
  },
  python = {
    control_flow = { "if", "elif", "else", "try", "except", "finally" },
    loops = { "for", "while" },
    exceptions = { "try", "except", "raise", "finally" },
    comments = { "#" },
    weight = 0.9
  },
  go = {
    control_flow = { "if", "else", "switch", "case", "select" },
    loops = { "for", "range" },
    exceptions = { "defer", "panic", "recover" },
    comments = { "//" },
    weight = 1.0
  },
  default = {
    control_flow = { "if", "else", "elif", "elseif", "switch", "case", "when" },
    loops = { "for", "while", "do", "each", "map", "filter" },
    exceptions = { "try", "catch", "except", "finally", "rescue" },
    comments = { "//", "#", "%-%-" },
    weight = 1.0
  }
}

--- Enhanced complexity estimation with language awareness and single-pass parsing
---@param lines table Array of function lines
---@param filetype string Vim filetype for language-specific patterns
---@return string complexity_label, integer score
function estimate_complexity(lines, filetype)
  local patterns = language_patterns[filetype] or language_patterns.default
  local LOC = #lines
  local max_indent = 0
  local branch_count, conditional_count, loop_count = 0, 0, 0
  
  -- Single-pass analysis for better performance
  for _, line in ipairs(lines) do
    -- Calculate indentation
    local indent = line:match("^(%s*)") or ""
    max_indent = math.max(max_indent, #indent)
    
    -- Remove comments based on language
    local clean_line = line
    for _, comment_pattern in ipairs(patterns.comments) do
      clean_line = clean_line:gsub("%s*" .. comment_pattern .. ".*", "")
    end
    
    -- Skip empty lines after comment removal
    if clean_line:match("^%s*$") then
      goto continue
    end
    
    -- Count control flow patterns
    for _, pattern in ipairs(patterns.control_flow) do
      local matches = select(2, clean_line:gsub("%f[%w_]" .. pattern .. "%f[%W_]", ""))
      branch_count = branch_count + matches
    end
    
    -- Count loop patterns (weighted higher)
    for _, pattern in ipairs(patterns.loops) do
      local matches = select(2, clean_line:gsub("%f[%w_]" .. pattern .. "%f[%W_]", ""))
      loop_count = loop_count + matches
    end
    
    -- Count exception handling patterns
    for _, pattern in ipairs(patterns.exceptions) do
      local matches = select(2, clean_line:gsub("%f[%w_]" .. pattern .. "%f[%W_]", ""))
      branch_count = branch_count + matches
    end
    
    -- Count logical operators in conditional contexts
    if clean_line:match("%f[%w_](if|while|elsif|elseif|elif)%f[%W_]") then
      local conditionals = select(2, clean_line:gsub("%f[%w_](and|or|not|&&|%|%||%?|:)%f[%W_]", ""))
      conditional_count = conditional_count + conditionals
    end
    
    ::continue::
  end
  
  -- Calculate weighted score with language-specific adjustments
  local base_score =
    branch_count * 3.0 +        -- if/else/case statements
    loop_count * 4.0 +           -- loops are more complex
    conditional_count * 2.0 +    -- logical operators in conditions
    math.min(LOC, 30) * 0.1 +    -- minimal LOC contribution, capped
    max_indent * 0.5             -- deep nesting adds complexity
  
  local score = base_score * patterns.weight
  
  -- Determine complexity label based on thresholds
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