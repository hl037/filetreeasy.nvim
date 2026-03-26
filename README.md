# filetreeasy.nvim

File tree plugin built on [treeasy.nvim](https://github.com/yourname/treeasy.nvim).

## Requirements

- treeasy.nvim
- (optional) nvim-web-devicons

## Setup

`setup()` must be called explicitly — it registers all commands and installs autocmds. All options are optional.

```lua
-- Minimal: use all defaults
require("filetreeasy").setup()

-- Full example
require("filetreeasy").setup({
  width    = 12,
  side     = "left",   -- "left" | "right"
  devicons = false,    -- opt-in: requires nvim-web-devicons
  icons    = {
    dir_open   = "▾ ",
    dir_closed = "▸ ",
    file       = "",
    modified   = "●",
  },
  plugins  = {
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

All keymaps can be overridden before calling `setup()` via `treeasy.set_keymap("filetreeasy", {...})`.

## Roots

Roots are session-local. The cwd is added automatically on first open.

```lua
local ft = require("filetreeasy")
ft.roots().add("/some/path")
ft.roots().remove("/some/path")
ft.roots().get()   -- list of current roots
ft.reload()        -- rebuild tree after root change
```

## FS Operations (`m`)

- **add** — create file or directory (append `/` for dir); creates parent dirs
- **move** — rename (no `/` in input) or move to another path
- **delete** — delete with confirmation
- **copy** — copy to a destination path
- **link to** — `ln -s <this> <link_location>` (symlink elsewhere → this file)
- **link from** — `ln -s <target> <here>/<basename>` (symlink here → another file)

## Symlinks

Symlinks are displayed in italic with their target: `name -> /path/to/target`.

## Pick window (`[♠]`)

Each file shows a `[♠]` button. Click it to arm pick-window mode — the button becomes `[[♠]]`. Then click any edit window to open the file there. Click `[[♠]]` again or interact with any other tree node to cancel.

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

To disable: remove it from the `plugins` list.

## Plugin system

Each plugin in the `plugins` list may expose:

- `plugin.colors` — table of `name = hl_def` registered as defaults (not set if user pre-configured them)
- `plugin.make_label_plugin()` — returns `fn(node, label) -> label`; plugins are applied left to right
- `plugin.setup()` — called once at `setup()` time for autocmds etc.

Example custom plugin:

```lua
local my_plugin = {
  colors = { test_marker = { fg = "#bb9af7" } },
  make_label_plugin = function()
    return function(node, label)
      if node.name:match("%.test%.") then
        return label .. " <c:test_marker>[test]</c>"
      end
      return label
    end
  end,
}

require("filetreeasy").setup({
  plugins = {
    require("filetreeasy.plugins.git"),
    require("filetreeasy.plugins.pick_win"),
    my_plugin,
  },
})
```
