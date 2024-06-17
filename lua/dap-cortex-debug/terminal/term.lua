local utils = require('dap-cortex-debug.utils')
local BaseTerminal = require('dap-cortex-debug.terminal.base')
local codes = require('dap-cortex-debug.terminal.codes')

---@class CDTerminal.Term:CDTerminal
---@field term number CDTerminal job channel
local Terminal = utils.class(BaseTerminal)

---Create new terminal object with its buffer. This needs to open a window, at least temporarily.
---Will delete previous terminal with the same URI. `get_or_new` can be used instead.
---@param opts CDTerminalOpts
---@return CDTerminal.Term
function Terminal:new(opts)
    local instance = self:_new()
    return BaseTerminal:new(opts, instance)
end

Terminal.get_or_new = Terminal._get_or_new(Terminal)

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

function Terminal:clear()
    self:send(codes.escape_sequence('c'))
end

---Send data to terminal. Safe to call from |lua-loop-callbacks|.
---@param data string
---@param opts? CDTerminalSendOpts
function Terminal:send(data, opts)
    opts = opts or {}

    -- FIXME: is it always needed
    data = data:gsub('\n', '\r\n')
    if opts.newline then
        data = data .. '\r\n'
    end

    local text = {}
    if opts.bold then
        table.insert(text, codes.display.bold)
    end
    if opts.error then
        table.insert(text, codes.display.fg.red)
    end
    table.insert(text, data)
    if opts.bold or opts.error then
        table.insert(text, codes.display.clear)
    end
    data = table.concat(text)

    local is_first = not self.__was_first_send
    self.__was_first_send = true

    utils.call_api(function()
        pcall(vim.api.nvim_chan_send, self.term, data)
        if is_first then
            self:scroll()
        elseif not self:is_visible() then
            self.needs_scroll = true
        end
    end)
end

return Terminal
