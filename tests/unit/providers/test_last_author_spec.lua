local eq = assert.are.same

-- Helper to temporarily stub a module (full replacement)
local function with_stub(mod, stub, fn)
  local orig = package.loaded[mod]
  package.loaded[mod] = stub
  local ok, err = pcall(fn)
  package.loaded[mod] = orig
  if not ok then error(err) end
end

-- Patch selected functions on an already-required module (preserves existing upvalues)
local function with_module_patches(mod_name, patches, fn)
  local mod = require(mod_name)
  local originals = {}
  for k, v in pairs(patches) do
    originals[k] = mod[k]
    mod[k] = v
  end
  local ok, err = pcall(fn)
  for k, v in pairs(originals) do
    mod[k] = v
  end
  if not ok then error(err) end
end

-- Freezeable time helper
local function with_time(fixed_time, fn)
  local orig_time = os.time
  os.time = function() return fixed_time end
  local ok, err = pcall(fn)
  os.time = orig_time
  if not ok then error(err) end
end

describe("providers.last_author", function()
  local provider = require("lensline.providers.last_author")

  -- Base temp file directory (inside gitignored tests/tmp/)
  local base_tmp = vim.fn.getcwd() .. "/tests/tmp"
  if vim.fn.isdirectory(base_tmp) == 0 then
    vim.fn.mkdir(base_tmp, "p")
  end

  -- Create a unique real file so fs_stat passes (different per test to avoid name collisions if a prior buffer lingers after failure)
  local function make_real_file(tag)
    local path = string.format("%s/.tmp_last_author_%s.lua", base_tmp, tag)
    local fh = assert(io.open(path, "w"))
    fh:write("-- temp file for last_author tests\nlocal function foo() end\n")
    fh:close()
    return path
  end

  local buf_counter = 0
  local function mk_buf()
    buf_counter = buf_counter + 1
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "local function foo()",
      "  return 42",
      "end",
    })
    local path = make_real_file(buf_counter)
    vim.api.nvim_buf_set_name(bufnr, path)
    return bufnr
  end

  it("returns nil when blame cache has no data", function()
    local bufnr = mk_buf()
    local called = false
    with_stub("lensline.debug", { log_context = function() end }, function()
      with_module_patches("lensline.blame_cache", {
        configure = function() end,
        get_function_author = function() return nil end,
      }, function()
        with_stub("lensline.utils", {
          if_nerdfont_else = function(a, b) return a end,
        }, function()
          provider.handler(bufnr, { line = 1 }, {}, function(res)
            called = true
            eq(nil, res)
          end)
        end)
      end)
    end)
    eq(true, called)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("formats minutes ago (>=1 min, < 60m)", function()
    local now = 1000000
    local bufnr = mk_buf()
    local out
    with_time(now, function()
      with_stub("lensline.debug", { log_context = function() end }, function()
        with_module_patches("lensline.blame_cache", {
          configure = function() end,
          get_function_author = function() return { author = "Alice", time = now - 125 } end, -- 2.08m -> ceil => 3min
        }, function()
          with_stub("lensline.utils", {
            if_nerdfont_else = function(a, b) return a end,
          }, function()
            provider.handler(bufnr, { line = 1 }, {}, function(res) out = res end)
          end)
        end)
      end)
    end)
    eq({ line = 1, text = "󰊢 Alice, 3min ago" }, out)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("formats hours ago (< 24h) no nerdfont icon", function()
    local now = 2000000
    local bufnr = mk_buf()
    local out
    with_time(now, function()
      with_stub("lensline.debug", { log_context = function() end }, function()
        with_module_patches("lensline.blame_cache", {
          configure = function() end,
          get_function_author = function() return { author = "Bob", time = now - (3 * 3600 + 15) } end,
        }, function()
          with_stub("lensline.utils", {
            if_nerdfont_else = function(a, b) return "" end, -- simulate no nerdfont
          }, function()
            provider.handler(bufnr, { line = 1 }, {}, function(res) out = res end)
          end)
        end)
      end)
    end)
    eq({ line = 1, text = "Bob, 3h ago" }, out)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("formats days ago (< 365d)", function()
    local now = 3000000
    local bufnr = mk_buf()
    local out
    with_time(now, function()
      with_stub("lensline.debug", { log_context = function() end }, function()
        with_module_patches("lensline.blame_cache", {
          configure = function() end,
          get_function_author = function() return { author = "Carol", time = now - (5 * 86400 + 100) } end,
        }, function()
          with_stub("lensline.utils", {
            if_nerdfont_else = function(a, b) return a end,
          }, function()
            provider.handler(bufnr, { line = 2 }, {}, function(res) out = res end)
          end)
        end)
      end)
    end)
    eq({ line = 2, text = "󰊢 Carol, 5d ago" }, out)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("formats years ago (>= 365d)", function()
    local now = 4000000
    local bufnr = mk_buf()
    local out
    with_time(now, function()
      with_stub("lensline.debug", { log_context = function() end }, function()
        with_module_patches("lensline.blame_cache", {
          configure = function() end,
          get_function_author = function() return { author = "Dave", time = now - (2 * 31536000 + 1234) } end,
        }, function()
          with_stub("lensline.utils", {
            if_nerdfont_else = function(a, b) return a end,
          }, function()
            provider.handler(bufnr, { line = 3 }, {}, function(res) out = res end)
          end)
        end)
      end)
    end)
    eq({ line = 3, text = "󰊢 Dave, 2y ago" }, out)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)