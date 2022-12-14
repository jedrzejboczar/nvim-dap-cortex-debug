local dap = require('dap')
local utils = require('dap-cortex-debug.utils')
local Buffer = require('dap-cortex-debug.buffer')
local HexDump = require('dap-cortex-debug.hexdump')

local ns = vim.api.nvim_create_namespace('cortex-debug-memory')

---@type { [integer]: MemoryView }
local mem_views = {}

--- Memory viewer that attaches to a buffer to display hexdump
---@class MemoryView:Class
---@field id integer Memory view window number
---@field address integer Memory start address
---@field length integer Memory length in bytes
---@field bytes nil|integer[] Current memory bytes
---@field buffer CDBuffer Display buffer
---@field update_id integer Incremented on each update
---@field highlight_time integer Duration [ms] of change highlight (-1 -> disabled, 0 -> until next update)
---@field _hexdump HexDumpOpts Hexdump display options
local MemoryView = utils.class()

---@class MemoryViewOpts
---@field id integer
---@field address integer
---@field length integer
---@field hexdump? HexDumpOpts
---@field highlight_time? integer

---@param opts MemoryViewOpts
---@return MemoryView
function MemoryView:new(opts)
    vim.validate { opts = { opts, 'table' } }

    local mem = self:_new()
    mem.id = opts.id
    mem.address = assert(opts.address)
    mem.length = assert(opts.length)
    mem._hexdump = opts.hexdump or {}
    mem.highlight_time = opts.highlight_time or 0
    mem.bytes = nil
    mem.update_id = 0
    mem.buffer = Buffer.get_or_new {
        uri = MemoryView._uri(mem.id),
        set_win = Buffer.open_in_split { size = 90, mods = 'vertical' },
        on_delete = function()
            mem_views[self.id] = nil
        end,
    }
    mem.buffer._memview = mem

    mem_views[mem.id] = mem

    mem:_set_keymaps()

    return mem
end

function MemoryView:_set_keymaps()
    -- stylua: ignore
    local fn = {
        inc = function(v) return v + 1 end,
        dec = function(v) return v - 1 end,
        mul2 = function(v) return 2 * v end,
        div2 = function(v) return math.ceil(v / 2) end, -- avoid going to 0 for mul2 to work
        swap_endianess = function(v) return v == 'big' and 'little' or 'big' end,
        invert = function(v) return not v end,
    }

    local maps = {
        { 'g?', 'Show help' },
        { 'gr', 'Refresh memory from DUT' },
        { 'ge', 'Toggle byte-word endianess', 'endianess', fn.swap_endianess },
        { 'gx', 'Toggle address 0x prefix', 'addr_0x', fn.invert },
        { '-', 'Decrement bytes per line', 'per_line', fn.dec },
        { '+', 'Increment bytes per line', 'per_line', fn.inc },
        { '[w', 'Decrease bytes per word (/2)', 'word_bytes', fn.div2 },
        { ']w', 'Increase bytes per word (x2)', 'word_bytes', fn.mul2 },
        { '[g', 'Decrement byte group size', 'group_by', fn.dec },
        { ']g', 'Increment byte group size', 'group_by', fn.inc },
        { '[s', 'Decrement number of spaces', 'spaces', fn.dec },
        { ']s', 'Increment number of spaces', 'spaces', fn.inc },
    }
    for _, map in ipairs(maps) do
        maps[map[1]] = map
    end

    local nmap = function(lhs, rhs)
        vim.keymap.set('n', lhs, rhs, { buffer = self.buffer.buf, desc = maps[lhs][2] })
    end

    -- Automatically create parameter update mappings
    for _, map in ipairs(maps) do
        if map[3] then
            local lhs, desc, param, modify_fn = unpack(map)
            local rhs = function()
                self:with { hexdump = { [param] = modify_fn(self:hexdump()[param]) } }
                self:set(self.bytes)
            end
            vim.keymap.set('n', lhs, rhs, { buffer = self.buffer.buf, desc = desc })
        end
    end

    nmap('gr', function()
        self:update()
    end)
    nmap('g?', function()
        local fmt = '%5s   %s'
        local lines = { fmt:format('LHS', 'Description') }
        for _, map in ipairs(maps) do
            local lhs, desc = unpack(map)
            table.insert(lines, fmt:format('`' .. lhs .. '`', desc))
        end
        table.insert(lines, 'Move cursor to go back')

        vim.api.nvim_buf_clear_namespace(self.buffer.buf, ns, 0, -1)
        vim.api.nvim_buf_set_lines(self.buffer.buf, 0, -1, false, lines)
        vim.schedule(function()
            vim.api.nvim_create_autocmd('CursorMoved', {
                once = true,
                buffer = self.buffer.buf,
                callback = function()
                    if self.bytes then
                        self:set(self.bytes)
                    end
                end,
            })
        end)
    end)
end

---@param opts MemoryViewOpts
---@return MemoryView
function MemoryView:with(opts)
    if opts.id and opts.id ~= self.id then
        utils.warn('Cannot reconfigure MemoryView.id')
    end
    self.address = vim.F.if_nil(opts.address, self.address)
    self.length = vim.F.if_nil(opts.length, self.length)
    self._hexdump = vim.tbl_extend('force', self._hexdump, opts.hexdump or {})
    self.highlight_time = vim.F.if_nil(opts.highlight_time, self.highlight_time)
    return self
end

function MemoryView._uri(id)
    return string.format([[cortex-debug://memory:%d]], id)
end

---@param id integer
---@return MemoryView?
function MemoryView.get(id)
    local buffer = Buffer.get(MemoryView._uri(id))
    return buffer and buffer._memview
end

---@param opts MemoryViewOpts
---@return MemoryView
function MemoryView.get_or_new(opts)
    local buffer = Buffer.get(MemoryView._uri(opts.id))
    return buffer and buffer._memview:with(opts) or MemoryView:new(opts)
end

function MemoryView:hexdump()
    local opts = vim.tbl_extend('error', { start_addr = self.address }, self._hexdump)
    return HexDump:new(opts)
end

function MemoryView:set(bytes)
    if not self.buffer:is_valid() then
        return
    end
    local buf = self.buffer.buf

    self.update_id = self.update_id + 1
    local changes = self:changes(bytes)
    self.bytes = bytes

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

    -- Handle hexdump generation errors due to incorrect parameters
    local ok, dump, lines = pcall(function()
        local dump = self:hexdump()
        local lines = dump:lines(bytes)
        return dump, lines
    end)

    if not ok then
        local err = dump
        local line1 = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
        local end_col = vim.startswith(line1 or '', 'ERROR') and 1 or 0
        vim.api.nvim_buf_set_lines(buf, 0, end_col, false, { 'ERROR: ' .. err })
        vim.api.nvim_buf_add_highlight(buf, ns, 'Error', 0, 0, -1)
        return
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    if self.highlight_time >= 0 then
        for _, c in ipairs(changes) do
            vim.api.nvim_buf_add_highlight(buf, ns, 'DiffChange', dump:pos_hex(c))
            vim.api.nvim_buf_add_highlight(buf, ns, 'DiffChange', dump:pos_ascii(c))
        end
    end

    if self.highlight_time > 0 then
        local id = self.update_id
        vim.defer_fn(function()
            if self.update_id == id and self.buffer:is_valid() then
                vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
            end
        end, self.highlight_time)
    end
end

function MemoryView:update()
    local session = dap.session()
    utils.assert(session ~= nil, 'No DAP session is running')
    utils.assert(session.config.type == 'cortex-debug', 'DAP session is not cortex-debug')
    session:request('read-memory', { address = self.address, length = self.length }, function(err, response)
        if err then
            utils.error('read-memory failed: %s', err.message or vim.inspect(err))
            return
        end
        if tonumber(response.startAddress) ~= self.address then
            utils.warn('Address mismatch 0x%08x vs 0x%08x', response.startAddress, self.address)
        end
        self:set(response.bytes)
    end)
end

--- Find positions of modified bytes
---@param bytes integer[]
---@return integer[]
function MemoryView:changes(bytes)
    local changes = {}
    if self.bytes then
        for i = 1, #bytes do
            if self.bytes[i] ~= bytes[i] then
                table.insert(changes, i)
            end
        end
    end
    return changes
end

---@param opts MemoryViewOpts
local function show(opts)
    MemoryView.get_or_new(opts):update()
end

local function update()
    for _, view in pairs(mem_views) do
        view:update()
    end
end

---@async
--- Try to evaluate a variable to get its memory range
---@param var string Should be variable value, & will be prepended
---@param opts? { frame_id?: integer }
---@return any|nil error
---@return nil|{ address: integer, length: integer }
local function var_to_mem(var, opts)
    opts = vim.tbl_extend('force', {
        frame_id = dap.session().current_frame.id,
    }, opts or {})

    local evaluate = function(expr)
        return utils.session_request('evaluate', {
            expression = expr,
            frameId = opts.frame_id,
            context = 'variables',
        })
    end

    local err, response = evaluate('&' .. var)
    if err then
        return err
    end
    local address = tonumber(response.memoryReference)
    if not address then
        return 'Could not get address of ' .. var
    end

    err, response = evaluate(string.format('sizeof(%s)', var))
    if err then
        return err
    end
    local length = tonumber(response.result)
    if not length then
        return 'Could not get size of ' .. var
    end

    return nil, { address = address, length = length }
end

return {
    show = show,
    update = update,
    var_to_mem = var_to_mem,
    MemoryView = MemoryView,
}
