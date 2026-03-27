# filetreeasy.nvim

File tree plugin built on [treeasy.nvim](https://github.com/hl037/treeasy.nvim).

## Requirements

- treeasy.nvim
- (optional) nvim-web-devicons

## Installation


Using [lazy.nvim](https://github.com/folke/lazy.nvim):
```lua
{
  "hl037/filetreeasy.nvim",
  dependencies = {
    "hl037/treeasy.nvim",
    { "nvim-tree/nvim-web-devicons", optional = true },
  },
  config = function()
    require("filetreeasy").setup()
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use {
  "hl037/filetreeasy.nvim",
  requires = {
    "hl037/treeasy.nvim",
    { "nvim-tree/nvim-web-devicons", opt = true },
  },
  config = function()
    require("filetreeasy").setup()
  end,
}
```

Using [vim-plug](https://github.com/junegunn/vim-plug):
```vim
Plug 'hl037/treeasy.nvim'
Plug 'hl037/filetreeasy.nvim'
" optional:
Plug 'nvim-tree/nvim-web-devicons'
```
Then in your `init.lua`:
```lua
require("filetreeasy").setup()
```


## Setup

`setup()` must be called explicitly — it registers all commands and installs autocmds. All options are optional.

```lua
-- Minimal: use all defaults
require("filetreeasy").setup()

-- Full example
require("filetreeasy").setup({
  width    = 12,
  side     = "left",    -- "left" | "right"
  devicons = false,     -- opt-in: requires nvim-web-devicons
  icons    = {
    dir_open   = "▾ ",
    dir_closed = "▸ ",
    file       = "",
    modified   = "●",
  },

  buffer_sync            = true,   -- auto-reveal current file in tree on BufEnter
  auto_close_empty_roots = false,  -- remove alt roots when all their buffers close
  collapse_alt_on_switch = false,  -- collapse alt roots when switching to another root

  plugins = {
    require("filetreeasy.plugins.git"),
    require("filetreeasy.plugins.pick_win"),
  },
})
```

## Commands

| Command | Description |
|---|---|
| `FileTreeOpen` | Open the tree |
| `FileTreeClose` | Close the tree |
| `FileTreeToggle` | Toggle the tree |
| `FileTreeFocus` | Focus the tree window |
| `FileTreeReveal` | Reveal current file in tree |
| `FileTreeRootAdd [path]` | Add a root (default: cwd) |
| `FileTreeRootRemove [path]` | Remove a root (default: cwd) |

## Keymaps (inside the tree)

| Key | Action |
|---|---|
| `<CR>` | Toggle expand / open file |
| `<LeftRelease>` | Click |
| `<S-CR>` | Expand/collapse recursively |
| `m` | FS operations menu |

All keymaps can be overridden before `setup()` via `treeasy.set_keymap("filetreeasy", {...})`.

## Tree structure

```
FileTreeasy.nvim          ← plugin header
/path/to/project          ← main root (non-deletable)
  src/
    main.lua
/other/path               ← alt root (added by reveal or FileTreeRootAdd)
  [X] /other/path         ← [X] button closes root + its buffers
  file.lua
```

The main root is set on first open (cwd). When navigating to a file outside all known roots, the file's parent directory is added as an **alt root** (collapsible, with `[X]` to close). Alt roots are also added from the global root registry if a match is found there.

## FS Operations (`m`)

Popup menu with single-key shortcuts — no Enter needed:

| Key | Action |
|---|---|
| `a` | Add file or dir (trailing `/` = dir) |
| `m` | Move / rename |
| `d` | Delete (with confirmation) |
| `c` | Copy |
| `t` | Link to (`ln -s this link_location`) |
| `f` | Link from (`ln -s target here`) |
| `q` / `Esc` | Close menu |

All path inputs show the full path and support file completion.

## Symlinks

Displayed in italic with their target: `name -> /path/to/target`. Followed transparently for directory traversal.

## Pick window (`[♠]`)

Each file has a `[♠]` button. Click it to arm pick-window mode — button becomes `[[♠]]`. Then click any edit window to open the file there. Click again or interact with any other node to cancel.

## Git plugin (`filetreeasy.plugins.git`)

Enabled by default. Uses `git status --porcelain` directly — no dependencies.

| Status | Icon | Color |
|---|---|---|
| staged | ● | green |
| modified | ✚ | yellow |
| deleted | ✖ | red |
| renamed | ➜ | purple |
| untracked | ? | cyan |
| ignored | ◌ | gray |
| conflict | ═ | red + underline on filename |

## Roots API

```lua
local ft = require("filetreeasy")
ft.roots().add("/some/path")
ft.roots().remove("/some/path")
ft.roots().get()     -- list of global roots
ft.reload()          -- rebuild all views
```

## Plugin system

Each plugin exposes only `init(view)`:

```lua
function MyPlugin.init(view)
  local fte = view._filetreeasy

  -- Default highlight groups (only set if user hasn't pre-configured them).
  -- Register via treeasy.set_colors("filetreeasy", {...}) if treeasy.get_colors() == nil.

  -- Private state.
  fte.my_plugin = { ... }

  -- Label pipeline (left to right, each fn(node, label, view) -> label).
  table.insert(fte.label_fns, function(node, label, view) ... end)

  -- Treeasy event handlers (return true to stop propagation).
  local ph = fte.plugin_handlers
  if not ph.click then ph.click = {} end
  table.insert(ph.click, function(node, view, ctx) ... end)

  -- Filetreeasy hooks.
  table.insert(fte.hooks.fs_change,    function(dir_path) ... end)
  table.insert(fte.hooks.root_change,  function() ... end)
end

MyPlugin.default_colors = {
  my_color = { fg = "#..." },
}
```

`default_colors` is merged at class setup time (before first open), only if `treeasy.get_colors("filetreeasy") == nil`.
