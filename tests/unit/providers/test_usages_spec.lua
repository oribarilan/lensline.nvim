local eq = assert.are.same

local function with_stub(mod, stub, fn)
  local orig = package.loaded[mod]
  package.loaded[mod] = stub
  local ok, err = pcall(fn)
  package.loaded[mod] = orig
  if not ok then error(err) end
end

describe("providers.usages", function()
  local provider = require("lensline.providers.usages")

  describe("collapsed view (default)", function()
    it("aggregates all usage types", function()
      local calls = {}
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {}, {}, {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end,
        get_lsp_implementations = function(_, _, cb) cb({ {}, {} }) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(7, { line = 7 }, {}, function(res) table.insert(calls, res) end)
        end)
      end)
      eq({ { line = 7, text = "6 usages" } }, calls)
    end)

    it("shows total with suffix", function()
      local out
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({}) end,
        get_lsp_implementations = function(_, _, cb) cb({ {} }) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(9, { line = 9 }, {}, function(res) out = res end)
        end)
      end)
      eq({ line = 9, text = "2 usages" }, out)
    end)

    it("singular form for single usage", function()
      local out
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({}) end,
        get_lsp_implementations = function(_, _, cb) cb({}) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(5, { line = 5 }, {}, function(res) out = res end)
        end)
      end)
      eq({ line = 5, text = "1 usage" }, out)
    end)

    it("shows zero usages when no usages found", function()
      local out
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({}) end,
        get_lsp_definitions = function(_, _, cb) cb({}) end,
        get_lsp_implementations = function(_, _, cb) cb({}) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(3, { line = 3 }, {}, function(res) out = res end)
        end)
      end)
      eq({ line = 3, text = "0 usages" }, out)
    end)
  end)

  describe("expanded view (toggled)", function()
    it("shows breakdown with default separator", function()
      local out
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {}, {}, {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end,
        get_lsp_implementations = function(_, _, cb) cb({ {}, {} }) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return true end,
        }, function()
          provider.handler(7, { line = 7 }, {}, function(res) out = res end)
        end)
      end)
      eq({ line = 7, text = "3 ref, 1 def, 2 impl" }, out)
    end)

    it("uses custom separator from provider config", function()
      local out
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end,
        get_lsp_implementations = function(_, _, cb) cb({ {} }) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return true end,
        }, function()
          provider.handler(4, { line = 4 }, { inner_separator = " • " }, function(res) out = res end)
        end)
      end)
      eq({ line = 4, text = "1 ref • 1 def • 1 impl" }, out)
    end)

    it("only shows non-zero counts", function()
      local out
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {}, {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({}) end,
        get_lsp_implementations = function(_, _, cb) cb({}) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return true end,
        }, function()
          provider.handler(6, { line = 6 }, {}, function(res) out = res end)
        end)
      end)
      eq({ line = 6, text = "2 ref" }, out)
    end)

    it("shows zero usages in expanded mode", function()
      local out
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({}) end,
        get_lsp_definitions = function(_, _, cb) cb({}) end,
        get_lsp_implementations = function(_, _, cb) cb({}) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return true end,
        }, function()
          provider.handler(8, { line = 8 }, {}, function(res) out = res end)
        end)
      end)
      eq({ line = 8, text = "0 usages" }, out)
    end)
  end)

  describe("graceful error handling", function()
    it("handles LSP request failures gracefully", function()
      local out
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb(nil) end,  -- Failed request
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end,
        get_lsp_implementations = function(_, _, cb) cb({ {} }) end,
        if_nerdfont_else = function(_, b) return b end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(10, { line = 10 }, {}, function(res) out = res end)
        end)
      end)
      eq({ line = 10, text = "2 usages" }, out)  -- Shows partial results
    end)

    it("handles all LSP request failures", function()
      local out
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb(nil) end,
        get_lsp_definitions = function(_, _, cb) cb(nil) end,
        get_lsp_implementations = function(_, _, cb) cb(nil) end,
        if_nerdfont_else = function(_, b) return b end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(12, { line = 12 }, {}, function(res) out = res end)
        end)
      end)
      eq({ line = 12, text = "0 usages" }, out)  -- Shows zero when all fail
    end)
  end)
end)