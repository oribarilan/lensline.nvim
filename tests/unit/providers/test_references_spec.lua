local eq = assert.are.same

local function with_stub(mod, stub, fn)
  local orig = package.loaded[mod]
  package.loaded[mod] = stub
  local ok, err = pcall(fn)
  package.loaded[mod] = orig
  if not ok then error(err) end
end

describe("providers.references", function()
  local provider = require("lensline.providers.references")

  it("nerdfont: counts references", function()
    local calls = {}
    with_stub("lensline.utils", {
      get_lsp_references = function(_, _, cb) cb({ {}, {}, {} }) end,
      if_nerdfont_else = function(a, _) return a end,
    }, function()
      provider.handler(7, { line = 7 }, {}, function(res) table.insert(calls, res) end)
    end)
    eq({ { line = 7, text = "󰌹 3" } }, calls)
  end)

  it("no nerdfont: plain count + suffix", function()
    local out
    with_stub("lensline.utils", {
      get_lsp_references = function(_, _, cb) cb({ {}, {} }) end,
      if_nerdfont_else = function(_, b) return b end,
    }, function()
      provider.handler(9, { line = 9 }, {}, function(res) out = res end)
    end)
    eq({ line = 9, text = "2 refs" }, out)
  end)

  it("zero refs nerdfont", function()
    local out
    with_stub("lensline.utils", {
      get_lsp_references = function(_, _, cb) cb({}) end,
      if_nerdfont_else = function(a, _) return a end,
    }, function()
      provider.handler(11, { line = 11 }, {}, function(res) out = res end)
    end)
    eq({ line = 11, text = "󰌹 0" }, out)
  end)

  it("zero refs no nerdfont", function()
    local out
    with_stub("lensline.utils", {
      get_lsp_references = function(_, _, cb) cb({}) end,
      if_nerdfont_else = function(_, b) return b end,
    }, function()
      provider.handler(12, { line = 12 }, {}, function(res) out = res end)
    end)
    eq({ line = 12, text = "0 refs" }, out)
  end)

  it("nil references", function()
    local marker = "unset"
    with_stub("lensline.utils", {
      get_lsp_references = function(_, _, cb) cb(nil) end,
      if_nerdfont_else = function(a, _) return a end,
    }, function()
      provider.handler(3, { line = 3 }, {}, function(res) marker = res end)
    end)
    eq(nil, marker)
  end)

  it("single callback invocation", function()
    local count = 0
    with_stub("lensline.utils", {
      get_lsp_references = function(_, _, cb) cb({ {}, {} }) end,
      if_nerdfont_else = function(_, b) return b end,
    }, function()
      provider.handler(15, { line = 15 }, {}, function() count = count + 1 end)
    end)
    eq(1, count)
  end)
end)