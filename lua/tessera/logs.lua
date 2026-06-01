local M = {}

local SCRIPT_REF = "([%w_]+_scripts/[%w_/%-%.]+%.js)[:#](%d+)"

local function read_all(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then return "" end
  local stat = vim.uv.fs_fstat(fd)
  local data = (stat and stat.size > 0) and vim.uv.fs_read(fd, stat.size, 0) or ""
  vim.uv.fs_close(fd)
  return data or ""
end

local function read_tail(path, from_offset)
  local stat = vim.uv.fs_stat(path)
  if not stat then return "", from_offset end
  if stat.size <= from_offset then return "", stat.size end
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then return "", stat.size end
  local data = vim.uv.fs_read(fd, stat.size - from_offset, from_offset) or ""
  vim.uv.fs_close(fd)
  return data, stat.size
end

local function is_error_header(line)
  return line:find("/ERROR%]") ~= nil
    or line:find("/WARN%]") ~= nil
    or line:find("Error:", 1, true) ~= nil
    or line:find("Exception", 1, true) ~= nil
end

local function is_info_line(line)
  return line:find("/INFO%]") ~= nil
end

local function extract_message(line)
  local msg = line:match("%]:%s*(.+)$")
    or line:match("Error:%s*(.+)$")
    or line:match("Exception[^:]*:%s*(.+)$")
    or line
  return (msg:gsub("^%s+", ""):gsub("%s+$", ""))
end

local SCOPE_ORDER = { "server", "client", "startup", "latest" }

local function parse_chunk(chunk, root, into)
  local current_msg, current_type = nil, nil
  for line in chunk:gmatch("[^\r\n]+") do
    if is_error_header(line) then
      current_msg = extract_message(line)
      current_type = line:find("/WARN%]") and "W" or "E"
    elseif is_info_line(line) then
      current_msg, current_type = nil, nil
    end

    for relpath, lnum in line:gmatch(SCRIPT_REF) do
      into[#into + 1] = {
        filename = vim.fs.joinpath(root, "kubejs", relpath),
        lnum = tonumber(lnum),
        col = 1,
        text = current_msg or extract_message(line),
        type = current_type or "E",
      }
    end
  end
end

function M.collect(root, scope)
  local config = require("tessera.config").get()
  local files = config.log_files or {}
  local order = (scope and scope ~= "all" and files[scope]) and { scope } or SCOPE_ORDER

  local entries = {}
  for _, key in ipairs(order) do
    local rel = files[key]
    if rel then
      local path = vim.fs.joinpath(root, rel)
      local data = read_all(path)
      if data ~= "" then parse_chunk(data, root, entries) end
    end
  end
  return entries
end

function M.populate_quickfix(entries, title)
  vim.fn.setqflist({}, "r", { title = title or "Tessera errors", items = entries })
  if #entries > 0 then
    vim.cmd("copen")
    vim.cmd("cfirst")
  end
end

local watchers = {}

local function on_new_chunk(root, path, chunk)
  local entries = {}
  parse_chunk(chunk, root, entries)
  if #entries == 0 then return end

  vim.fn.setqflist({}, "a", { title = "Tessera errors (watch)", items = entries })

  vim.notify(
    string.format("[Tessera] %d new error(s) in %s", #entries, vim.fs.basename(path)),
    vim.log.levels.WARN
  )
end

function M.watch(root)
  if watchers[root] then return watchers[root] end

  local config = require("tessera.config").get()
  local files = config.log_files or {}
  local handles, offsets = {}, {}

  for _, rel in pairs(files) do
    local path = vim.fs.joinpath(root, rel)
    local stat = vim.uv.fs_stat(path)
    offsets[path] = (stat and stat.size) or 0

    local handle = vim.uv.new_fs_event()
    if handle then
      local ok = pcall(function()
        handle:start(path, {}, vim.schedule_wrap(function(err)
          if err then return end
          local data, new_offset = read_tail(path, offsets[path])
          if new_offset < offsets[path] then
            data, new_offset = read_tail(path, 0)
          end
          offsets[path] = new_offset
          if data ~= "" then on_new_chunk(root, path, data) end
        end))
      end)
      if ok then handles[#handles + 1] = handle end
    end
  end

  watchers[root] = {
    stop = function()
      for _, h in ipairs(handles) do
        if h and not h:is_closing() then h:stop(); h:close() end
      end
      watchers[root] = nil
    end,
  }
  return watchers[root]
end

function M.unwatch(root)
  local w = watchers[root]
  if w then w.stop() end
end

function M.is_watching(root)
  return watchers[root] ~= nil
end

function M._roots()
  return vim.tbl_keys(watchers)
end

return M
