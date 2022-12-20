local dap = require('dap')
local utils = require('dap-cortex-debug.utils')
local Buffer = require('dap-cortex-debug.buffer')

local M = {}

local ns = vim.api.nvim_create_namespace('cortex-debug-memory')

function M.hexdump(bytes, opts)
    opts = vim.tbl_extend('force', {
        start = 0,
        n = 16,
        double_space = 8,
    }, opts or {})

    local lines = {}
    local addr = opts.start
    local addr_inc = opts.n
    for chunk in utils.chunks(bytes, opts.n) do
        local hex = {}
        local ascii = {}
        for i, byte in ipairs(chunk) do
            local str = string.format('%02x', byte)
            if opts.double_space and (i - 1) % opts.double_space == 0 then
                str = ' ' .. str
            end
            table.insert(hex, str)

            local printable = byte >= 32 and byte <= 126
            table.insert(ascii, printable and string.char(byte) or '.')
        end

        local line = string.format('0x%08x %s  %s', addr, table.concat(hex, ' '), table.concat(ascii, ''))
        table.insert(lines, line)
        addr = addr + addr_inc
    end
    return lines
end

local state = {
    address = nil,
    length = nil,
    opts = nil,
    bytes = nil,
    id = nil,
}

M.uri = [[cortex-debug://memory]]

function M.memory_buf()
    return Buffer.get_or_new {
        uri = M.uri,
        set_win = Buffer.open_in_split { size = 90, mods = 'vertical' },
        on_delete = function()
            if state.address then
                for key, _ in pairs(state) do
                    state[key] = nil
                end
            end
        end
    }
end

function M.is_open()
    return Buffer.get(M.uri) ~= nil
end

local function update_display(prev_bytes)
    state.id = (state.id or 0) + 1

    local hex_opts = vim.tbl_extend('error', { start = tonumber(state.address) }, state.opts)
    local lines = M.hexdump(state.bytes, hex_opts)

    local changes = {}
    if prev_bytes then
        for i = 1, #state.bytes do
            if state.bytes[i] ~= prev_bytes[i] then
                table.insert(changes, i)
            end
        end
    end

    local mem = M.memory_buf()
    vim.api.nvim_buf_clear_namespace(mem.buf, ns, 0, -1)
    vim.api.nvim_buf_set_lines(mem.buf, 0, -1, false, lines)

    for _, change in ipairs(changes) do
        local n = hex_opts.n or 16
        local line = math.floor((change - 1) / n)
        local line_pos = (change - 1) % n
        -- address, space, 3 chars per byte, 1 per each 8 bytes
        local col = 10 + 2 + line_pos * 3 + math.floor(line_pos / 8)
        vim.api.nvim_buf_add_highlight(mem.buf, ns, 'DiffChange', line, col, col + 2)
        -- ascii
        local ascii_col = 10 + 2 + 3 * n + math.floor(n / 8) + line_pos
        vim.api.nvim_buf_add_highlight(mem.buf, ns, 'DiffChange', line, ascii_col, ascii_col + 1)
    end

    local id = state.id
    local delay = 3000
    vim.defer_fn(function()
        if state.id == id and vim.api.nvim_buf_is_valid(mem.buf) then
            vim.api.nvim_buf_clear_namespace(mem.buf, ns, 0, -1)
        end
    end, delay)
end

function M.show(address, length, opts)
    state.address = address or state.address
    state.length = length or state.length
    state.opts = opts or state.opts or {}

    session = state.opts.session or dap.session()
    utils.assert(session ~= nil, 'No DAP session is running')
    utils.assert(session.config.type == 'cortex-debug', 'DAP session is not cortex-debug')

    session:request('read-memory', { address = state.address, length = state.length },
        function(err, response)
            if err then
                utils.error('read-memory failed: %s', err)
                return
            end

            if tonumber(response.startAddress) ~= state.address then
                utils.warn('Address mismatch 0x%08x vs 0x%08x', response.startAddress, state.address)
            end

            local prev = state.bytes
            state.bytes = response.bytes
            update_display(prev)
        end
    )
end

function M.update()
    if M.is_open() then
        M.show()
    end
end

return M
