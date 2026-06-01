# tessera.nvim

Neovim integration for [KubeJS](https://kubejs.com) modpack development.

Tessera detects KubeJS modpack roots, gives you `fzf-lua` pickers for the three
script folders (`server_scripts`, `client_scripts`, `startup_scripts`), for
datapacks and resourcepacks, and parses [ProbeJS](https://github.com/Prunoideae/ProbeJS)
dumps to power pickers over registry IDs and event names.

## Requirements

- Neovim 0.10+
- [`fzf-lua`](https://github.com/ibhagwan/fzf-lua)
- A KubeJS modpack with ProbeJS installed; run `/probejs dump` in-game once so
  declarations land in `<modpack>/.probe/`.

## Install

With `lazy.nvim`:

```lua
{
  "your-handle/tessera.nvim",
  dependencies = { "ibhagwan/fzf-lua" },
  cmd = "Tessera",
  config = function() require("tessera").setup{} end,
}
```

## Commands

| Command | What it does |
|---|---|
| `:Tessera scripts [server\|client\|startup]` | Picker over script files. Omit scope for all three. |
| `:Tessera datapacks` | Picker over namespaces under `kubejs/data/` and any `datapacks/*`. |
| `:Tessera resourcepacks` | Picker over namespaces under `kubejs/assets/` and any `resourcepacks/*`. |
| `:Tessera ids [item\|block\|fluid\|entity\|tag\|...]` | Picker over registry IDs. Inserts the selected ID, quoted, at cursor. |
| `:Tessera events [server\|item\|block\|...]` | Picker over event names. Scaffolds a listener stub at cursor. |
| `:Tessera probe refresh` | Force a re-parse of `.probe/` and rewrite the disk cache. |
| `:Tessera errors [all\|server\|client\|startup\|latest]` | Scan KubeJS log files for errors, populate quickfix with script-line refs, jump to first. |
| `:Tessera errors watch` | Toggle a live watcher on the log files; new errors append to quickfix and notify. |
| `:Tessera root` | Print the detected modpack root (debug aid). |

## Configuration

```lua
require("tessera").setup({
  root_markers = { 
      "server_scripts", 
      "client_scripts", 
      "startup_scripts",
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
  -- Optional: also surface packs from a global auto-loader mod.
  -- Set to "paxi" or "openloader" (or leave nil to skip).
  auto_loader = nil,
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
    quote_style    = "auto",  -- "auto" | "single" | "double"
    scripts_prefix = true,    -- show [S]/[C]/[U] in combined scripts picker
  },
  cache_dir = vim.fn.stdpath("cache") .. "/tessera",
  log_files = {
    server  = "logs/kubejs/server.log",
    client  = "logs/kubejs/client.log",
    startup = "logs/kubejs/startup.log",
    latest  = "logs/latest.log",
  },
})
```

## How root detection works

From the current buffer's directory, Tessera walks upward looking for a
`kubejs/` folder whose immediate children include any of the `root_markers`.
If the current buffer is itself inside `kubejs/`, that's also recognised. The
parent of `kubejs/` is the modpack root; everything else is resolved relative
to it.

## ProbeJS parsing

Tessera reads every `.d.ts` under `.probe/` (at the modpack root) and extracts:

- Registry-ID type-alias unions (`type ItemIDs = "minecraft:diamond" | ...;`)
  bucketed by name into `item`, `block`, `fluid`, `entity`, `tag_*`, etc.
- Event method names inside `ServerEvents`, `ItemEvents`, etc. blocks.

The parsed result is cached at `stdpath('cache')/tessera/<hash>.json` and
invalidated when any `.d.ts` is newer than the cache file, or via the fs
watcher that runs while Neovim is open.

## Status

Early. Folder/pack pickers and ID/event pickers work. Live script reload via
sentinel file, scaffolding commands, and lang-file linting are planned but
not implemented.
