local utils = require("lensline.utils")
local blame_cache = require("lensline.blame_cache")

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


-- Last Author Provider
-- Shows the most recent Git author and date for functions/methods
return {
  name = "last_author",
  event = { "BufRead", "BufWritePost" },
  handler = function(bufnr, func_info, provider_config, callback)
    local debug = require("lensline.debug")
    local config = require("lensline.config")
    debug.log_context("LastAuthor", "handler called for function '" .. (func_info.name or "unknown") .. "' at line " .. func_info.line)
    
    -- Get the file path and validate it
    local filename = vim.api.nvim_buf_get_name(bufnr)
    if filename == "" or not vim.loop.fs_stat(filename) then
      debug.log_context("LastAuthor", "invalid or unsaved file: " .. (filename or "empty"))
      callback(nil)
      return
    end
    
    debug.log_context("LastAuthor", "processing file: " .. filename)
    
    -- Configure cache using provider config
    local cache_max_files = provider_config and provider_config.cache_max_files or 50
    blame_cache.configure({ max_files = cache_max_files })
    
    -- Use cached blame data to get function author
    local author_info = blame_cache.get_function_author(filename, bufnr, func_info)
    
    if not author_info then
      debug.log_context("LastAuthor", "no author info found for function at line " .. func_info.line)
      callback(nil)
      return
    end
    
    -- Format the result
    local opts = config.get()
    local relative_time = format_relative_time(author_info.time)
    local result_text
    if opts.style.use_nerdfont then
      result_text = "󰊢 " .. author_info.author .. ", " .. relative_time
    else
      result_text = author_info.author .. ", " .. relative_time
    end
    
    debug.log_context("LastAuthor", "final result: " .. result_text)
    
    local result = {
      line = func_info.line,
      text = result_text
    }
    
    -- Always call callback (async-only)
    callback(result)
  end
}