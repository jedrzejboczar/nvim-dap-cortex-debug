local M = {}

local dap = require('dap')
local config = require('dap-cortex-debug.config')
local rtt = require('dap-cortex-debug.rtt')
local gdb_server = require('dap-cortex-debug.gdb_server')
local utils = require('dap-cortex-debug.utils')

local PLUGIN = 'cortex-debug'
M.debug = true

local function set_listener(when, name, handler)
    handler = handler or function() end
    local is_event = vim.startswith(name, 'event_')

    local log_handler = function(_session, ...)
        local args = {...}
        if debug then
            local msg = string.format('cortex-debug.%s.%s: %s', when, name, vim.inspect(args))
            vim.notify(msg, vim.log.levels.DEBUG)
        end
    end

    dap.listeners[when][name][PLUGIN] = function(...)
        log_handler(...)
        return handler(...)
    end
end

local before = utils.bind(set_listener, 'before')
local after = utils.bind(set_listener, 'after')

-- Create handlers for cortex-debug custom events
function M.setup()
    after('event_capabilities', function(session, body) end, 'after')

    before('event_custom-event-ports-allocated', function(session, body)
        local ports = body and body.info
        session.used_ports = session.used_ports or {}
        vim.list_extend(session.used_ports, ports or {})
    end)

    before('event_custom-event-ports-done')

    before('event_custom-event-popup', function(session, body)
        local msg = body.info and body.info.message or '<NIL>'
        local level = ({
            warning = vim.log.levels.WARN,
            error = vim.log.levels.ERROR,
        })[body.info and body.info.type] or vim.log.levels.INFO
        vim.notify(msg, level)
    end)

    before('event_custom-stop')
    before('event_custom-continued')
    before('event_swo-configure')
    before('event_rtt-configure', function(session, body)
        assert(body and body.type == 'socket')
        assert(body.decoder.type == 'console')
        rtt.connect(body.decoder.tcpPort, body.decoder.port, function()
            session:request('rtt-poll')
        end)
    end)
    before('event_record-event')
    before('event_custom-event-open-disassembly')
    before('event_custom-event-post-start-server')
    before('event_custom-event-post-start-gdb')
    before('event_custom-event-session-terminating')
    before('event_custom-event-session-restart')
    before('event_custom-event-session-reset')

    before('initialize', function(_session, _err, _response, _payload) end)

    -- HACK: work around cortex-debug's workaround for vscode's bug...
    -- Cortex-debug includes a workaround for some bug in VS code, which causes cortex-debug
    -- to send the first frame/thread as "cortex-debug-dummy". It is solved by runToEntryPoint
    -- which will result in a breakpoint stop and then we will get correct stack trace. But we
    -- need to re-request threads, and force nvim-dap to jump to the new frame received (it
    -- won't jump because it sees that session.stopped_thread_id ~= nil).
    after('stackTrace', function(session, err, response, payload)
        if vim.tbl_get(response, 'stackFrames', 1, 'name') == 'cortex-debug-dummy' then
            session.stopped_thread_id = nil
            session:update_threads()
        end
    end)

end

return M
