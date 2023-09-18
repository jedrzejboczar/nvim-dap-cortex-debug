local M = {}

local dap = require('dap')
local consoles = require('dap-cortex-debug.consoles')
local memory = require('dap-cortex-debug.memory')
local utils = require('dap-cortex-debug.utils')

local PLUGIN = 'cortex-debug'
M.debug = true

local function set_listener(when, name, handler)
    handler = handler or function() end

    local log_handler = function(_session, ...)
        local args = { ... }
        if debug then
            utils.debug('cortex-debug.%s.%s: %s', when, name, vim.inspect(args))
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

    before('event_custom-event-popup', function(_session, body)
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

        local channel = body.decoder.port
        local rtt_opts = {
            channel = channel,
            tcp_port = body.decoder.tcpPort,
            logfile = body.decoder.logfile,
        }
        consoles.rtt_connect(rtt_opts, function(client, term)
            -- See: cortex-debug/src/frontend/swo/sources/socket.ts:123
            -- When the TCP connection to the RTT port is established, send config commands
            -- within 100ms to configure the RTT channel.  See
            -- https://wiki.segger.com/RTT#SEGGER_TELNET_Config_String for more information
            -- on the config string format.
            if session.config.servertype == 'jlink' then
                client:write(string.format('$$SEGGER_TELNET_ConfigStr=RTTCh;%d$$', channel))
            end

            -- Notify our dapui element to update
            require('dap-cortex-debug.dapui.rtt').on_rtt_connect(channel)

            session:request('rtt-poll')
            term:scroll()
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
    after('stackTrace', function(session, err, response, _payload)
        if not err and vim.tbl_get(response, 'stackFrames', 1, 'name') == 'cortex-debug-dummy' then
            session._cortex_debug_dummy = (session._cortex_debug_dummy or 0) + 1
            if session._cortex_debug_dummy <= 3 then
                session.stopped_thread_id = nil
                vim.defer_fn(function()
                    utils.debug('Re-requesting threads to fix dummy frame')
                    session:update_threads()
                end, 50)
            else
                utils.warn_once('Failed to update stack trace after 3 cortex-debug-dummy frames')
            end
        end
    end)

    -- Cortex-debug sends a tooltips (multi-line info) under variable.type, e.g.
    --   SystemCoreClock undefined SystemCoreClock;
    --   dec: 168000000
    --   hex: 0x0a037a00
    --   oct: 001200675000
    --   bin: 00001010 00000011 01111010 00000000 = 168000000
    -- where: "SystemCoreClock {TYPE} = 168000000".
    -- Try to extract actual type from the first line, and store the whole string under _tooltip.
    -- TODO: find a way to use this tooltip on hover.
    local function fix_variable_type(var)
        if not var.type then
            return
        end

        var._tooltip = var.type
        local line = vim.split(var.type, '\n', { plain = true, trimempty = true })[1]

        -- Remove trailing semicolon
        if vim.endswith(line, ';') then
            line = line:sub(1, #line - 1)
        end
        -- Remove variable name
        local tokens = vim.tbl_filter(function(token)
            return token ~= var.name
        end, vim.split(line, '%s+'))

        -- Remove redundant registers info
        if tokens[1] == 'Register:' and vim.endswith(tokens[2], var.name) then
            tokens = vim.list_slice(tokens, 3)
        end

        var.type = table.concat(tokens, ' ')
    end

    before('variables', function(_session, _err, response, _payload)
        if not response then
            return
        end
        for _, var in ipairs(response.variables or {}) do
            fix_variable_type(var)
        end
    end)

    after('event_stopped', function(_session, _body)
        memory.update()
    end)
end

return M
