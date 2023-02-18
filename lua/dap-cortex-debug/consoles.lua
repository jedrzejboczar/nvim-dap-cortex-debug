local tcp = require('dap-cortex-debug.tcp')
local utils = require('dap-cortex-debug.utils')
local config = require('dap-cortex-debug.config')
local Terminal = require('dap-cortex-debug.terminal')

local M = {}

local function bold(text)
    return Terminal.display.bold .. text .. Terminal.display.clear
end

local function bold_error(text)
    return Terminal.display.bold .. Terminal.display.fg.red .. text .. Terminal.display.clear
end

local gdb_server_console = {
    server = nil,
    port = nil,
}

function M.gdb_server_console_term()
    return Terminal.get_or_new {
        set_win = Terminal.temporary_win,
        uri = [[cortex-debug://gdb-server-console]],
        on_delete = function()
            if gdb_server_console.server then
                local server = gdb_server_console.server
                gdb_server_console.server = nil
                server:shutdown(function()
                    server:close()
                end)
            end
        end,
    }
end

function M.gdb_server_console()
    if not gdb_server_console.server then
        gdb_server_console.port = tcp.get_free_port(55878)
        gdb_server_console.server = tcp.serve {
            port = gdb_server_console.port,
            on_connect = function(sock)
                local sock_info = sock:getsockname()
                -- Cannot create terminal in callback so do wait for loop
                vim.schedule(function()
                    local term = M.gdb_server_console_term()
                    term:scroll()
                    term:send_line(bold(string.format('Connected from %s:%d', sock_info.ip, sock_info.port)))

                    sock:read_start(function(err, data)
                        if err then
                            term:send_line(bold_error('ERROR: ' .. err))
                        elseif data then
                            term:send(data)
                        else
                            sock:close()
                            term:send_line(bold('Disconnected\n'))
                        end
                    end)
                end)
            end,
            on_error = function(err)
                utils.error('Could not open gdb server console: %s', err)
                gdb_server_console.server = nil
                gdb_server_console.port = nil
            end,
        }
    end
    return gdb_server_console
end

function M.rtt_term(channel, set_win)
    local default_set_win = config.dapui_rtt and Terminal.temporary_win
        or Terminal.open_in_split { size = 80, mods = 'vertical' }
    return Terminal.get_or_new {
        uri = string.format([[cortex-debug://rtt:%d]], channel),
        set_win = set_win or default_set_win,
    }
end

function M.rtt_connect(channel, tcp_port, on_connected)
    local on_connect = function(client)
        local term = M.rtt_term(channel)
        term:send_line(bold('Connected on port ' .. tcp_port))

        client:read_start(function(err, data)
            if err then
                term:send_line(bold_error('ERROR: ' .. err))
            elseif data then
                term:send(data)
            else
                client:shutdown()
                client:close()
                pcall(vim.api.nvim_buf_delete, term.buf, { force = true })
                term:send_line(bold('Disconnected\n'))
            end
        end)

        on_connected(client, term)
    end

    tcp.connect {
        host = '0.0.0.0',
        port = tcp_port,
        retries = 20,
        delay = 250,
        on_error = vim.schedule_wrap(function(err)
            utils.error('Failed to connect RTT:%d on TCP port %d: %s', channel, tcp_port, err)
        end),
        on_success = vim.schedule_wrap(on_connect),
    }
end

return M
