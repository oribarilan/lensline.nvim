-- tests/unit/providers/test_usages_spec.lua
-- unit tests for lensline.providers.usages

local eq = assert.are.same

local function with_stub(mod, stub, fn)
  local orig = package.loaded[mod]
  package.loaded[mod] = stub
  local ok, err = pcall(fn)
  package.loaded[mod] = orig
  if not ok then error(err) end
end

describe("lensline.providers.usages", function()
  local usages_provider = require("lensline.providers.usages")

  it("has correct provider metadata", function()
    eq("usages", usages_provider.name)
    eq({ "LspAttach", "BufWritePost" }, usages_provider.event)
    eq("function", type(usages_provider.handler))
  end)

  it("single attribute with nerdfont", function()
    local result = nil
    local provider_config = {
      include = { "refs" },
      breakdown = false,
      show_zero = true,
      labels = { refs = "refs" },
      inner_separator = ", ",
    }
    
    with_stub("lensline.utils", {
      has_lsp_references_capability = function(_) return true end,
      get_lsp_references = function(_, _, cb) cb({ {}, {}, {}, {}, {} }) end, -- 5 refs
      if_nerdfont_else = function(a, _) return a end, -- nerdfont enabled
    }, function()
      usages_provider.handler(1, { line = 1 }, provider_config, function(res)
        result = res
      end)
    end)
    
    eq({ line = 1, text = "󰌹 5" }, result)
  end)

  it("single attribute without nerdfont", function()
    local result = nil
    local provider_config = {
      include = { "refs" },
      breakdown = false,
      show_zero = true,
      labels = { refs = "refs" },
      inner_separator = ", ",
    }
    
    with_stub("lensline.utils", {
      has_lsp_references_capability = function(_) return true end,
      get_lsp_references = function(_, _, cb) cb({ {}, {} }) end, -- 2 refs
      if_nerdfont_else = function(_, b) return b end, -- nerdfont disabled
    }, function()
      usages_provider.handler(1, { line = 1 }, provider_config, function(res)
        result = res
      end)
    end)
    
    eq({ line = 1, text = "2 refs" }, result)
  end)

  it("multiple attributes aggregated with nerdfont", function()
    local result = nil
    local provider_config = {
      include = { "refs", "defs", "impls" },
      breakdown = false,
      show_zero = true,
      labels = { refs = "refs", defs = "defs", impls = "impls", usages = "usages" },
      inner_separator = ", ",
    }
    
    with_stub("lensline.utils", {
      has_lsp_references_capability = function(_) return true end,
      has_lsp_definitions_capability = function(_) return true end,
      has_lsp_implementations_capability = function(_) return true end,
      get_lsp_references = function(_, _, cb) cb({ {}, {}, {}, {}, {} }) end, -- 5 refs
      get_lsp_definitions = function(_, _, cb) cb({ {} }) end, -- 1 def
      get_lsp_implementations = function(_, _, cb) cb({ {}, {} }) end, -- 2 impls
      if_nerdfont_else = function(a, _) return a end, -- nerdfont enabled
    }, function()
      usages_provider.handler(1, { line = 1 }, provider_config, function(res)
        result = res
      end)
    end)
    
    eq({ line = 1, text = "󰌹 8" }, result) -- 5+1+2 = 8
  end)

  it("breakdown mode with show_zero=true", function()
    local result = nil
    local provider_config = {
      include = { "refs", "defs", "impls" },
      breakdown = true,
      show_zero = true,
      labels = { refs = "refs", defs = "defs", impls = "impls" },
      inner_separator = ", ",
    }
    
    with_stub("lensline.utils", {
      has_lsp_references_capability = function(_) return true end,
      has_lsp_definitions_capability = function(_) return true end,
      has_lsp_implementations_capability = function(_) return true end,
      get_lsp_references = function(_, _, cb) cb({ {}, {}, {}, {}, {} }) end, -- 5 refs
      get_lsp_definitions = function(_, _, cb) cb({}) end, -- 0 defs
      get_lsp_implementations = function(_, _, cb) cb({ {}, {} }) end, -- 2 impls
      if_nerdfont_else = function(a, _) return a end, -- nerdfont (not used in breakdown)
    }, function()
      usages_provider.handler(1, { line = 1 }, provider_config, function(res)
        result = res
      end)
    end)
    
    eq({ line = 1, text = "5 refs, 0 defs, 2 impls" }, result)
  end)

  it("breakdown mode with show_zero=false", function()
    local result = nil
    local provider_config = {
      include = { "refs", "defs", "impls" },
      breakdown = true,
      show_zero = false,
      labels = { refs = "refs", defs = "defs", impls = "impls" },
      inner_separator = ", ",
    }
    
    with_stub("lensline.utils", {
      has_lsp_references_capability = function(_) return true end,
      has_lsp_definitions_capability = function(_) return true end,
      has_lsp_implementations_capability = function(_) return true end,
      get_lsp_references = function(_, _, cb) cb({ {}, {}, {}, {}, {} }) end, -- 5 refs
      get_lsp_definitions = function(_, _, cb) cb({}) end, -- 0 defs
      get_lsp_implementations = function(_, _, cb) cb({ {}, {} }) end, -- 2 impls
      if_nerdfont_else = function(a, _) return a end, -- nerdfont (not used in breakdown)
    }, function()
      usages_provider.handler(1, { line = 1 }, provider_config, function(res)
        result = res
      end)
    end)
    
    eq({ line = 1, text = "5 refs, 2 impls" }, result) -- 0 defs hidden
  end)

  it("unsupported capability is ignored", function()
    local result = nil
    local provider_config = {
      include = { "refs", "impls" },
      breakdown = false,
      show_zero = true,
      labels = { refs = "refs", impls = "impls", usages = "usages" },
      inner_separator = ", ",
    }
    
    with_stub("lensline.utils", {
      has_lsp_references_capability = function(_) return true end,
      has_lsp_implementations_capability = function(_) return false end, -- not supported
      get_lsp_references = function(_, _, cb) cb({ {}, {} }) end, -- 2 refs
      if_nerdfont_else = function(a, _) return a end,
    }, function()
      usages_provider.handler(1, { line = 1 }, provider_config, function(res)
        result = res
      end)
    end)
    
    eq({ line = 1, text = "󰌹 2" }, result) -- only refs shown, impls ignored
  end)

  it("no supported capabilities returns nil", function()
    local result = "unset"
    local provider_config = {
      include = { "refs", "defs" },
      breakdown = false,
      show_zero = true,
      labels = { refs = "refs", defs = "defs" },
      inner_separator = ", ",
    }
    
    with_stub("lensline.utils", {
      has_lsp_references_capability = function(_) return false end,
      has_lsp_definitions_capability = function(_) return false end,
      if_nerdfont_else = function(a, _) return a end,
    }, function()
      usages_provider.handler(1, { line = 1 }, provider_config, function(res)
        result = res
      end)
    end)
    
    eq(nil, result)
  end)

  it("zero counts with show_zero=false returns nil", function()
    local result = "unset"
    local provider_config = {
      include = { "refs", "defs" },
      breakdown = false,
      show_zero = false,
      labels = { refs = "refs", defs = "defs", usages = "usages" },
      inner_separator = ", ",
    }
    
    with_stub("lensline.utils", {
      has_lsp_references_capability = function(_) return true end,
      has_lsp_definitions_capability = function(_) return true end,
      get_lsp_references = function(_, _, cb) cb({}) end, -- 0 refs
      get_lsp_definitions = function(_, _, cb) cb({}) end, -- 0 defs
      if_nerdfont_else = function(a, _) return a end,
    }, function()
      usages_provider.handler(1, { line = 1 }, provider_config, function(res)
        result = res
      end)
    end)
    
    eq(nil, result)
  end)

  it("zero counts with show_zero=true shows zeros", function()
    local result = nil
    local provider_config = {
      include = { "refs", "defs" },
      breakdown = false,
      show_zero = true,
      labels = { refs = "refs", defs = "defs", usages = "usages" },
      inner_separator = ", ",
    }
    
    with_stub("lensline.utils", {
      has_lsp_references_capability = function(_) return true end,
      has_lsp_definitions_capability = function(_) return true end,
      get_lsp_references = function(_, _, cb) cb({}) end, -- 0 refs
      get_lsp_definitions = function(_, _, cb) cb({}) end, -- 0 defs
      if_nerdfont_else = function(a, _) return a end,
    }, function()
      usages_provider.handler(1, { line = 1 }, provider_config, function(res)
        result = res
      end)
    end)
    
    eq({ line = 1, text = "󰌹 0" }, result)
  end)
end)