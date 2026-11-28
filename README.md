# packview.nvim

A floating list of the plugins `vim.pack` installed. It reads plugin state and applies changes through `vim.pack`; it never clones, checks out, or writes the lockfile itself.

Neovim 0.12 or newer.

## Install

`vim.pack`:

```lua
vim.pack.add({ "https://github.com/you/packview.nvim" })
```

lazy.nvim:

```lua
{ "you/packview.nvim", cmd = "Packview" }
```

## Use

`:Packview` opens the list.

| Key | Action |
|---|---|
| `<Space>` | Mark the row |
| `u` | Update marked rows, or the row under the cursor |
| `U` | Update every row that has new commits |
| `r` | Fetch and check for updates |
| `x` | Delete marked rows, after confirmation |
| `<CR>` | Open the source, or the compare page when it is behind |
| `q` | Close |

`<leader>ps` opens the list and `<leader>pU` updates every plugin. Both are set when the plugin loads.

`u` and `U` call `vim.pack.update(names, { force = true })`. `d` calls `vim.pack.del`.

## Load reasons

`vim.pack` only knows whether it added a plugin. A loader can add why it loaded:

```lua
require("packview").setup({
  provider = function()
    return {
      { name = "snacks.nvim", loaded = true, why = "start", needs = { "plenary" } },
    }
  end,
})
```

Each row is `{ name, loaded, why, needs }`. `name` is the directory name `vim.pack` uses. Rows for plugins that are not installed are ignored.

## Layout

```
lua/packview/init.lua     setup() and open()
lua/packview/state.lua    read vim.pack.get() and the provider
lua/packview/git.lua      fetch and compare, read only
lua/packview/view.lua     the floating window
lua/packview/actions.lua  update and delete through vim.pack
lua/packview/keys.lua     buffer keys
plugin/packview.lua       the :Packview command
```
