local M = {}

local Console = require('dap-cortex-debug.console')

local function create_server(host, port, on_connect)
    local server = assert(vim.loop.new_tcp())
    local backlog = 128
    server:bind(host, port)
    server:listen(backlog, function(err)
        assert(not err, err)
        local sock = vim.loop.new_tcp()
        server:accept(sock)
        on_connect(sock)
    end)
    return server
end

-- Support only a single console at a time
M.console = Console:new { name = 'gdb-server' }

M.auto_open = false

-- TODO: find free port? do this before launch and pass in config to adapter?
function M.connect(port)
    port = port or 55878

    M.console.server = create_server('0.0.0.0', port, function(sock)
        M.console:clear()
        -- Append output from the server to the terminal window
        sock:read_start(function(err, chunk)
            assert(not err, err)
            if chunk then
                M.console:append(chunk)
            else
                sock:close()
                M.console:show_info('disconnected', false)
            end
        end)
    end)

    return port
end

function M.open()
    M.console:open()
end

function M.gdbServerConsolePort(port)
    return function()
        return coroutine.create(function(dap_run_co)
            vim.schedule(function()
                port = M.connect(port)
                if M.auto_open then
                    M.open()
                end
                coroutine.resume(dap_run_co, port)
            end)
        end)
    end
end

return M
