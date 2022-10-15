local consoles = require('dap-cortex-debug.consoles')

-- Find first open RTT channel
local function find_rtt_channel()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buf)
        local channel = name:match([[cortex%-debug://rtt:([0-9]+)]])
        channel = vim.F.npcall(tonumber, channel)
        if channel then
            return channel
        end
    end
end

-- We only know the RTT channel when the session starts, so initially open a scratch
-- buffer and replace it later.
local rtt_win

-- We create the terminal only after connecting to RTT, so a response from rtt-poll
-- request would be an ideal listener, but cortex-debug does not respond for rtt-poll,
-- so this gets called when we connect.
local function on_rtt_connect(channel)
    local curr_win = vim.api.nvim_get_current_win()
    local curr_buf = vim.api.nvim_get_current_buf()

    if rtt_win and channel then
        local term = consoles.rtt_term(channel)
        if term:is_visible() then
            vim.api.nvim_win_close(vim.fn.bufwinid(term.buf), false)
        end

        -- This won't work because dapui forces buffers from its internally saved mapping
        -- vim.api.nvim_win_set_buf(rtt_win, term.buf)

        -- HACK: replace the buffer in dapui's window-buffer internal mapping
        local layouts = require('dapui.windows').layouts
        for _, layout in ipairs(layouts) do
            if layout.win_bufs[rtt_win] then
                -- Replace the internal mapping
                layout.win_bufs[rtt_win] = term.buf
                -- Open terminal buffer in dapui window
                vim.api.nvim_win_set_buf(rtt_win, term.buf)
                -- The old dapui buffer will jump to current window so reset it
                vim.api.nvim_win_set_buf(curr_win, curr_buf)
                -- Make sure that terminal will be auto scrolling with new output
                term:scroll()
                return
            end
        end
    end
end

---@type Element
return {
    name = 'RTT',
    buf_options = { filetype = 'dapui_rtt' },
    float_defaults = { width = 80, height = 20, enter = true },
    setup = function() end,
    setup_buffer = function(buf)
        rtt_win = vim.fn.bufwinid(buf)
        local channel = find_rtt_channel()
        on_rtt_connect(channel)
    end,
    render = function() end,
    on_rtt_connect = on_rtt_connect,
}
