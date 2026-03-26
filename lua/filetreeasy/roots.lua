local M = {}
local _roots = {}

local function norm(p)
  return vim.fn.fnamemodify(p, ":p"):gsub("/$", "")
end

function M.add(path)
  path = norm(path)
  for _, r in ipairs(_roots) do
    if r == path then return end
  end
  table.insert(_roots, path)
end

function M.remove(path)
  path = norm(path)
  for i, r in ipairs(_roots) do
    if r == path then table.remove(_roots, i); return end
  end
end

function M.get()
  return vim.deepcopy(_roots)
end

-- Returns the deepest root that is an ancestor of (or equal to) path.
function M.find_best(path)
  path = norm(path)
  local best, blen = nil, 0
  for _, r in ipairs(_roots) do
    if (path == r or path:sub(1, #r + 1) == r .. "/") and #r > blen then
      best, blen = r, #r
    end
  end
  return best
end

return M
