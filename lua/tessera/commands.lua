local M = {}

local SUBCOMMANDS = {
  scripts       = { args = { "server", "client", "startup" } },
  datapacks     = {},
  resourcepacks = {},
  ids           = { args = { "item", "block", "fluid", "entity", "tag", "enchantment", "effect", "biome", "dimension" } },
  events        = { args = { "server", "item", "block", "startup", "client", "player", "entity", "network", "world", "level", "jei", "rei", "emi", "worldgen", "blockstate", "lootjs" } },
  probe         = { args = { "refresh" } },
  root          = {},
  errors        = { args = { "all", "server", "client", "startup", "latest", "watch" } },
}

local function split(s)
  local out = {}
  for word in s:gmatch("%S+") do out[#out + 1] = word end
  return out
end

local function getCommand(opts)
  local raw = split((opts and opts.args) or "")
  if #raw == 0 then return nil end
  return {
    subCommand = raw[1],
    args = #raw > 1 and table.concat(raw, " ", 2) or nil,
  }
end

local function require_project()
  local p = require("tessera.project").find_root()
  if not p then
    vim.notify("[Tessera] no project detected", vim.log.levels.WARN)
  end
  return p
end

local HANDLERS = {
  scripts       = function(c) require("tessera.pickers").scripts(c.args) end,
  datapacks     = function()  require("tessera.pickers").datapacks() end,
  resourcepacks = function()  require("tessera.pickers").resourcepacks() end,
  ids           = function(c) require("tessera.pickers").ids(c.args) end,
  events        = function(c) require("tessera.pickers").events(c.args) end,

  probe = function(c)
    if c.args ~= "refresh" then
      vim.notify("[Tessera] :Tessera probe refresh", vim.log.levels.INFO); return
    end
    local p = require_project(); if not p then return end
    require("tessera.registry").rebuild(p.root)
    vim.notify("[Tessera] probe registry rebuilt for " .. p.root, vim.log.levels.INFO)
  end,

  errors = function(c)
    local p = require_project(); if not p then return end
    local logs = require("tessera.logs")
    if c.args == "watch" then
      if logs.is_watching(p.root) then
        logs.unwatch(p.root)
        vim.notify("[Tessera] log watcher stopped", vim.log.levels.INFO)
      else
        logs.watch(p.root)
        vim.notify("[Tessera] log watcher started for " .. p.root, vim.log.levels.INFO)
      end
      return
    end
    local entries = logs.collect(p.root, c.args)
    if #entries == 0 then
      vim.notify("[Tessera] no errors found in logs", vim.log.levels.INFO)
    else
      logs.populate_quickfix(entries, "Tessera errors (" .. (c.args or "all") .. ")")
    end
  end,

  root = function()
    local p = require("tessera.project").find_root()
    if p then
      vim.notify("[Tessera] root: " .. p.root .. "\nkubejs: " .. p.kubejs, vim.log.levels.INFO)
    else
      vim.notify("[Tessera] no KubeJS project detected from current buffer", vim.log.levels.WARN)
    end
  end,
}

function M.dispatch(opts)
  local command = getCommand(opts)
  if not command then
    vim.notify("[Tessera] usage: :Tessera <" .. table.concat(vim.tbl_keys(SUBCOMMANDS), "|") .. ">", vim.log.levels.INFO)
    return
  end
  local handler = HANDLERS[command.subCommand]
  if handler then
    handler(command)
  else
    vim.notify("[Tessera] unknown subcommand: " .. command.subCommand, vim.log.levels.ERROR)
  end
end

function M.complete(arglead, cmdline, _)
  local args = split(cmdline)
  local at_subcommand = #args <= 1 or (#args == 2 and arglead ~= "")
  if at_subcommand then
    local keys = vim.tbl_keys(SUBCOMMANDS)
    table.sort(keys)
    return vim.tbl_filter(function(k) return k:find(arglead, 1, true) == 1 end, keys)
  end
  local sub = args[2]
  local spec = SUBCOMMANDS[sub]
  if not spec or not spec.args then return {} end
  return vim.tbl_filter(function(k) return k:find(arglead, 1, true) == 1 end, spec.args)
end

return M
