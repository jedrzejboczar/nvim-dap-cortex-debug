local M = {}

local utils = require('dap-cortex-debug.utils')

local localhost = '127.0.0.1'

---@class ConnectOpts
---@field host? string
---@field port number
---@field retries? number Maximum number of retries (default 0 or math.huge if delay_total_max!=nil)
---@field delay? number Delay in milliseconds between retriesa (default 100)
---@field delay_multiplier? number Each subsequent delay is X times longer (default 1.0)
---@field delay_max? number Max delay after multiplication
---@field delay_total_max? number Max total delay, can be used limit by delay instead of retries
---@field on_success fun(client: userdata)
---@field on_error fun(err: string?)

---Connect to a server with retries
---@param opts ConnectOpts
function M.connect(opts)
    coroutine.wrap(function()
        local resume = utils.coroutine_resume()

        local retries = opts.retries and opts.retries or (opts.delay_total_max and math.huge or 0)
        local attempts = retries + 1
        local host = opts.host or localhost
        local delay = opts.delay or 100
        local delay_mul = opts.delay_multiplier or 1.0
        local delay_max = opts.delay_max or math.huge
        local delay_total_max = opts.delay_total_max or math.huge
        local delay_total = 0

        local err
        for attempt = 1, attempts do
            local client = assert(vim.loop.new_tcp())
            client:connect(host, opts.port, resume)
            err = coroutine.yield()

            if not err then
                opts.on_success(client)
                return
            end
            client:shutdown()
            client:close()

            if attempt ~= attempts then
                -- check if the total time after sleeping would exceed the limit
                delay_total = delay_total + delay
                if delay_total > delay_total_max then
                    break
                end

                vim.defer_fn(resume, delay)
                coroutine.yield()

                -- multiply and limit
                delay = math.ceil(math.min(delay * delay_mul, delay_max))
                -- make the last attempt exactly at delay_total_max
                if delay_total ~= delay_total_max then
                    delay = math.min(delay, delay_total_max - delay_total)
                end
            end
        end

        opts.on_error(err)
    end)()
end

---@class ServeOpts
---@field host? string
---@field port number
---@field backlog? number Maximum number of pending connections
---@field on_connect fun(socket: userdata)
---@field on_error fun(err: string?)

---Start serving on given port
---@param opts ServeOpts
---@return userdata LibUV server userdata
function M.serve(opts)
    local host = opts.host or localhost
    local backlog = opts.backlog or 128

    local server = assert(vim.loop.new_tcp())
    -- TODO: handle bind/listen errors
    server:bind(host, opts.port)
    server:listen(backlog, function(err)
        if err then
            opts.on_error(err)
        else
            local socket = vim.loop.new_tcp()
            server:accept(socket)
            opts.on_connect(socket)
        end
    end)

    return server
end

---Check if given port is available
---@param port integer
---@param host? string
---@return boolean
function M.try_port_listen(port, host)
    local tcp = assert(vim.loop.new_tcp())
    local ok = pcall(function()
        assert(tcp:bind(host or localhost, port))
        assert(tcp:listen(1, function() end))
    end)
    tcp:shutdown()
    tcp:close()
    return ok
end

---Find a free port
---@param preferred? integer Try to use this port if possible
---@param host? string
---@return integer Port that is free for use
function M.get_free_port(preferred, host)
    if preferred and M.try_port_listen(preferred) then
        return preferred
    end
    local tcp = vim.loop.new_tcp()
    tcp:bind(host or localhost, 0) -- 0 finds a free port
    local port = tcp:getsockname().port
    tcp:shutdown()
    tcp:close()
    return port
end

return M
