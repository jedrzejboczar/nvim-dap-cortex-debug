local M = {}

local dap = require('dap')
local config = require('dap-cortex-debug.config')

---Wrap a function with given values for N first arguments
---@param fn function
---@param ... any
---@return function
function M.bind(fn, ...)
    local args = { ... }
    return function(...)
        return fn(unpack(args), ...)
    end
end

local function logger(level, notify_fn, cond)
    return function(...)
        if cond and not cond() then
            return
        end
        -- Use notify_fn as string to get correct function if user
        -- replaced it later via vim.notify = ...
        local notify = vim[notify_fn]
        notify(string.format(...), level)
    end
end

local function debug_enabled()
    return config.debug
end

local function info_enabled()
    return not config.silent
end

M.debug = logger(vim.log.levels.DEBUG, 'notify', debug_enabled)
M.debug_once = logger(vim.log.levels.DEBUG, 'notify_once', debug_enabled)
M.info = logger(vim.log.levels.INFO, 'notify', info_enabled)
M.info_once = logger(vim.log.levels.INFO, 'notify_once', info_enabled)
M.warn = logger(vim.log.levels.WARN, 'notify')
M.warn_once = logger(vim.log.levels.WARN, 'notify_once')
M.error = logger(vim.log.levels.ERROR, 'notify')
M.error_once = logger(vim.log.levels.ERROR, 'notify_once')

---Assert a condition or raise an error with formatted message
---@param val any Value treated as assertion condition
---@param err string Error message with optional format string placeholders
---@param ... any Arguments to the format string
---@return any Value if it was true-ish
function M.assert(val, err, ...)
    if not val then
        -- Use level 2 to show the error at caller location
        error(string.format(err, ...), 2)
    end
    return val
end

---Run function in protected mode like pcall but preserve traceback information
---@param fn function
---@param ... any
---@return boolean Success
---@return any Function return value or error message
function M.trace_pcall(fn, ...)
    return xpcall(fn, debug.traceback, ...)
end

---Make path absolute, remove repeated/trailing slashes
---@param path string
---@return string
function M.path_sanitize(path)
    path = vim.fn.fnamemodify(path, ':p'):gsub('/+', '/'):gsub('/$', '')
    return path
end

---Run `fn`, scheduling it if called in fast event
---@param fn function
function M.call_api(fn)
    if vim.in_fast_event() then
        vim.schedule(fn)
    else
        fn()
    end
end

---Create a callback that will resume currently running coroutine
---@return function
function M.coroutine_resume()
    local co = assert(coroutine.running())
    return function(...)
        coroutine.resume(co, ...)
    end
end

---@async
--- Execute session request as sync call
---@param command string
---@param arguments? any
---@param session? Session
---@return table err
---@return any result
function M.session_request(command, arguments, session)
    session = session or dap.session()
    local resume = M.coroutine_resume()
    session:request(command, arguments, function(err, response)
        resume(err, response)
    end)
    return coroutine.yield()
end

---Determine system platform
---@return 'darwin'|'windows'|'linux'
function M.get_platform()
    if vim.fn.has('macos') == 1 or vim.fn.has('osx') == 1 then
        return 'darwin'
    elseif vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
        return 'windows'
    else
        return 'linux'
    end
end

function M.get_lib_ext()
    local extensions = {
        darwin = 'dylib',
        windows = 'dll',
        linux = 'so',
    }
    return config.lib_extension or extensions[M.get_platform()]
end

--- Resolve and sanitize path to cortex-debug extension
---@return string?
function M.get_extension_path()
    local paths = vim.fn.glob(config.extension_path, false, true)
    if paths and paths[1] then
        return M.path_sanitize(paths[1])
    end
end

--- Resolve path to debugadapter.js
---@param extension_path string
---@return string
function M.get_debugadapter_path(extension_path)
    local paths = vim.fn.glob(extension_path .. '/dist/debugadapter.js', true, true)
    return paths and M.path_sanitize(paths[1])
end

---@class Class
---@field _new fun(cls: table, fields?: table): table Object constructor

--- Create a class that inherits from given class
---@param base_cls table?
---@return Class
function M.class(base_cls)
    -- New class table and metatable
    local cls = {}
    cls.__index = cls

    function cls:_new(fields)
        return setmetatable(fields or {}, cls)
    end

    -- Inheritance: indexing cls first checks cls due to object's metatable
    -- and then base_cls due to the metatable of `cls` itself
    if base_cls then
        setmetatable(cls, { __index = base_cls })
    end

    return cls
end

--- Returns an iterator over list items grouped in chunks
---@generic T
---@param list T[]
---@param len integer
---@return function
function M.chunks(list, len)
    local head = 1
    local tail = len
    return function()
        if head > #list then
            return
        end
        local chunk = vim.list_slice(list, head, tail)
        head = head + len
        tail = tail + len
        return chunk
    end
end

---@generic T
---@param list T[]
function M.reverse_in_place(list)
    for i = 1, math.floor(#list / 2) do
        local j = #list + 1 - i
        local tmp = list[i]
        list[i] = list[j]
        list[j] = tmp
    end
end

return M
