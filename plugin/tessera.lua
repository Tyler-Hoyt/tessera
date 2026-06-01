if vim.g.loaded_tessera == 1 then
  return
end
vim.g.loaded_tessera = 1

vim.api.nvim_create_user_command("Tessera", function(opts)
  require("tessera.commands").dispatch(opts)
end, {
  nargs = "*",
  complete = function(arglead, cmdline, cursorpos)
    return require("tessera.commands").complete(arglead, cmdline, cursorpos)
  end,
  desc = "Tessera: KubeJS development tools",
})

local group = vim.api.nvim_create_augroup("Tessera", { clear = true })
vim.api.nvim_create_autocmd("BufDelete", {
  group = group,
  callback = function(args)
    local ok, project = pcall(require, "tessera.project")
    if ok then project.forget(args.buf) end
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    local ok, logs = pcall(require, "tessera.logs")
    if ok then
      for _, root in ipairs(logs._roots and logs._roots() or {}) do
        logs.unwatch(root)
      end
    end
  end,
})
