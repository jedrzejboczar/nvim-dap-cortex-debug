local utils = require('dap-cortex-debug.utils')
local Buffer = require('dap-cortex-debug.buffer')

---@class CDTerminalOpts:CDBufferOpts
---Assigns terminal buffer to a window, return window and optional callback to call when terminal is ready.
---@field on_input? fun(term: CDTerminal, data: string)
---@field scroll_on_open? boolean Scroll to end when opening with new output (default true)

---@class CDTerminal:CDBuffer
---@field term number CDTerminal job channel
---@field on_input? fun(term: CDTerminal, data: string)
---@field scroll_on_open boolean
local Terminal = utils.class(Buffer)

local augroup = vim.api.nvim_create_augroup('CortexDebugTerminal', { clear = true })

local function escape_sequence(seq)
    -- In lua this decimal, so it's the equivalent of the usual \033 (octal)
    return '\027' .. seq
end

-- See: https://en.wikipedia.org/wiki/ANSI_escape_code
-- PERF: could merge multiple into one when needed, like "[1;31m"; probably not worth it
---@class CDTerminalDisplay
Terminal.display = {
    reset = escape_sequence('[0m'),
    clear = escape_sequence('[0m'),
    bold = escape_sequence('[1m'),
    dim = escape_sequence('[2m'),
    italic = escape_sequence('[2m'),
    underline = escape_sequence('[2m'),
    fg = {
        black = escape_sequence('[30'),
        red = escape_sequence('[31'),
        green = escape_sequence('[32'),
        yellow = escape_sequence('[33'),
        blue = escape_sequence('[34'),
        magenta = escape_sequence('[35'),
        cyan = escape_sequence('[36'),
        white = escape_sequence('[37'),
        bright_black = escape_sequence('[90'),
        bright_red = escape_sequence('[91'),
        bright_green = escape_sequence('[92'),
        bright_yellow = escape_sequence('[93'),
        bright_blue = escape_sequence('[94'),
        bright_magenta = escape_sequence('[95'),
        bright_cyan = escape_sequence('[96'),
        bright_white = escape_sequence('[97'),
    },
    bg = {
        black = escape_sequence('[40'),
        red = escape_sequence('[41'),
        green = escape_sequence('[42'),
        yellow = escape_sequence('[43'),
        blue = escape_sequence('[44'),
        magenta = escape_sequence('[45'),
        cyan = escape_sequence('[46'),
        white = escape_sequence('[47'),
        bright_black = escape_sequence('[100'),
        bright_red = escape_sequence('[101'),
        bright_green = escape_sequence('[102'),
        bright_yellow = escape_sequence('[103'),
        bright_blue = escape_sequence('[104'),
        bright_magenta = escape_sequence('[105'),
        bright_cyan = escape_sequence('[106'),
        bright_white = escape_sequence('[107'),
    },
}

---Create new terminal object with its buffer. This needs to open a window, at least temporarily.
---Will delete previous terminal with the same URI. `get_or_new` can be used instead.
---@param opts CDTerminalOpts
---@return CDTerminal
function Terminal:new(opts)
    local term = Buffer:new(opts --[[@as CDBufferOpts]], self:_new())

    term.needs_scroll = false
    term.on_input = opts.on_input
    term.scroll_on_open = vim.F.if_nil(opts.scroll_on_open, true)

    return term --[[@as CDTerminal]]
end

-- FIXME: overriding because superclass directly accesses Buffer methods
function Terminal.get_or_new(opts)
    return Terminal.get(opts.uri) or Terminal:new(opts)
end

function Terminal:_create_buf_final()
    -- Needs to be stored as &channel doesn't work with buffers created using nvim_open_term
    self.term = vim.api.nvim_open_term(self.buf, {
        on_input = function(_input, _term, _buf, data)
            if self.on_input then
                self:on_input(data)
            end
        end,
    })
end

-- Set up buffer autocommands
function Terminal:_create_autocmds()
    Buffer:_create_autocmds()
    vim.api.nvim_create_autocmd('BufWinEnter', {
        group = augroup,
        buffer = self.buf,
        callback = function()
            if self.needs_scroll then
                self.needs_scroll = false
                -- Do it in next loop when the window is valid
                vim.schedule(function()
                    self:scroll()
                end)
            end
        end,
    })
end

---Clear terminal buffer. Safe to call from |lua-loop-callbacks|.
function Terminal:clear()
    self:send(escape_sequence('c'))
end

---Send data to terminal. Safe to call from |lua-loop-callbacks|.
---@param data string
function Terminal:send(data, newline)
    local is_first = not self.__was_first_send
    self.__was_first_send = true

    -- FIXME: is it always needed
    data = data:gsub('\n', '\r\n')
    if newline then
        data = data .. '\r\n'
    end
    utils.call_api(function()
        pcall(vim.api.nvim_chan_send, self.term, data)
        if is_first then
            self:scroll()
        elseif not self:is_visible() then
            self.needs_scroll = true
        end
    end)
end

function Terminal:send_line(data)
    return self:send(data, true)
end

function Terminal:is_visible()
    return vim.api.nvim_win_is_valid(vim.fn.bufwinid(self.buf))
end

---Scroll terminal to the end. Safe to call from |lua-loop-callbacks|.
function Terminal:scroll()
    utils.call_api(function()
        if not vim.api.nvim_buf_is_valid(self.buf) then
            return
        end
        local win = vim.fn.bufwinid(self.buf) -- TODO: or scroll all windows?
        if vim.api.nvim_win_is_valid(win) then
            local nlines = vim.api.nvim_buf_line_count(self.buf)
            vim.api.nvim_win_set_cursor(win, { nlines, 0 })
        else
            self.needs_scroll = true
        end
    end)
end

return Terminal
