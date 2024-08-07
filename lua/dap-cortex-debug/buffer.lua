local utils = require('dap-cortex-debug.utils')

---@alias BufferSetWin fun(buf: number): number, function?
---@alias Uri string

---@class CDBufferOpts
---Assigns buffer to a window, return window and optional callback to call when is ready.
---@field set_win BufferSetWin
---@field uri Uri
---@field on_delete? fun(b: CDBuffer)

---@class CDBuffer:Class
---@field buf number
---@field on_delete? fun(b: CDBuffer)
local Buffer = utils.class()

local augroup = vim.api.nvim_create_augroup('CortexDebugBuffer', { clear = true })

---@type { [Uri]: CDBuffer }
local buffers = {}

---Create new buffer object with its buffer.
---NOTE: For terminals this needs to open a window, at least temporarily.
---Will delete previous buffer with the same URI. `get_or_new` can be used instead.
---@param opts CDBufferOpts
---@return CDBuffer
function Buffer:new(opts, instance)
    if buffers[opts.uri] then
        buffers[opts.uri]:delete()
    end

    local b = instance or self:_new()
    b.buf = nil
    b.on_delte = nil
    b.uri = assert(opts.uri)

    b:_create_buf(opts.set_win)
    b:_create_autocmds()

    buffers[b.uri] = b

    return b
end

function Buffer.get(uri)
    return buffers[uri]
end

function Buffer._get_or_new(cls)
    return function(opts)
        return cls.get(opts.uri) or cls:new(opts)
    end
end

--- Must be overwritten in deriving classes since this is a constructor
Buffer.get_or_new = Buffer._get_or_new(Buffer)

function Buffer:delete()
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
end

local function delete_buf_by_name(name)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf) == name then
            vim.api.nvim_buf_delete(buf, { force = true })
            return
        end
    end
end

local function set_buf_name(buf, uri)
    -- If the buffer already exists then it might e.g. have been restored by mksession - delete it
    -- We do not care for buffers with our names matching our URI scheme that are not owned by us,
    -- so delete forcefully.
    delete_buf_by_name(uri)
    vim.api.nvim_buf_set_name(buf, uri)
end

---Set buffer URI
---@param uri Uri
function Buffer:set_uri(uri)
    if buffers[uri] then
        utils.error('Buffer with given URI already exists: "%s"', uri)
        return
    end
    -- TODO: set user friendly b:term_title?
    set_buf_name(self.buf, uri)
    buffers[self.uri] = nil
    self.uri = uri
    buffers[self.uri] = self
end

function Buffer:_create_buf(set_win)
    self.buf = vim.api.nvim_create_buf(true, true)
    self:set_uri(self.uri)

    local win, on_ready = set_win(self.buf)
    vim.api.nvim_set_option_value('number', false, { win = win, scope = 'local' })
    vim.api.nvim_set_option_value('relativenumber', false, { win = win, scope = 'local' })
    vim.api.nvim_set_option_value('spell', false, { win = win, scope = 'local' })

    self:_create_buf_final()

    if on_ready then
        on_ready(self)
    end
end

function Buffer:_create_buf_final() end

function Buffer:_create_autocmds()
    vim.api.nvim_create_autocmd('BufDelete', {
        group = augroup,
        buffer = self.buf,
        once = true,
        callback = function()
            buffers[self.uri] = nil
            if self.on_delete then
                self:on_delete()
            end
        end,
    })
end

function Buffer:is_visible()
    return vim.api.nvim_win_is_valid(vim.fn.bufwinid(self.buf))
end

function Buffer:is_valid()
    return vim.api.nvim_buf_is_valid(self.buf)
end

function Buffer.temporary_win(buf)
    local curr_win = vim.api.nvim_get_current_win()
    local new_win = vim.api.nvim_open_win(buf, false, {
        relative = 'win',
        win = curr_win,
        width = vim.api.nvim_win_get_width(curr_win),
        height = vim.api.nvim_win_get_height(curr_win),
        row = 0,
        col = 0,
        style = 'minimal',
    })
    return new_win, function()
        vim.api.nvim_win_close(new_win, false)
    end
end

function Buffer.open_in_split(opts)
    return function(buf)
        local prev_win = vim.api.nvim_get_current_win()
        vim.cmd(table.concat({ opts.mods or '', opts.size or '', 'split' }, ' '))
        local new_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(new_win, buf)
        if not opts.focus then
            vim.api.nvim_set_current_win(prev_win)
        end
        return new_win
    end
end

return Buffer
