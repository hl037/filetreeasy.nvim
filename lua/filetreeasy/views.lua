-- Registry of active filetreeasy views (each has view._filetreeasy).
local M = {}
local _list = {}

function M.register(view)
  _list[#_list + 1] = view
end

function M.unregister(view)
  for i, v in ipairs(_list) do
    if v == view then table.remove(_list, i); return end
  end
end

-- Iterate live views, pruning dead ones in-place.
function M.each(fn)
  local live = {}
  for _, v in ipairs(_list) do
    if v.window and vim.api.nvim_win_is_valid(v.window) then
      live[#live + 1] = v
      fn(v)
    end
  end
  _list = live
end

return M
