local M = {}

M.defaults = {
  width    = 12,
  side     = "left",
  icons    = {
    dir_open   = "▾ ",
    dir_closed = "▸ ",
    file       = "",
    modified   = "●",
  },
  devicons = false,
  plugins  = {
    require("filetreeasy.plugins.git"),
    require("filetreeasy.plugins.pick_win"),
  },
}

M.global = nil

function M.setup(opts)
  M.global = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if opts and opts.plugins ~= nil then M.global.plugins = opts.plugins end
end

-- Create a per-view filetreeasy config object.
-- Plugins populate the documented slots in their init(view).
--
-- Documented slots (plugins write here in init):
--   fte.label_fns        []   fn(node, label, view) -> label  (appended in order)
--   fte.plugin_handlers  {}   event -> list of fn(node, view, ctx) -> true|nil
--   fte.hooks.fs_change  []   fn(dir_path)  called when a watched dir changes
--   fte.hooks.root_change[]   fn()          called when the root list changes
--
-- Runtime state (managed by core, read by plugins):
--   fte.node_index       {}   path -> node
--   fte.current_buf      nil  currently focused edit buffer
--   fte.last_win         nil  last focused edit window
function M.make_fte(overrides)
  local base = M.global or vim.deepcopy(M.defaults)
  local fte  = vim.tbl_deep_extend("force", vim.deepcopy(base), overrides or {})
  if overrides and overrides.plugins ~= nil then fte.plugins = overrides.plugins end

  fte.label_fns       = {}
  fte.plugin_handlers = {}
  fte.hooks           = { fs_change = {}, root_change = {} }
  fte.node_index      = {}
  fte.current_buf     = nil
  fte.last_win        = nil

  return fte
end

return M
