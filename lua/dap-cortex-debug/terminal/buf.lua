local utils = require('dap-cortex-debug.utils')
local codes = require('dap-cortex-debug.terminal.codes')
local BaseTerminal = require('dap-cortex-debug.terminal.base')

---@class CDTerminal.Buf:CDTerminal
local Terminal = utils.class(BaseTerminal)

Terminal.ns = vim.api.nvim_create_namespace('dap-cortex-debug.terminal.buf')

---Create new terminal object with its buffer. This needs to open a window, at least temporarily.
---Will delete previous terminal with the same URI. `get_or_new` can be used instead.
---@param opts CDTerminalOpts
---@return CDTerminal.Buf
function Terminal:new(opts)
    local term = BaseTerminal:new(opts, self:_new())
    term.has_newline = false
    return term
end

Terminal.get_or_new = Terminal._get_or_new(Terminal)

function Terminal:_create_buf_final()
    vim.bo[self.buf].buftype = 'nofile'
end

function Terminal:clear()
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, {})
    vim.api.nvim_buf_clear_namespace(self.buf, self.ns, 0, -1)
end

local function cursor_at_end(win)
    local api = vim.api
    return api.nvim_win_is_valid(win) and
        api.nvim_win_get_cursor(win)[1] == api.nvim_buf_line_count(api.nvim_win_get_buf(win))
end

---Send data to terminal. Safe to call from |lua-loop-callbacks|.
---@param data string
---@param opts? CDTerminalSendOpts
function Terminal:send(data, opts)
    opts = opts or {}

    data = data:gsub('\r\n', '\n')
    if opts.newline then
        data = data .. '\n'
    end

    -- replace escape sequences: https://stackoverflow.com/a/24005600
    -- TODO: parse some escape sequences into extmark highlights
    data = data:gsub(codes.escape_sequence('%[[^@-~]*[@-~]'), '')

    local lines = vim.split(data, '\n', { plain = true })

    utils.call_api(function()
        local srow, scol, erow, ecol

        if opts.bold or opts.error then
            srow = vim.api.nvim_buf_line_count(self.buf) - 1
            scol = #vim.api.nvim_buf_get_lines(self.buf, -2, -1, true)[1]
        end

        -- check which windows need scroll before appending text
        local to_scroll = vim.tbl_filter(cursor_at_end, vim.fn.win_findbuf(self.buf))

        vim.api.nvim_buf_set_text(self.buf, -1, -1, -1, -1, lines)

        if opts.bold or opts.error then
            erow = vim.api.nvim_buf_line_count(self.buf) - 1
            ecol = #vim.api.nvim_buf_get_lines(self.buf, -2, -1, true)[1]
            local set_mark = function(hl_group)
                vim.api.nvim_buf_set_extmark(self.buf, self.ns, srow, scol, { end_row = erow, end_col = ecol, hl_group = hl_group })
            end
            if opts.bold then
                set_mark('Bold')
            end
            if opts.error then
                set_mark('ErrorMsg')
            end
        end

        local nlines = vim.api.nvim_buf_line_count(self.buf)
        self.needs_scroll = true
        for _, win in ipairs(to_scroll) do
            vim.api.nvim_win_set_cursor(win, { nlines, 0 })
            self.needs_scroll = false
        end
    end)
end

return Terminal
