local M = {}

local dap = require('dap')
local rtt = require('dap-cortex-debug.rtt')
local utils = require('dap-cortex-debug.utils')

local PLUGIN = 'cortex-debug'
M.debug = true

local function set_event_handler(when, event, handler)
    handler = handler or function() end

    local event_name = 'event_' .. event
    local log_handler = function(_session, body)
        if debug then
            vim.notify('cortex-debug:' .. event_name .. ' : ' .. vim.inspect(body), vim.log.levels.DEBUG)
        end
    end

    dap.listeners[when][event_name][PLUGIN] = function(...)
        log_handler(...)
        return handler(...)
    end
end

local before = utils.bind(set_event_handler, 'before')
local after = utils.bind(set_event_handler, 'after')

-- Create handlers for cortex-debug custom events
function M.setup()
    after('capabilities', function(session, body) end, 'after')

    before('custom-event-ports-allocated', function(session, body)
        local ports = body and body.info
        session.used_ports = session.used_ports or {}
        vim.list_extend(session.used_ports, ports or {})
    end)

    before('custom-event-ports-done')

    before('custom-event-popup', function(session, body)
        local msg = body.info and body.info.message or '<NIL>'
        local level = ({
            warning = vim.log.levels.WARN,
            error = vim.log.levels.ERROR,
        })[body.info and body.info.type] or vim.log.levels.INFO
        vim.notify(msg, level)
    end)

    before('custom-stop')
    before('custom-continued')
    before('swo-configure')
    before('rtt-configure', function(session, body)
        assert(body and body.type == 'socket')
        assert(body.decoder.type == 'console')
        rtt.connect(body.decoder.tcpPort, body.decoder.port, function()
            session:request('rtt-poll')
        end)
    end)
    before('record-event')
    before('custom-event-open-disassembly')
    before('custom-event-post-start-server')
    before('custom-event-post-start-gdb')
    before('custom-event-session-terminating')
    before('custom-event-session-restart')
    before('custom-event-session-reset')
end

return M
