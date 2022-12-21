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
    vim.validate {opts = {opts, 'table'}}

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

    -- TODO: keymaps

    return mem
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
    return buffer and buffer._memview or MemoryView:new(opts)
end

function MemoryView:hexdump()
    local opts = vim.tbl_extend('error', { address = self.address }, self._hexdump)
    return HexDump:new(opts)
end

function MemoryView:set(bytes)
    if not self.buffer:is_valid() then return end

    self.update_id = self.update_id + 1
    local changes = self:changes(bytes)
    self.bytes = bytes

    local dump = self:hexdump()
    local lines = dump:lines(bytes)

    vim.api.nvim_buf_clear_namespace(self.buffer.buf, ns, 0, -1)
    vim.api.nvim_buf_set_lines(self.buffer.buf, 0, -1, false, lines)

    if self.highlight_time >= 0 then
        for _, c in ipairs(changes) do
            vim.api.nvim_buf_add_highlight(self.buffer.buf, ns, 'DiffChange', dump:pos_hex(c))
            vim.api.nvim_buf_add_highlight(self.buffer.buf, ns, 'DiffChange', dump:pos_ascii(c))
        end
    end

    if self.highlight_time > 0 then
        local id = self.update_id
        vim.defer_fn(function()
            if self.update_id == id and self.buffer:is_valid() then
                vim.api.nvim_buf_clear_namespace(self.buffer.buf, ns, 0, -1)
            end
        end, self.highlight_time)
    end
end

function MemoryView:update()
    session = dap.session()
    utils.assert(session ~= nil, 'No DAP session is running')
    utils.assert(session.config.type == 'cortex-debug', 'DAP session is not cortex-debug')
    session:request('read-memory', { address = self.address, length = self.length },
        function(err, response)
            if err then
                utils.error('read-memory failed: %s', err)
                return
            end
            if tonumber(response.startAddress) ~= self.address then
                utils.warn('Address mismatch 0x%08x vs 0x%08x', response.startAddress, self.address)
            end
            self:set(response.bytes)
        end
    )
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

local function show(address, length, opts)
    opts = opts or {}
    local view = MemoryView.get_or_new {
        address = address,
        length = length,
        id = opts.id or 1,
    }
    view.address = address
    view.length = length
    view:update()
end

local function update()
    for _, view in pairs(mem_views) do
        view:update()
    end
end

return {
    show = show,
    update = update,
    MemoryView = MemoryView,
}
