---Uri scheme for plugin buffers
local M = {}

---@alias CortexDebugUri string

M.scheme = 'cortex-debug'

function M.create(session_id, tail)
    return string.format('%s://%d/%s', M.scheme, session_id, tail)
end

function M.parse(_uri)
    assert(false, 'Not implemented')
end

return M
