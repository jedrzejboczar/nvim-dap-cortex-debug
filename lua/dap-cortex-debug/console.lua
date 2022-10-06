-- Console listening on a tcp port and showing output in a terminal buffer
local Console = {}
Console.__index = Console

function Console:new(opts)
    assert(opts.name)
    return setmetatable({
        name = opts.name,
    }, self)
end

local function maybe_shedule(fn)
    if vim.in_fast_event() then
        fn = vim.schedule_wrap(fn)
    end
    fn()
end

function Console:rename(name)
    maybe_shedule(function()
        self.name = name
        if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
            vim.api.nvim_buf_set_name(self.buf, string.format('[%s]', self.name))
        end
    end)
end

function Console:show_info(str, newline)
    newline = vim.F.if_nil(newline, true)
    self:append(string.format('[%s: %s]%s', self.name, str, newline and '\n' or ''))
end

function Console:_visible()
    local wins = vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
    for _, win in ipairs(wins) do
        if vim.api.nvim_win_get_buf(win) == self.buf then
            return true
        end
    end
end

function Console:_create_term_buf()
    self.buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(self.buf, string.format('[%s]', self.name))
    vim.api.nvim_buf_set_option(self.buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(self.buf, 'swapfile', false)

    vim.api.nvim_create_autocmd('BufWinEnter', {
        buffer = self.buf,
        callback = function() self:_configure_win(0) end
    })
    -- vim.api.nvim_create_autocmd('BufWinEnter', {
    --     buffer = self.buf,
    --     once = true,
    --     callback = function() self:_scroll_win(0) end
    -- })

    -- Create a window before starting a terminal
    local width = math.max(1, vim.api.nvim_win_get_width(0) - 2)
    local height = math.max(1, math.ceil(vim.api.nvim_win_get_height(0) / 2))
    local fopts = vim.lsp.util.make_floating_popup_options(width, height, {})
    local win = vim.api.nvim_open_win(self.buf, false, fopts)
    vim.api.nvim_win_set_buf(win, self.buf)

    self.term = vim.api.nvim_open_term(self.buf, {})
    assert(self.term ~= 0, 'Failed to create terminal')

    -- if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, false)
    -- end

    self:show_info(os.date())
end

function Console:clear()
    maybe_shedule(function()
        self:_ensure_term_buf()

        -- it's not possible to modify terminal buffer content so swap the current one
        local old = self.buf
        vim.api.nvim_buf_set_name(old, string.format('[%s-old]', self.name))
        self:_create_term_buf()
        vim.api.nvim_buf_delete(old, { force = true })
    end)
end

function Console:_ensure_term_buf()
    if self.buf and vim.api.nvim_buf_is_valid(self.buf) then return end
    self:_create_term_buf()
end

function Console:_configure_win(win)
    vim.api.nvim_win_set_option(win, 'number', false)
    vim.api.nvim_win_set_option(win, 'relativenumber', false)
    vim.api.nvim_win_set_option(win, 'signcolumn', 'no')
    vim.api.nvim_win_set_option(win, 'spell', false)
end

function Console:_scroll_win(win)
    -- Set cursor to last line to have "auto-scroll" to bottom on new output
    local buf = vim.api.nvim_win_get_buf(win)
    local nlines = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(win, { nlines, 0 })
end

function Console:scroll()
    maybe_shedule(function()
        local wins = vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
        for _, win in ipairs(wins) do
            if vim.api.nvim_win_get_buf(win) == self.buf then
                self:_scroll_win(win)
                return
            end
        end
    end)
end

function Console:open(focus)
    maybe_shedule(function()
        if self:_visible() then return end

        self:_ensure_term_buf()

        local prev_win = vim.api.nvim_get_current_win()
        vim.cmd('belowright split')
        local win = vim.api.nvim_get_current_win()

        vim.api.nvim_win_set_buf(win, self.buf)
        -- Rest of configuration done in BufWinEnter

        if not focus then
            vim.api.nvim_set_current_win(prev_win)
        end
    end)
end

function Console:append(chunk, scroll)
    maybe_shedule(function()
        self:_ensure_term_buf()
        chunk = chunk:gsub('\n', '\r\n')  -- fix newlines
        pcall(vim.api.nvim_chan_send, self.term, chunk)
        if scroll and vim.api.nvim_get_current_buf() ~= self.buf then
            self:scroll()
        end
    end)
end

return Console
