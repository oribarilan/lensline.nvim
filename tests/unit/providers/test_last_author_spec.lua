-- tests/unit/providers/test_last_author_spec.lua
-- unit tests for lensline.providers.last_author (author and time formatting)

local eq = assert.are.same

describe("providers.last_author.handler", function()
  local provider = require("lensline.providers.last_author")
  local created_buffers = {}

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
    provider = require("lensline.providers.last_author")
  end

  local function with_stub(mod, stub, fn)
    local orig = package.loaded[mod]
    package.loaded[mod] = stub
    local ok, err = pcall(fn)
    package.loaded[mod] = orig
    if not ok then error(err) end
  end

  local function with_module_patches(mod_name, patches, fn)
    local mod = require(mod_name)
    local originals = {}
    for k, v in pairs(patches) do
      originals[k] = mod[k]
      mod[k] = v
    end
    local ok, err = pcall(fn)
    for k, _ in pairs(originals) do
      mod[k] = originals[k]
    end
    if not ok then error(err) end
  end

  local function with_time(fixed_time, fn)
    local orig_time = os.time
    os.time = function() return fixed_time end
    local ok, err = pcall(fn)
    os.time = orig_time
    if not ok then error(err) end
  end

  local function make_buf()
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(created_buffers, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "local function foo()",
      "  return 42",
      "end",
    })
    -- set a dummy name to avoid fs operations
    vim.api.nvim_buf_set_name(bufnr, "/tmp/test_file.lua")
    return bufnr
  end

  local function call_handler(blame_data, use_nerdfont, expected_result, func_line)
    func_line = func_line or 1
    local bufnr = make_buf()
    local result = "unset"
    local called = false

    -- stub vim.loop.fs_stat to simulate file exists
    local orig_fs_stat = vim.loop.fs_stat
    vim.loop.fs_stat = function() return { type = "file" } end

    with_stub("lensline.debug", { log_context = function() end }, function()
      with_module_patches("lensline.blame_cache", {
        configure = function() end,
        get_function_author = function() return blame_data end,
      }, function()
        with_stub("lensline.utils", {
          if_nerdfont_else = function(nf, fallback)
            return use_nerdfont and nf or fallback
          end,
        }, function()
          provider.handler(bufnr, { line = func_line }, {}, function(res)
            called = true
            result = res
          end)
        end)
      end)
    end)

    -- restore fs_stat
    vim.loop.fs_stat = orig_fs_stat

    eq(true, called)
    eq(expected_result, result)
  end

  before_each(function()
    reset_modules()
    created_buffers = {}
  end)

  after_each(function()
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    reset_modules()
  end)

  it("returns nil when blame cache has no data", function()
    call_handler(nil, true, nil)
  end)

  it("handles uncommitted changes without timestamp", function()
    call_handler(
      { author = "uncommitted", time = nil },
      true,
      { line = 1, text = "󰊢 uncommitted" }
    )
  end)

  -- table-driven tests for time formatting scenarios
  local now = 1000000
  for _, case in ipairs({
    {
      name = "formats minutes ago (2+ minutes)",
      author = "Alice",
      time_ago = 125, -- seconds (2.08 min -> ceil to 3min)
      use_nerdfont = true,
      expected_text = "󰊢 Alice, 3min ago"
    },
    {
      name = "formats hours ago without nerdfont",
      author = "Bob", 
      time_ago = 3 * 3600 + 15, -- 3 hours 15 seconds -> 3h
      use_nerdfont = false,
      expected_text = "Bob, 3h ago"
    },
    {
      name = "formats days ago",
      author = "Carol",
      time_ago = 5 * 86400 + 100, -- 5 days 100 seconds -> 5d
      use_nerdfont = true,
      expected_text = "󰊢 Carol, 5d ago"
    },
    {
      name = "formats years ago",
      author = "Dave",
      time_ago = 2 * 365 * 86400 + 1234, -- 2+ years -> 2y
      use_nerdfont = true,
      expected_text = "󰊢 Dave, 2y ago"
    },
  }) do
    it(("time formatting: %s"):format(case.name), function()
      with_time(now, function()
        call_handler(
          { author = case.author, time = now - case.time_ago },
          case.use_nerdfont,
          { line = 1, text = case.expected_text }
        )
      end)
    end)
  end

  -- table-driven tests for line positioning
  for _, case in ipairs({
    {
      name = "uses correct line number from func_info",
      func_line = 1,
      expected_line = 1
    },
    {
      name = "uses different line number from func_info",
      func_line = 3,
      expected_line = 3
    },
  }) do
    it(("line positioning: %s"):format(case.name), function()
      with_time(now, function()
        call_handler(
          { author = "TestAuthor", time = now - 3600 },
          true,
          { line = case.expected_line, text = "󰊢 TestAuthor, 1h ago" },
          case.func_line
        )
      end)
    end)
  end
end)