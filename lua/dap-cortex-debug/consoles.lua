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

local function log_timestamp()
    return os.date('%Y-%m-%d_%H:%M:%S')
end

---@class dap-cortex-debug.Logfile
---@field fd number? file descriptor
---@field filename string?
local Logfile = {}
Logfile.__index = Logfile

function Logfile:new(filename)
    local o = setmetatable({
        fd = nil,
        filename = filename,
    }, self)
    if filename then
        o:_open()
        o:write('\n') -- mark new "open" with a newline
        o:write(string.format('LOG START: %s\n', log_timestamp()))
    end
    return o
end

function Logfile:_open()
    self.fd = vim.loop.fs_open(self.filename, 'a', 438)
    if not self.fd then
        utils.warn('Could not open logfile: %s', self.filename)
        return
    end
end

function Logfile:write(data)
    if not self.fd then
        return
    end
    local ok = vim.loop.fs_write(self.fd, data)
    if not ok then
        utils.warn_once('Writing to logfile failed: %s', self.filename)
    end
end

function Logfile:close()
    if not self.fd then
        return
    end
    self:write(string.format('LOG END: %s\n', log_timestamp()))
    vim.loop.fs_close(self.fd)
end

function M.gdb_server_console_term()
    return Terminal.get_or_new {
        set_win = Terminal.temporary_win,
        uri = [[cortex-debug://gdb-server-console]],
        on_delete = function()
            if gdb_server_console.server then
                local server = gdb_server_console.server
                gdb_server_console.server = nil
                if server then
                    server:shutdown(function()
                        server:close()
                    end)
                end
            end
        end,
    }
end

function M.gdb_server_console(logfile)
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

                    local log = Logfile:new(logfile)

                    sock:read_start(function(err, data)
                        if err then
                            term:send_line(bold_error('ERROR: ' .. err))
                        elseif data then
                            log:write(data)
                            term:send(data)
                        else
                            sock:close()
                            log:close()
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

---@class dap-cortex-debug.RTTConnectOpts
---@field channel number
---@field tcp_port number
---@field logfile? string

---@param opts dap-cortex-debug.RTTConnectOpts
---@param on_connected fun(client, term)
---@param on_client_connected? fun(client) raw client connection callback, without vim.schedule
function M.rtt_connect(opts, on_connected, on_client_connected)
    local on_connect = vim.schedule_wrap(function(client)
        local term = M.rtt_term(opts.channel)
        term:send_line(bold('Connected on port ' .. opts.tcp_port))

        local log = Logfile:new(opts.logfile)

        client:read_start(function(err, data)
            if err then
                term:send_line(bold_error('ERROR: ' .. err))
            elseif data then
                log:write(data)
                term:send(data)
            else
                client:shutdown()
                client:close()
                log:close()
                pcall(vim.api.nvim_buf_delete, term.buf, { force = true })
                term:send_line(bold('Disconnected\n'))
            end
        end)

        on_connected(client, term)
    end)

    local on_success = function(client)
        if on_client_connected then
            on_client_connected(client)
        end
        on_connect(client)
    end

    tcp.connect {
        host = '0.0.0.0',
        port = opts.tcp_port,
        retries = 20,
        delay = 250,
        on_error = vim.schedule_wrap(function(err)
            utils.error('Failed to connect RTT:%d on TCP port %d: %s', opts.channel, opts.tcp_port, err)
        end),
        on_success = on_success,
    }
end

return M
