local utils = require('dap-cortex-debug.utils')

---@class HexDump:Class
---@field start_addr integer Starting address
---@field per_line integer Number of bytes shown in each line
---@field word_bytes integer Number of bytes grouped into a single word (without spaces)
---@field endianess 'little'|'big' Show words as little-endian / big-endian
---@field group_by integer Size of group (in bytes), groups are separated by additional space
---@field addr_0x boolean Whether to add 0x prefix to address
---@field spaces integer Number of spaces used between sections
---@field _fmt { [string]: { [1]: string, [2]: integer }}
local HexDump = utils.class()

---@class HexDumpOpts
---@field start_addr? integer
---@field per_line? integer
---@field word_bytes? integer
---@field endianess? 'little'|'big'
---@field group_by? integer
---@field addr_0x? boolean
---@field spaces? integer

---@param opts? HexDumpOpts
---@return HexDump
function HexDump:new(opts)
    opts = opts or {}
    local o = self:_new {
        start_addr = opts.start_addr or 0,
        per_line = opts.per_line or 16,
        word_bytes = opts.word_bytes or 1,
        endianess = opts.endianess or 'little',
        group_by = opts.group_by or 8,
        addr_0x = vim.F.if_nil(opts.addr_0x, false),
        spaces = opts.spaces or 3,
    }
    -- to allow for construction of invalid objects with settings for hot-reload
    pcall(o._update_fmt, o)
    return o
end

function HexDump:_update_fmt()
    assert(self.per_line % self.word_bytes == 0, 'per_line must be multiple of word_bytes')
    assert(self.group_by % self.word_bytes == 0, 'group_by must be multiple of word_bytes')
    self._fmt = {
        addr = self.addr_0x and { '0x%08x', 10 } or { '%08x', 8 },
        word = { string.rep('%02x', self.word_bytes), 2 * self.word_bytes },
    }
end

--- Given a range of values <left, right> where there is a breaking point at which criteria `test(x)` changes from
--- returning false (left) to returning true (right), performs binary search to find that value.
---@param left integer
---@param right integer
---@param test fun(val: integer): boolean
---@return integer?
local function binary_search(left, right, test)
    assert(left <= right)
    while left < right do
        local mid = math.floor((left + right) / 2)
        if test(mid) then
            right = mid
        else
            left = mid + 1
        end
    end
    return left
end

--- Get maximum number of values that can be passed to unpack() without an error.
---@return integer
local max_unpack_size = utils.lazy(function()
    local min_estimate = 1
    local max_estimate = 16 * 1024
    local tbl = {}
    local first_err = binary_search(min_estimate, max_estimate, function(n)
        return not pcall(unpack, tbl, 1, n)
    end)
    assert(first_err and first_err > 1, 'Could not determine max number of arguments for unpack()')
    return first_err - 1
end)

--- Optimized function for converting a list of bytes into a byte-string making use of large unpack() calls.
---@param bytes integer[]
---@return string
local function bytes_to_string(bytes)
    local max_chunk = max_unpack_size()
    local taken, len = 0, #bytes
    local parts = {}
    while taken < len do
        local chunk = math.min(max_chunk, len - taken)
        table.insert(parts, string.char(unpack(bytes, taken + 1, taken + 1 + chunk - 1)))
        taken = taken + chunk
    end
    return table.concat(parts)
end

---@param data string|integer[] prefer using byte-string instead of a list-table
---@return string[]
function HexDump:lines(data)
    vim.validate { data = { data, { 'string', 'table' } } }
    if type(data) == 'table' then
        data = bytes_to_string(data)
    end

    self:_update_fmt()

    local spaces = string.rep(' ', self.spaces)
    local lines = {}
    local row = 0

    for chunk in utils.string_chunks(data, self.per_line) do
        local line = {}

        local addr = self.start_addr + row * self.per_line
        table.insert(line, string.format(self._fmt.addr[1], addr))
        table.insert(line, spaces)

        -- Hex section
        local nbytes = 0
        local word_i = 1
        local hex_len = 0
        for word in utils.string_chunks(chunk, self.word_bytes) do
            nbytes = nbytes + #word

            if self.endianess == 'little' then
                word = word:reverse()
            end
            table.insert(line, string.format(self._fmt.word[1], word:byte(1, #word)))
            hex_len = hex_len + self._fmt.word[2]

            if word_i ~= self:words_per_line() then -- no space after last word
                local more_space = word_i % self:words_per_group() == 0
                table.insert(line, more_space and '  ' or ' ')
                hex_len = hex_len + (more_space and 2 or 1)
                word_i = word_i + 1
            end
        end

        -- Padding
        if nbytes ~= self.per_line then
            local n = (self:_ascii_col(0) - self._fmt.addr[2] - 2 * self.spaces) - hex_len
            table.insert(line, string.rep(' ', n))
        end

        table.insert(line, spaces)

        -- Ascii section
        for i = 1, #chunk do
            local byte = chunk:byte(i)
            table.insert(line, self:_printable(byte) and string.char(byte) or '.')
        end

        table.insert(lines, table.concat(line))
        row = row + 1
    end

    return lines
end

--- Buffer position of text for given byte hex
---@param b integer 1-indexed byte number
---@return integer row
---@return integer start_col
---@return integer end_col non-inclusive
function HexDump:pos_hex(b)
    local row = self:_byte_row(b - 1)
    local col = self:_byte_col(self:_byte_in_row(b - 1))
    return row, col, col + 2
end

--- Buffer position of text for given byte ascii
---@param b integer 1-indexed byte number
---@return integer row
---@return integer start_col
---@return integer end_col non-inclusive
function HexDump:pos_ascii(b)
    local row = self:_byte_row(b - 1)
    local col = self:_ascii_col(self:_byte_in_row(b - 1))
    return row, col, col + 1
end

function HexDump:words_per_line()
    return math.floor(self.per_line / self.word_bytes)
end
function HexDump:words_per_group()
    return math.floor(self.group_by / self.word_bytes)
end

-- Everyting 0-indexed
function HexDump:_byte_row(b)
    return math.floor(b / self.per_line)
end
function HexDump:_byte_in_row(b)
    return b % self.per_line
end
-- All following inputs `b` are modulo line (aka _byte_in_row)
function HexDump:_byte_word(b)
    return math.floor(b / self.word_bytes)
end
function HexDump:_byte_in_word(b)
    local i = b % self.word_bytes
    return self.endianess == 'little' and (self.word_bytes - 1 - i) or i
end
function HexDump:_byte_groups(b)
    return math.floor(b / self.group_by)
end
function HexDump:_byte_col(b)
    local addr_w = self._fmt.addr[2] + self.spaces
    local word_w = self._fmt.word[2] + 1
    return addr_w + self:_byte_word(b) * word_w + self:_byte_in_word(b) * 2 + self:_byte_groups(b)
end
function HexDump:_ascii_col(b)
    -- return self:_byte_col(self.per_line - 1) + 2 + self.spaces + b
    local addr_w = self._fmt.addr[2] + self.spaces
    local word_w = self._fmt.word[2] + 1
    local hex_end = addr_w + (self:words_per_line() * word_w - 1) + self:_byte_groups(self.per_line - 1)
    return hex_end + self.spaces + b
end

function HexDump:_printable(byte)
    return byte >= 32 and byte <= 126
end

--- Open test buffer with live-update of settings on key presses
---@private
-- stylua: ignore
function HexDump._test_buf_open(opts)
    local dump = HexDump:new(opts)

    local bytes = {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112,
        113, 114, 115, 116, 117, 119, 120, 121, 122, 10, 113, 119, 101, 114, 116, 121,
        121, 117, 105, 111, 112, 49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 97,
        115, 100, 102, 103, 104, 106, 107, 108, 59, 122, 120, 99, 118, 98, 110, 109,
        44, 46, 47, 10, 1, 2, 3, 4, 5, 5, 4, 5, 6, 7, 8, 6,
        4, 56, 9, 4, 6, 4, 6, 4,
    }

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, dump:lines(bytes))

    vim.cmd('enew')
    vim.api.nvim_set_current_buf(buf)

    local last_n_lines = 0
    local update = function()
        local ok, lines = pcall(dump.lines, dump, bytes)
        local err_line = ''
        if ok then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            last_n_lines = vim.api.nvim_buf_line_count(buf)
        else
            err_line = 'ERROR: ' .. lines
        end

        local info = vim.split(vim.inspect(vim.tbl_extend('force', {}, dump)), '\n')
        table.insert(info, err_line)

        vim.api.nvim_buf_set_lines(buf, last_n_lines, -1, false, info)

        -- Run a position test
        local tests = {}
        local n_ok = 0
        for i, byte in ipairs(bytes) do
            local row, start_col, end_col = dump:pos_hex(i)
            local hex = vim.api.nvim_buf_get_text(buf, row, start_col, row, end_col, {})[1]
            local hex_expected = string.format('%02x', byte)
            if hex ~= hex_expected then
                table.insert(tests,
                    string.format('ERR at %2d: %s vs %s : %d %d %d', i, hex, hex_expected, row, start_col, end_col))
            else
                n_ok = n_ok + 1
                table.insert(tests,
                    string.format('ok  at %2d: %s vs %s : %d %d %d', i, hex, hex_expected, row, start_col, end_col))
            end
        end

        vim.api.nvim_buf_set_lines(buf, -1, -1, false, { string.format('Tests OK: %d / %d', n_ok, #bytes) })
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, tests)
    end

    local nmap = function(lhs, fn)
        vim.keymap.set('n', lhs, function()
            fn()
            update()
        end, { buffer = buf })
    end

    nmap('-', function() dump.per_line = dump.per_line - 1 end)
    nmap('+', function() dump.per_line = dump.per_line + 1 end)
    nmap('<f1>', function() dump.word_bytes = math.ceil(dump.word_bytes / 2) end)
    nmap('<f2>', function() dump.word_bytes = dump.word_bytes * 2 end)
    nmap('<f3>', function() dump.group_by = dump.group_by - 1 end)
    nmap('<f4>', function() dump.group_by = dump.group_by + 1 end)
    nmap('<f5>', function() dump.addr_0x = not dump.addr_0x end)
    nmap('<f6>', function() dump.endianess = dump.endianess == 'big' and 'little' or 'big' end)
    nmap('<f7>', function() dump.spaces = dump.spaces - 1 end)
    nmap('<f8>', function() dump.spaces = dump.spaces + 1 end)

    update()
end

return HexDump
