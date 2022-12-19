local M = {}

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

---Determine system platform
---@return 'darwin'|'windows'|'linux'
function M.get_platform()
    if vim.fn.has('macos') == 1 then
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

return M
