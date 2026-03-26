local M = {}
local _handles = {} -- path -> uv fs_event handle

function M.watch(path, cb)
  if _handles[path] then return end
  local h = vim.loop.new_fs_event()
  if not h then return end
  h:start(path, {}, vim.schedule_wrap(function(err, fname, events)
    if not err then cb(path, fname, events) end
  end))
  _handles[path] = h
end

function M.unwatch(path)
  local h = _handles[path]
  if h then pcall(h.stop, h); _handles[path] = nil end
end

function M.unwatch_all()
  for _, h in pairs(_handles) do pcall(h.stop, h) end
  _handles = {}
end

return M
