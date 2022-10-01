local M = {}

local Console = require('dap-cortex-debug.console')

-- TODO: support multiple RTT channels
local console = Console:new { name = 'RTT' }

function M.parse_data(data)
    return data
end

--@param opts.host string
--@param opts.port number
--@param opts.channel number
--@param opts.max_retries number
--@param opts.period number
--@param opts.on_success function
--@param opts.on_error function?
local function try_connect(opts)
    local client = vim.loop.new_tcp()
    client:connect(opts.host, opts.port, function(err)
        if not err then
            opts.on_success(client)
        else
            opts.retries = (opts.retries or 0) + 1
            if opts.retries <= opts.max_retries then
                vim.defer_fn(function()
                    M.try_connect(opts)
                end, opts.period)
            elseif opts.on_error then
                opts.on_error(opts.retries - 1)
            end
        end
    end)
end

function M.connect(port, channel, on_connect)
    try_connect {
        host = '0.0.0.0',
        port = port,
        channel = channel,
        max_retries = 10,
        period = 250,
        on_error = function()
            local msg = string.format('RTT: could not connect on port %d channel %d', port, channel)
            vim.notify(msg, vim.log.levels.ERROR)
        end,
        on_success = function(client)
            -- See: cortex-debug/src/frontend/swo/sources/socket.ts:123
            -- When the TCP connection to the RTT port is established, send config commands
            -- within 100ms to configure the RTT channel.  See
            -- https://wiki.segger.com/RTT#SEGGER_TELNET_Config_String for more information
            -- on the config string format.
            client:write(string.format('$$SEGGER_TELNET_ConfigStr=RTTCh;%d$$', channel))

            console:rename('rtt:' .. channel)
            console:clear()
            console:open()

            client:read_start(function(err, data)
                assert(not err, err)
                if data then
                    local chunk = M.parse_data(data)
                    if chunk then
                        console:append(chunk, true)
                    end
                else
                    client:shutdown()
                    client:close()
                    console:show_info('disconnected')
                end
            end)

            if on_connect then
                on_connect(client)
            end
        end,
    }
end

return M
