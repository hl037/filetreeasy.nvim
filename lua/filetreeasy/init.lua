local M = {}

-- ── internals ─────────────────────────────────────────────────────────────────

local _views       = {}     -- roots_key -> view (one active view per root set)
local _initialized = false

local function is_view_alive(view)
  return view and view.window and vim.api.nvim_win_is_valid(view.window)
end

local function build_and_open(roots_list, fte)
  local builder = require("filetreeasy.tree_builder")
  local tree    = builder.build(roots_list, fte)
  local view    = builder.open_window(tree, fte)
  builder.expand_roots(tree, view)
  return tree, view
end

-- ── setup ─────────────────────────────────────────────────────────────────────

function M.setup(opts)
  require("filetreeasy.config").setup(opts)
  require("filetreeasy.buffer_sync").setup()

  vim.api.nvim_create_user_command("FileTreeOpen",   function() M.open()   end, {})
  vim.api.nvim_create_user_command("FileTreeClose",  function() M.close()  end, {})
  vim.api.nvim_create_user_command("FileTreeToggle", function() M.toggle() end, {})
  vim.api.nvim_create_user_command("FileTreeFocus",  function() M.focus()  end, {})
  vim.api.nvim_create_user_command("FileTreeReveal", function() M.reveal() end, {})

  vim.api.nvim_create_user_command("FileTreeRootAdd", function(a)
    M.roots().add(a.args ~= "" and a.args or vim.fn.getcwd())
    M.reload()
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("FileTreeRootRemove", function(a)
    M.roots().remove(a.args ~= "" and a.args or vim.fn.getcwd())
    M.reload()
  end, { nargs = "?" })
end

-- ── open / close / toggle / focus ────────────────────────────────────────────

-- opts: optional per-call overrides merged on top of global config.
function M.open(opts)
  local cfg  = require("filetreeasy.config")
  local fte  = cfg.make_fte(opts)

  local roots = require("filetreeasy.roots")
  if not _initialized then
    _initialized = true
    roots.add(vim.fn.getcwd())
  end
  local roots_list = roots.get()
  if #roots_list == 0 then roots.add(vim.fn.getcwd()); roots_list = roots.get() end

  -- Reuse existing view if alive.
  local key = table.concat(roots_list, "|")
  if _views[key] and is_view_alive(_views[key]) then
    vim.api.nvim_set_current_win(_views[key].window)
    return
  end

  local prev_win = vim.api.nvim_get_current_win()
  local _, view  = build_and_open(roots_list, fte)
  _views[key]    = view

  if vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
end

function M.close()
  require("filetreeasy.views").each(function(view)
    pcall(vim.api.nvim_win_close, view.window, false)
    require("filetreeasy.views").unregister(view)
  end)
end

function M.toggle(opts)
  local alive = false
  require("filetreeasy.views").each(function() alive = true end)
  if alive then M.close() else M.open(opts) end
end

function M.focus()
  local found = false
  require("filetreeasy.views").each(function(view)
    if not found then
      vim.api.nvim_set_current_win(view.window)
      found = true
    end
  end)
  if not found then M.open() end
end

function M.reveal(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if path == "" then return end
  local alive = false
  require("filetreeasy.views").each(function(view)
    if not alive then
      alive = true
      require("filetreeasy.navigation").reveal(path, view)
    end
  end)
  if not alive then M.open(); M.reveal(path) end
end

-- ── roots ─────────────────────────────────────────────────────────────────────

function M.roots()
  return require("filetreeasy.roots")
end

function M.reload()
  local cfg        = require("filetreeasy.config")
  local roots_list = require("filetreeasy.roots").get()
  local builder    = require("filetreeasy.tree_builder")

  require("filetreeasy.views").each(function(view)
    local fte  = view._filetreeasy
    local tree = builder.build(roots_list, fte)
    view:set_root(tree.root)
    builder.expand_roots(tree, view)
    for _, fn in ipairs(fte.hooks.root_change) do fn() end
  end)
end

return M
