-- autocmds.lua — all core autocommands for filetreeasy.
--
-- BufEnter      update current_buf, refresh highlights, reveal, collapse alts
-- BufWritePost  refresh modified indicator
-- BufModifiedSet refresh modified indicator
-- BufAdd        increment root buf_count
-- BufDelete     decrement root buf_count, auto-close empty alt roots
-- BufWipeout    same as BufDelete

local M = {}

local function is_under(path, root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function collapse_other_alts(cur_path, view)
  local builder = require("filetreeasy.tree_builder")
  for _, rg in ipairs(builder.get_root_nodes(view)) do
    if rg.is_alt and not is_under(cur_path, rg.path) then
      view:set_open(rg, false)
    end
  end
end

local function is_edit_win(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local bt = vim.bo[buf].buftype
  return bt == "" or bt == "acwrite"
end

local function update_node_for_path(path, view)
  if not path or path == "" then return end
  local nf   = require("filetreeasy.node_factory")
  local node = nf.find_loaded_node(view, path)
  if node then require("treeasy").tree.update_node(node) end
end

-- Find the root_ghost that best contains path (longest prefix match).
local function find_root_ghost(path, view)
  local builder = require("filetreeasy.tree_builder")
  local best, blen = nil, 0
  for _, rg in ipairs(builder.get_root_nodes(view)) do
    local r = rg.path or ""
    if (path == r or path:sub(1, #r + 1) == r .. "/") and #r > blen then
      best, blen = rg, #r
    end
  end
  return best
end

local function inc_buf_count(path, view)
  local rg = find_root_ghost(path, view)
  if rg then rg.buf_count = (rg.buf_count or 0) + 1 end
end

local function dec_buf_count(path, view)
  local rg = find_root_ghost(path, view)
  if not rg then return end
  rg.buf_count = math.max(0, (rg.buf_count or 0) - 1)
  if rg.buf_count == 0 and rg.deletable
  and view._filetreeasy.auto_close_empty_roots then
    require("filetreeasy.roots").remove(rg.path)
    require("filetreeasy").reload()
  end
end

function M.setup()
  local aug = vim.api.nvim_create_augroup("filetreeasy_sync", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group    = aug,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if not is_edit_win(win) then return end
      local buf = vim.api.nvim_get_current_buf()

      require("filetreeasy.views").each(function(view)
        local fte  = view._filetreeasy
        local prev = fte.current_buf
        
        fte.current_buf = buf
        local prev_path = prev and vim.api.nvim_buf_get_name(prev) or nil
        local cur_path  = vim.api.nvim_buf_get_name(buf)
        vim.schedule(function()
          update_node_for_path(prev_path, view)
          update_node_for_path(cur_path, view)
          if fte.buffer_sync and cur_path ~= "" then
            require("filetreeasy.navigation").reveal(cur_path, view)
          end
          if fte.collapse_alt_on_switch and cur_path ~= "" then
            collapse_other_alts(cur_path, view)
          end
        end)
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWritePost", "BufModifiedSet" }, {
    group    = aug,
    callback = function()
      local path = vim.fn.expand("<afile>:p")
      require("filetreeasy.views").each(function(view)
        vim.schedule(function() update_node_for_path(path, view) end)
      end)
    end,
  })

  -- Track buf_count: increment when a new buffer is loaded.
  vim.api.nvim_create_autocmd("BufAdd", {
    group    = aug,
    callback = function()
      local path = vim.fn.expand("<afile>:p")
      if path == "" then return end
      require("filetreeasy.views").each(function(view)
        inc_buf_count(path, view)
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group    = aug,
    callback = function()
      local buf  = tonumber(vim.fn.expand("<abuf>"))
      local path = buf and vim.api.nvim_buf_get_name(buf) or ""
      require("filetreeasy.views").each(function(view)
        if path ~= "" then dec_buf_count(path, view) end
        vim.schedule(function() update_node_for_path(path, view) end)
      end)
    end,
  })
end

return M
