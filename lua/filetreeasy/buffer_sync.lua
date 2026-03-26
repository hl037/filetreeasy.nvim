local M = {}

local function is_edit_win(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local bt = vim.bo[buf].buftype
  return bt == "" or bt == "acwrite"
end

local function update_node_for_path(path, fte)
  if not path or path == "" then return end
  local node = fte.node_index[path]
  if node then require("treeasy").tree.update_node(node) end
end

function M.setup()
  local aug = vim.api.nvim_create_augroup("filetreeasy_sync", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group    = aug,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if not is_edit_win(win) then return end
      local buf = vim.api.nvim_get_current_buf()

      require("filetreeasy.views").each(function(view)
        local fte  = view._filetreeasy
        local prev = fte.current_buf
        fte.last_win    = win
        fte.current_buf = buf
        local prev_path = prev and vim.api.nvim_buf_get_name(prev) or nil
        local cur_path  = vim.api.nvim_buf_get_name(buf)
        vim.schedule(function()
          update_node_for_path(prev_path, fte)
          update_node_for_path(cur_path, fte)
        end)
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWritePost", "BufModifiedSet" }, {
    group    = aug,
    callback = function()
      local path = vim.fn.expand("<afile>:p")
      require("filetreeasy.views").each(function(view)
        vim.schedule(function() update_node_for_path(path, view._filetreeasy) end)
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group    = aug,
    callback = function()
      local buf  = tonumber(vim.fn.expand("<abuf>"))
      local path = buf and vim.api.nvim_buf_get_name(buf) or ""
      require("filetreeasy.views").each(function(view)
        vim.schedule(function() update_node_for_path(path, view._filetreeasy) end)
      end)
    end,
  })
end

return M
