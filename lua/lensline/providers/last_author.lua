local utils = require("lensline.utils")

-- Helper function to format time as natural relative text (10min ago, 2h ago, 3d ago, etc.)
local function format_relative_time(timestamp)
  local now = os.time()
  local diff = now - timestamp
  
  -- Less than 1 hour -> Xmin ago (rounded up, minimum 1min)
  if diff < 3600 then
    local minutes = math.max(1, math.ceil(diff / 60))
    return minutes .. "min ago"
  end
  
  -- 1-23 hours -> Xh ago (rounded)
  if diff < 86400 then -- 24 hours
    local hours = math.floor(diff / 3600)
    return hours .. "h ago"
  end
  
  -- 1-364 days -> Xd ago (rounded)
  if diff < 31536000 then -- 365 days
    local days = math.floor(diff / 86400)
    return days .. "d ago"
  end
  
  -- 1+ years -> Xy ago (rounded)
  local years = math.floor(diff / 31536000)
  return years .. "y ago"
end

-- Helper function to parse git blame --line-porcelain output to find the latest author
local function parse_blame_output(blame_output, debug)
  local latest_author, latest_time = nil, 0
  local current_author, current_time = nil, nil
  
  debug.log_context("LastAuthor", "parsing " .. #blame_output .. " lines of blame output")
  
  for _, line in ipairs(blame_output) do
    -- Extract author name
    local author = line:match("^author (.+)$")
    if author then
      current_author = author
    end
    
    -- Extract author timestamp
    local time_str = line:match("^author%-time (%d+)$")
    if time_str then
      current_time = tonumber(time_str)
      
      -- Check if this is the latest author so far
      if current_author and current_time and current_time > latest_time then
        latest_author = current_author
        latest_time = current_time
        debug.log_context("LastAuthor", "new latest author: " .. latest_author .. " at " .. latest_time)
      end
    end
  end
  
  if latest_author and latest_time > 0 then
    -- Handle uncommitted changes with special author name
    if latest_author == "Not Committed Yet" then
      latest_author = "uncommitted"
    end
    
    local relative_time = format_relative_time(latest_time)
    local config = require("lensline.config")
    local opts = config.get()
    
    local result
    if opts.style.use_nerdfont then
      result = "󰊢 " .. latest_author .. ", " .. relative_time
    else
      result = latest_author .. ", " .. relative_time
    end
    
    debug.log_context("LastAuthor", "final result: " .. result)
    return result
  else
    debug.log_context("LastAuthor", "no valid author/time found in blame output")
    return nil
  end
end

-- Helper function to estimate function end line when not provided
local function estimate_function_end(bufnr, start_line, debug)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, math.min(start_line + 50, total_lines), false)
  
  local end_line = start_line
  local indent_level = nil
  
  for i, line in ipairs(lines) do
    local current_line = start_line + i - 1
    
    -- Skip empty lines
    if line:match("^%s*$") then
      goto continue
    end
    
    -- Get indentation of current line
    local current_indent = #line:match("^%s*")
    
    -- Set base indentation from first non-empty line (function declaration)
    if indent_level == nil then
      indent_level = current_indent
      goto continue
    end
    
    -- If we find a line with same or less indentation than function declaration, it's likely the end
    if current_indent <= indent_level and i > 1 then
      -- Make sure it's not just a continuation of the function signature
      if not line:match("^%s*[%w_(),:%s]*:?%s*$") then
        end_line = current_line - 1
        break
      end
    end
    
    -- Update end_line to include function body
    if current_indent > indent_level then
      end_line = current_line
    end
    
    ::continue::
  end
  
  -- Add a safety margin if we reached the scan limit
  if end_line == start_line + #lines - 1 and end_line < total_lines then
    end_line = math.min(start_line + 20, total_lines)  -- Conservative default
  end
  
  debug.log_context("LastAuthor", "estimated function end for line " .. start_line .. ": " .. end_line)
  return end_line
end

-- Helper function to get last author for a function asynchronously
local function get_function_last_author_async(filename, git_root, func_info, callback, debug, bufnr)
  local function_start = func_info.line
  local function_end = func_info.end_line
  
  -- If end_line is not provided, estimate it
  if not function_end then
    function_end = estimate_function_end(bufnr, function_start, debug)
  end
  
  local lines_range = ("%d,%d"):format(function_start, function_end)
  
  debug.log_context("LastAuthor", "async blame request for lines " .. lines_range)
  
  local uv = vim.loop
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local blame_output = {}
  local error_output = {}
  
  local handle
  handle = uv.spawn("git", {
    args = { "-C", git_root, "blame", "--line-porcelain", "-L", lines_range, filename },
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    handle:close()
    
    vim.schedule(function()
      if code ~= 0 then
        debug.log_context("LastAuthor", "git blame failed with code " .. code .. ": " .. table.concat(error_output, " "))
        callback(nil)
        return
      end
      
      local author_info = parse_blame_output(blame_output, debug)
      if author_info then
        callback({
          line = func_info.line,
          text = author_info
        })
      else
        callback(nil)
      end
    end)
  end)
  
  if not handle then
    debug.log_context("LastAuthor", "failed to spawn git blame process")
    callback(nil)
    return
  end
  
  uv.read_start(stdout, function(_, data)
    if data then
      for line in data:gmatch("[^\r\n]+") do
        table.insert(blame_output, line)
      end
    end
  end)
  
  uv.read_start(stderr, function(_, data)
    if data then
      for line in data:gmatch("[^\r\n]+") do
        table.insert(error_output, line)
      end
    end
  end)
end

-- Helper function to get last author for a function synchronously
local function get_function_last_author_sync(filename, git_root, func_info, debug, bufnr)
  local function_start = func_info.line
  local function_end = func_info.end_line
  
  -- If end_line is not provided, estimate it
  if not function_end then
    function_end = estimate_function_end(bufnr, function_start, debug)
  end
  
  local lines_range = ("%d,%d"):format(function_start, function_end)
  
  debug.log_context("LastAuthor", "sync blame request for lines " .. lines_range)
  
  local blame_cmd = { "git", "-C", git_root, "blame", "--line-porcelain", "-L", lines_range, filename }
  local blame_output = vim.fn.systemlist(blame_cmd)
  
  if vim.v.shell_error ~= 0 then
    debug.log_context("LastAuthor", "git blame command failed: " .. vim.v.shell_error)
    return nil
  end
  
  local author_info = parse_blame_output(blame_output, debug)
  local result = nil
  if author_info then
    result = {
      line = func_info.line,
      text = author_info
    }
  end
  
  return result
end

-- Last Author Provider
-- Shows the most recent Git author and date for functions/methods
return {
  name = "last_author",
  event = { "BufRead", "BufWritePost" },
  debounce = 500,
  handler = function(bufnr, func_info, callback)
    -- Early exit guard: check if this provider is disabled
    local config = require("lensline.config")
    local opts = config.get()
    local provider_config = nil
    
    -- Find this provider's config
    for _, provider in ipairs(opts.providers) do
      if provider.name == "last_author" then
        provider_config = provider
        break
      end
    end
    
    -- Exit early if provider is disabled
    if provider_config and provider_config.enabled == false then
      if callback then
        callback(nil)
      end
      return nil
    end
    
    local debug = require("lensline.debug")
    debug.log_context("LastAuthor", "handler called for function '" .. (func_info.name or "unknown") .. "' at line " .. func_info.line)
    
    -- Get the file path and validate it
    local filename = vim.api.nvim_buf_get_name(bufnr)
    if filename == "" or not vim.loop.fs_stat(filename) then
      debug.log_context("LastAuthor", "invalid or unsaved file: " .. (filename or "empty"))
      if callback then callback(nil) end
      return nil
    end
    
    debug.log_context("LastAuthor", "processing file: " .. filename)
    
    -- Check if we're in a git repository
    local file_dir = vim.fn.fnamemodify(filename, ":h")
    local git_root_cmd = { "git", "-C", file_dir, "rev-parse", "--show-toplevel" }
    local git_root_result = vim.fn.systemlist(git_root_cmd)
    local git_root = git_root_result[1]
    
    if vim.v.shell_error ~= 0 or not git_root or git_root == "" then
      debug.log_context("LastAuthor", "not in git repository or git command failed")
      if callback then callback(nil) end
      return nil
    end
    
    debug.log_context("LastAuthor", "git root: " .. git_root)
    
    -- If no callback provided, run synchronously
    if not callback then
      debug.log_context("LastAuthor", "running in synchronous mode")
      return get_function_last_author_sync(filename, git_root, func_info, debug, bufnr)
    end
    
    -- Run asynchronously
    debug.log_context("LastAuthor", "running in async mode for function '" .. (func_info.name or "unknown") .. "' at line " .. func_info.line)
    get_function_last_author_async(filename, git_root, func_info, callback, debug, bufnr)
    return nil  -- Must return nil for async mode
  end
}