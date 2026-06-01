local M = {}

local function category_from_ns(ns)
  return (ns:gsub("Events$", "")):lower()
end

local function classify_id(name)
  local lower = name:lower()
  if lower:find("tag") then
    if     lower:find("item")   then return "tag_item"
    elseif lower:find("block")  then return "tag_block"
    elseif lower:find("fluid")  then return "tag_fluid"
    elseif lower:find("entity") then return "tag_entity"
    else                             return "tag" end
  end
  if lower:find("item")    then return "item"   end
  if lower:find("block")   then return "block"  end
  if lower:find("fluid")   then return "fluid"  end
  if lower:find("entity")  then return "entity" end
  if lower:find("enchant") then return "enchantment" end
  if lower:find("effect")  then return "effect" end
  if lower:find("biome")   then return "biome"  end
  if lower:find("dimension") or lower:find("level") then return "dimension" end
  return nil
end

local function detect_event_block_start(line)
  local ns = line:match("namespace%s+([%w_]+Events)%s*{")
    or line:match("declare%s+const%s+([%w_]+Events)%s*:%s*{")
    or line:match("interface%s+([%w_]+Events)[%w_]*%s*{")
  if ns then return category_from_ns(ns), ns end
  return nil, nil
end

local SKIP_METHOD_NAMES = {
  ["function"] = true, ["declare"] = true, ["export"] = true,
  ["interface"] = true, ["type"] = true, ["const"] = true,
  ["let"] = true, ["var"] = true, ["return"] = true, ["if"] = true,
}

local function read_all(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then return "" end
  local stat = vim.uv.fs_fstat(fd)
  local data = (stat and stat.size > 0) and vim.uv.fs_read(fd, stat.size, 0) or ""
  vim.uv.fs_close(fd)
  return data or ""
end

local function add_set(t, key, value)
  local bucket = t[key]
  if not bucket then bucket = {}; t[key] = bucket end
  bucket[value] = true
end

local function commit_alias(registry, name, body)
  local kind = classify_id(name)
  if not kind then return end
  local is_tag = (kind == "tag" or kind:sub(1, 4) == "tag_")
  for s in body:gmatch('"([^"]+)"') do
    if is_tag or s:find(":", 1, true) then
      add_set(registry.ids, kind, s)
    end
  end
end

local function parse_file(path, registry)
  local data = read_all(path)
  if data == "" then return end

  local accum, accum_name = nil, nil
  local in_block, depth = nil, 0

  for line in data:gmatch("[^\r\n]+") do
    if not accum then
      local tname = line:match("^%s*type%s+([%w_]+)%s*=")
      if tname then
        accum_name = tname
        accum = line
      end
    else
      accum = accum .. " " .. line
    end
    if accum and line:find(";", 1, true) then
      commit_alias(registry, accum_name, accum)
      accum, accum_name = nil, nil
    end

    if in_block then
      for _ in line:gmatch("{") do depth = depth + 1 end
      for _ in line:gmatch("}") do depth = depth - 1 end
      local method = line:match("^%s*function%s+([%w_]+)")
        or line:match("^%s*([%w_]+)%s*[<(]")
      if method and not SKIP_METHOD_NAMES[method] then
        add_set(registry.events, in_block, method)
      end
      if depth <= 0 then
        in_block, depth = nil, 0
      end
    else
      local category, ns = detect_event_block_start(line)
      if category then
        in_block = category
        registry.event_ns[category] = ns
        depth = 0
        for _ in line:gmatch("{") do depth = depth + 1 end
        for _ in line:gmatch("}") do depth = depth - 1 end
        if depth <= 0 then in_block, depth = nil, 0 end
      end
    end
  end
end

local function finalize(registry)
  local function setmap_to_sorted(t)
    local out = {}
    for k, set in pairs(t) do
      local arr = {}
      for s in pairs(set) do arr[#arr + 1] = s end
      table.sort(arr)
      out[k] = arr
    end
    return out
  end
  local events = {}
  for cat, set in pairs(registry.events) do
    local names = {}
    for s in pairs(set) do names[#names + 1] = s end
    table.sort(names)
    events[cat] = { ns = registry.event_ns[cat] or cat, names = names }
  end
  return {
    ids    = setmap_to_sorted(registry.ids),
    events = events,
  }
end

function M.locate(root)
  local config = require("tessera.config").get()
  local dir = vim.fs.joinpath(root, config.probe_subdir)
  local stat = vim.uv.fs_stat(dir)
  if stat and stat.type == "directory" then return dir end
  return nil
end

local function is_dts(name)
  return name:sub(-5) == ".d.ts" or name:sub(-3) == ".ts"
end

local function walk(dir, visit)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return end
  while true do
    local name, type_ = vim.uv.fs_scandir_next(handle)
    if not name then break end
    local full = vim.fs.joinpath(dir, name)
    if type_ == "directory" then
      walk(full, visit)
    elseif type_ == "file" and is_dts(name) then
      visit(full)
    end
  end
end

function M.list_files(dir)
  local out = {}
  walk(dir, function(p) out[#out + 1] = p end)
  return out
end

function M.parse(dir)
  local registry = { ids = {}, events = {}, event_ns = {} }
  walk(dir, function(path) parse_file(path, registry) end)
  return finalize(registry)
end

function M.newest_mtime(dir)
  local newest = 0
  walk(dir, function(path)
    local stat = vim.uv.fs_stat(path)
    if stat and stat.mtime and stat.mtime.sec > newest then
      newest = stat.mtime.sec
    end
  end)
  return newest
end

function M.watch(dir, on_change)
  local handle = vim.uv.new_fs_event()
  if not handle then return function() end end
  local timer = vim.uv.new_timer()
  local scheduled = false
  handle:start(dir, { recursive = true }, function(err)
    if err or scheduled then return end
    scheduled = true
    timer:start(500, 0, vim.schedule_wrap(function()
      scheduled = false
      on_change()
    end))
  end)
  return function()
    if handle and not handle:is_closing() then handle:stop(); handle:close() end
    if timer and not timer:is_closing() then timer:stop(); timer:close() end
  end
end

return M
