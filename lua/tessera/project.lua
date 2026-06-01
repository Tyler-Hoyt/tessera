local M = {}

local cache = {}

local function dir_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

local function is_kubejs_dir(path, markers)
  for _, marker in ipairs(markers) do
    if dir_exists(vim.fs.joinpath(path, marker)) then
      return true
    end
  end
  return false
end

local function search_upward(start)
  local config = require("tessera.config").get()
  local markers = config.root_markers
  local dir = start
  while dir and dir ~= "" do
    local candidate = vim.fs.joinpath(dir, "kubejs")
    if dir_exists(candidate) and is_kubejs_dir(candidate, markers) then
      return { root = dir, kubejs = candidate }
    end
    if is_kubejs_dir(dir, markers) then
      return { root = vim.fs.dirname(dir), kubejs = dir }
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then return nil end
    dir = parent
  end
  return nil
end

function M.find_root(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if cache[bufnr] ~= nil then
    return cache[bufnr] or nil
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local start = (name ~= "" and vim.fs.dirname(name)) or vim.fn.getcwd()
  local found = search_upward(start)
  cache[bufnr] = found or false
  return found
end

function M.forget(bufnr)
  cache[bufnr] = nil
end

function M.clear()
  cache = {}
end

return M
