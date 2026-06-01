local M = {}

local defaults = {
  root_markers = { 
    "server_scripts", 
    "client_scripts", 
    "startup_scripts" 
  },
  probe_subdir = ".probe",
  script_subdirs = {
    server  = "kubejs/server_scripts",
    client  = "kubejs/client_scripts",
    startup = "kubejs/startup_scripts",
  },
  data_subdir   = "kubejs/data",
  assets_subdir = "kubejs/assets",
  datapack_dir     = "datapacks",
  resourcepack_dir = "resourcepacks",
  auto_loader = nil,  -- "paxi" | "openloader" | nil
  auto_loader_paths = {
    paxi = {
      datapacks     = "paxi/datapacks",
      resourcepacks = "paxi/resourcepacks",
    },
    openloader = {
      datapacks     = "openloader/data",
      resourcepacks = "openloader/resources",
    },
  },
  pickers = {
    quote_style    = "auto",
    scripts_prefix = true,
  },
  cache_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "tessera"),
  log_files = {
    server  = "logs/kubejs/server.log",
    client  = "logs/kubejs/client.log",
    startup = "logs/kubejs/startup.log",
    latest  = "logs/latest.log",
  },
}

local current = vim.deepcopy(defaults)

function M.apply(opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.get()
  return current
end

return M
