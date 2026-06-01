local M = {}

local mem_cache = {}
local watchers = {}

local function cache_path(root)
  local config = require("tessera.config").get()
  local hash = vim.fn.sha256(root):sub(1, 16)
  vim.fn.mkdir(config.cache_dir, "p")
  return vim.fs.joinpath(config.cache_dir, hash .. ".json")
end

local function read_file(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then return nil end
  local stat = vim.uv.fs_fstat(fd)
  local data = (stat and stat.size > 0) and vim.uv.fs_read(fd, stat.size, 0) or nil
  vim.uv.fs_close(fd)
  return data
end

local function write_file(path, content)
  local fd = vim.uv.fs_open(path, "w", 420)
  if not fd then return end
  vim.uv.fs_write(fd, content, 0)
  vim.uv.fs_close(fd)
end

local function file_mtime(path)
  local stat = vim.uv.fs_stat(path)
  return (stat and stat.mtime and stat.mtime.sec) or 0
end

local function load_disk(path)
  local data = read_file(path)
  if not data or data == "" then return nil end
  local ok, decoded = pcall(vim.json.decode, data)
  return ok and decoded or nil
end

local function save_disk(path, registry)
  write_file(path, vim.json.encode(registry))
end

local function ensure_watcher(root, dir)
  if watchers[root] then return end
  local probe = require("tessera.probe")
  watchers[root] = probe.watch(dir, function()
    M.invalidate(root)
  end)
end

local function is_empty(registry)
  return not registry or (vim.tbl_isempty(registry.ids or {}) and vim.tbl_isempty(registry.events or {}))
end

function M.get(root)
  if mem_cache[root] then return mem_cache[root] end

  local probe = require("tessera.probe")
  local dir = probe.locate(root)
  if not dir then
    mem_cache[root] = { ids = {}, events = {} }
    return mem_cache[root]
  end

  local cpath = cache_path(root)
  local newest = probe.newest_mtime(dir)
  local cached_mtime = file_mtime(cpath)

  local registry
  if cached_mtime >= newest and cached_mtime > 0 then
    registry = load_disk(cpath)
    if is_empty(registry) then registry = nil end
  end
  if not registry then
    registry = probe.parse(dir)
    if not is_empty(registry) then save_disk(cpath, registry) end
  end

  mem_cache[root] = registry
  ensure_watcher(root, dir)
  return registry
end

function M.invalidate(root)
  mem_cache[root] = nil
end

function M.rebuild(root)
  local probe = require("tessera.probe")
  local dir = probe.locate(root)
  if not dir then
    mem_cache[root] = { ids = {}, events = {} }
    return mem_cache[root]
  end
  local registry = probe.parse(dir)
  save_disk(cache_path(root), registry)
  mem_cache[root] = registry
  ensure_watcher(root, dir)
  return registry
end

return M
