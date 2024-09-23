local utils = require('dap-cortex-debug.utils')
local Buffer = require('dap-cortex-debug.buffer')

---@class CDTerminalSendOpts
---@field newline? boolean
---@field bold? boolean
---@field error? boolean

---@class CDTerminalLineBufferOpts
---@field timeout? number Timeout [ms] after which buffered data is pushed even without newline

---@class CDTerminalOpts:CDBufferOpts
---Assigns terminal buffer to a window, return window and optional callback to call when terminal is ready.
---@field on_input? fun(term: CDTerminal, data: string)
---@field scroll_on_open? boolean Scroll to end when opening with new output (default true)
---@field line_buffer? CDTerminalLineBufferOpts Perform line-buffering when sending data (default true)

---@class CDTerminal:CDBuffer
---@field on_input? fun(term: CDTerminal, data: string)
---@field scroll_on_open boolean
---@field line_buf_timeout number?
---@field line_buf_timer userdata?
---@field line_buf string[]
local Terminal = utils.class(Buffer)

local augroup = vim.api.nvim_create_augroup('CortexDebugTerminal', { clear = true })

---Create new terminal object with its buffer. This needs to open a window, at least temporarily.
---Will delete previous terminal with the same URI. `get_or_new` can be used instead.
---@param opts CDTerminalOpts
---@return CDTerminal
function Terminal:new(opts, instance)
    local term = Buffer:new(opts --[[@as CDBufferOpts]], instance or self:_new()) --[[@as CDTerminal]]

    term.needs_scroll = false
    term.on_input = opts.on_input
    term.scroll_on_open = vim.F.if_nil(opts.scroll_on_open, true)

    term.line_buf = {}
    local line_buffer = vim.F.if_nil(opts.line_buffer, {})
    if line_buffer then
        term.line_buf_timeout = line_buffer.timeout or 100
        term.line_buf_timer = vim.uv.new_timer()
    end

    return term
end

Terminal.get_or_new = function()
    error('NOT IMPLEMENTED')
end

function Terminal:_create_buf_final()
    error('NOT IMPLEMENTED')
end

-- Set up buffer autocommands
function Terminal:_create_autocmds()
    Buffer._create_autocmds(self)
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
    error('NOT IMPLEMENTED')
end

---Send data to terminal. Safe to call from |lua-loop-callbacks|.
---@param data string
---@param opts? CDTerminalSendOpts
function Terminal:send(data, opts)
    if self.line_buf_timeout then
        self:_send_line_buffered(data, opts)
    else
        self:_send(data, opts)
    end
end

---@param data string
---@param opts? CDTerminalSendOpts
function Terminal:_send(data, opts)
    error('NOT IMPLEMENTED')
end

---@param data string
---@param opts? CDTerminalSendOpts
function Terminal:send_line(data, opts)
    return self:send(data, vim.tbl_extend('force', opts or {}, { newline = true }))
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
        -- scroll all windows
        local nlines = vim.api.nvim_buf_line_count(self.buf)
        self.needs_scroll = true
        for _, win in ipairs(vim.fn.win_findbuf(self.buf)) do
            vim.api.nvim_win_set_cursor(win, { nlines, 0 })
            self.needs_scroll = false
        end
    end)
end

function Terminal:_commit_buffered()
    if #self.line_buf == 0 then
        return
    end
    local line = table.concat(self.line_buf, '')
    if line ~= '' then
        self:_send(line)
    end
    self.line_buf = {}
end

---@param data string
---@param opts? CDTerminalSendOpts
function Terminal:_send_line_buffered(data, opts)
    opts = opts or {}
    if opts.newline then
        table.insert(self.line_buf, data .. '\n')
        self:_commit_buffered()
        return
    end

    while #data do
        local newline = data:find('\n')
        if not newline then
            table.insert(self.line_buf, data)
            self.line_buf_timer:start(self.line_buf_timeout, 0, function()
                self:_commit_buffered()
            end)
            return
        else
            self.line_buf_timer:stop()
            table.insert(self.line_buf, data:sub(1, newline))
            self:_commit_buffered()
            data = data:sub(newline + 1)
        end
    end
end

---@type CDTerminal
return Terminal
