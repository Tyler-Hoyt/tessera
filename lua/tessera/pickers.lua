local M = {}

local SCRIPT_PREFIX = { server = "[S]", client = "[C]", startup = "[U]" }

local function notify_warn(msg)
  vim.notify("[Tessera] " .. msg, vim.log.levels.WARN)
end

local function notify_err(msg)
  vim.notify("[Tessera] " .. msg, vim.log.levels.ERROR)
end

local function get_fzf()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify_err("fzf-lua is not installed")
    return nil
  end
  return fzf
end

local function get_root()
  local p = require("tessera.project").find_root()
  if not p then
    notify_warn("no KubeJS project detected from current buffer")
    return nil
  end
  return p
end

local function list_files(dir)
  local stat = vim.uv.fs_stat(dir)
  if not stat or stat.type ~= "directory" then return {} end
  local results = vim.fs.find(function(name, _)
    return not name:match("^%.")
  end, { path = dir, type = "file", limit = math.huge })
  return results
end

local function list_subdirs(dir)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return {} end
  local out = {}
  while true do
    local name, type_ = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if type_ == "directory" then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local function list_files_in(dir, ext)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return {} end
  local out = {}
  while true do
    local name, type_ = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if type_ == "file" and (not ext or name:sub(-#ext) == ext) then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local function quote_for_current_line()
  local style = require("tessera.config").get().pickers.quote_style
  if style == "single" then return "'" end
  if style == "double" then return '"' end
  local line = vim.api.nvim_get_current_line()
  local s = 0
  for _ in line:gmatch("'") do s = s + 1 end
  local d = 0
  for _ in line:gmatch('"') do d = d + 1 end
  if d > s then return '"' end
  return "'"
end

local function insert_at_cursor(text)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  vim.api.nvim_set_current_line(before .. text .. after)
  vim.api.nvim_win_set_cursor(0, { row, col + #text })
end

local function insert_block(lines, cursor_offset_line)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, lines)
  local target = row - 1 + (cursor_offset_line or 0)
  local target_line = vim.api.nvim_buf_get_lines(0, target, target + 1, false)[1] or ""
  vim.api.nvim_win_set_cursor(0, { target + 1, #target_line })
end

function M.scripts(scope)
  local fzf = get_fzf(); if not fzf then return end
  local cfg = require("tessera.config").get()
  local p = get_root(); if not p then return end
  local prefix = cfg.pickers.scripts_prefix

  local entries = {}
  local lookup = {}
  local scopes = scope and { scope } or { "server", "client", "startup" }
  for _, s in ipairs(scopes) do
    local sub = cfg.script_subdirs[s]
    if sub then
      local dir = vim.fs.joinpath(p.root, sub)
      for _, file in ipairs(list_files(dir)) do
        local rel = file:sub(#dir + 2)
        local display = (prefix and not scope) and (SCRIPT_PREFIX[s] .. " " .. rel) or rel
        entries[#entries + 1] = display
        lookup[display] = file
      end
    end
  end

  if #entries == 0 then
    notify_warn("no script files found under " .. p.root)
    return
  end

  fzf.fzf_exec(entries, {
    prompt = "Scripts> ",
    actions = {
      ["default"] = function(selected)
        local path = lookup[selected[1]]
        if path then vim.cmd.edit(vim.fn.fnameescape(path)) end
      end,
    },
  })
end

local function add_pack_dir(p, rel, label_prefix, entries, lookup)
  local dir = vim.fs.joinpath(p.root, rel)
  for _, ns in ipairs(list_subdirs(dir)) do
    local label = label_prefix .. ": " .. ns
    entries[#entries + 1] = label
    lookup[label] = vim.fs.joinpath(dir, ns)
  end
  for _, zip in ipairs(list_files_in(dir, ".zip")) do
    local label = label_prefix .. ": " .. zip
    entries[#entries + 1] = label
    lookup[label] = vim.fs.joinpath(dir, zip)
  end
end

local function pack_entries(p, sub_in_kubejs, top_level_dir, kind)
  local entries, lookup = {}, {}
  add_pack_dir(p, sub_in_kubejs, "kubejs", entries, lookup)
  add_pack_dir(p, top_level_dir, top_level_dir, entries, lookup)

  local cfg = require("tessera.config").get()
  local loader = cfg.auto_loader
  if loader then
    local paths = cfg.auto_loader_paths and cfg.auto_loader_paths[loader]
    local rel = paths and paths[kind]
    if rel then
      add_pack_dir(p, rel, loader, entries, lookup)
    end
  end

  return entries, lookup
end

local function open_pack(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then return end
  if stat.type == "directory" then
    local mcmeta = vim.fs.joinpath(path, "pack.mcmeta")
    if vim.uv.fs_stat(mcmeta) then
      vim.cmd.edit(vim.fn.fnameescape(mcmeta))
    else
      vim.cmd.edit(vim.fn.fnameescape(path))
    end
  else
    notify_warn("packed archive: " .. path)
  end
end

function M.datapacks()
  local fzf = get_fzf(); if not fzf then return end
  local cfg = require("tessera.config").get()
  local p = get_root(); if not p then return end
  local entries, lookup = pack_entries(p, cfg.data_subdir, cfg.datapack_dir, "datapacks")
  if #entries == 0 then notify_warn("no datapacks found"); return end
  fzf.fzf_exec(entries, {
    prompt = "Datapacks> ",
    actions = { ["default"] = function(selected) open_pack(lookup[selected[1]]) end },
  })
end

function M.resourcepacks()
  local fzf = get_fzf(); if not fzf then return end
  local cfg = require("tessera.config").get()
  local p = get_root(); if not p then return end
  local entries, lookup = pack_entries(p, cfg.assets_subdir, cfg.resourcepack_dir, "resourcepacks")
  if #entries == 0 then notify_warn("no resourcepacks found"); return end
  fzf.fzf_exec(entries, {
    prompt = "Resourcepacks> ",
    actions = { ["default"] = function(selected) open_pack(lookup[selected[1]]) end },
  })
end

function M.ids(kind)
  local fzf = get_fzf(); if not fzf then return end
  local p = get_root(); if not p then return end
  local registry = require("tessera.registry").get(p.root)
  local pool = {}
  if kind then
    local bucket = registry.ids[kind]
    if not bucket and kind == "tag" then
      for k, v in pairs(registry.ids) do
        if k:sub(1, 4) == "tag_" then
          for _, s in ipairs(v) do pool[#pool + 1] = s end
        end
      end
    elseif bucket then
      for _, s in ipairs(bucket) do pool[#pool + 1] = s end
    end
  else
    for _, bucket in pairs(registry.ids) do
      for _, s in ipairs(bucket) do pool[#pool + 1] = s end
    end
  end

  if #pool == 0 then
    if vim.tbl_isempty(registry.ids) then
      notify_warn("no IDs in registry — run /probejs dump in-game, then :Tessera probe refresh")
    else
      notify_warn("no IDs found for kind '" .. tostring(kind) .. "' (have: " .. table.concat(vim.tbl_keys(registry.ids), ", ") .. ")")
    end
    return
  end

  fzf.fzf_exec(pool, {
    prompt = (kind and (kind .. " IDs> ")) or "IDs> ",
    actions = {
      ["default"] = function(selected)
        local q = quote_for_current_line()
        insert_at_cursor(q .. selected[1] .. q)
      end,
    },
  })
end

function M.events(category)
  local fzf = get_fzf(); if not fzf then return end
  local p = get_root(); if not p then return end
  local registry = require("tessera.registry").get(p.root)

  local entries, lookup = {}, {}
  local cats = category and { category } or vim.tbl_keys(registry.events)
  table.sort(cats)
  for _, cat in ipairs(cats) do
    local group = registry.events[cat]
    if group and group.ns and group.names then
      for _, evt in ipairs(group.names) do
        local label = group.ns .. "." .. evt
        entries[#entries + 1] = label
        lookup[label] = { ns = group.ns, evt = evt }
      end
    end
  end

  if #entries == 0 then
    notify_warn("no events found — run /probejs dump in-game, then :Tessera probe refresh")
    return
  end

  fzf.fzf_exec(entries, {
    prompt = "Events> ",
    actions = {
      ["default"] = function(selected)
        local pick = lookup[selected[1]]
        if not pick then return end
        insert_block({
          pick.ns .. "." .. pick.evt .. "(event => {",
          "  ",
          "})",
        }, 1)
      end,
    },
  })
end

return M
