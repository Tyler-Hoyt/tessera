local M = {}

function M.setup(opts)
  require("tessera.config").apply(opts)
end

local function lazy(mod)
  return setmetatable({}, {
    __index = function(_, k) return require(mod)[k] end,
  })
end

M.pickers  = lazy("tessera.pickers")
M.project  = lazy("tessera.project")
M.registry = lazy("tessera.registry")
M.probe    = lazy("tessera.probe")
M.config   = lazy("tessera.config")

return M
