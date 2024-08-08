--- Custom requests implemented by cortex-debug.
--- See gdb.ts (GDBDebugSession.customRequest) and frontend.extensions.ts.
local M = {}

local utils = require('dap-cortex-debug.utils')

--- FIXME: does not work? try to understand how to use it, or can we just use dap.pause?
---@param session? dap.Session
---@param callback? fun(err: table, result: any)
function M.reset_device(session, callback)
    local dap = require('dap')
    session = assert(session or dap.session(), 'No DAP session')
    session:request('reset-device', 'reset', function(err, result)
        if err then
            utils.error('Could not reset device: %s', vim.inspect(result))
        else
            utils.debug('Reset device: %s', vim.inspect(result))
        end
    end)
end

---@param session? dap.Session
---@param format { hex: boolean }
function M.set_var_format(session, format)
    local dap = require('dap')
    session = assert(session or dap.session(), 'No DAP session')
    session:request('set-var-format', format, function(err, result)
        if err then
            utils.error('Could not set var format: %s', result)
        end
    end)
end

return M
