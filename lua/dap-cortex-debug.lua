local M = {}

local dap = require('dap')
local utils = require('dap-cortex-debug.utils')
local config = require('dap-cortex-debug.config')
local events = require('dap-cortex-debug.events')
local gdb_server = require('dap-cortex-debug.gdb_server')

local function path_sanitize(path)
    return vim.fn.fnamemodify(path, ':p'):gsub('/+', '/'):gsub('/$', '')
end

local function get_extension_path()
    if config.extension_path and vim.fn.isdirectory(config.extension_path) then
        return path_sanitize(config.extension_path)
    end
    local paths = vim.fn.glob(config.extension_path_glob, false, true)
    if paths and paths[1] then
        return path_sanitize(paths[1])
    end
    utils.warn_once('Missing cortex-debug extension_path')
end

local function get_debugadapter_path(extension_path)
    -- TODO: does this solve Windows compatibility?
    local paths = vim.fn.glob(extension_path .. '/dist/debugadapter.js', true, true)
    return paths and path_sanitize(paths[1])
end

local function lib_extension()
    if config.lib_extension then
        return config.lib_extension
    elseif vim.fn.has('macos') then
        return 'dylib'
    elseif vim.fn.has('win32') or vim.fn.has('win64') then
        return 'dll'
    else
        return 'so'
    end
end

local function resolve_rtos(launch_config)
    local valid = {
        jlink = { 'Azure', 'ChibiOS', 'embOS', 'FreeRTOS', 'NuttX', 'Zephyr' },
        openocd = { 'ChibiOS', 'eCos', 'embKernel', 'FreeRTOS', 'mqx', 'nuttx', 'ThreadX', 'uCOS-III', 'auto' },
    }
    if valid[launch_config.servertype] then
        -- TODO: openocd support
        if launch_config.servertype == 'jlink' then
            return string.format('GDBServer/RTOSPlugin_%s.%s', launch_config.rtos, lib_extension())
        end
    end
    utils.warn('Could not resolve RTOS "%s"', launch_config.rtos)
end

function M.setup(opts)
    config.setup(opts)
    events.setup()


    -- TODO: is this necessary?
    dap.defaults['cortex-debug'].auto_continue_if_many_stopped = false

    -- Could be a function(cb, config) to auto-generate docker command arguments
    local extension_path = get_extension_path()
    dap.adapters['cortex-debug'] = {
        type = 'executable',
        command = 'node',
        args = { get_debugadapter_path(extension_path) },
        options = { detached = false, },
        enrich_config = function(old_config, on_config)
            local new_config = vim.deepcopy(old_config)

            -- TODO: cortex-debug/src/frontend/dconfigprovider.ts


            -- Makes no sense to glob recursively as this could be slow, let user specify the file manually in launch.json
            -- if not final.svdFile then
            --     vim.fn.glob('./**/*.svd')
            --     -- final.svdFile
            -- end

            if new_config.rtos then
                new_config.rtos = resolve_rtos(new_config)
            end

            -- TODO: cannot pass a function here
            -- -- cortex-debug/src/gdb.ts:511
            -- assert(not new_config.gdbServerConsolePort)
            -- new_config.gdbServerConsolePort = gdb_server.gdbServerConsolePort()

            -- needed for cortex-debug/src/gdb.ts:844
            if not new_config.extensionPath then
                new_config.extensionPath = extension_path
            end

            on_config(new_config)
        end
    }
end

function M.rtt_config(channels)
    if type(channels) ~= 'table' then
        channels = { channels }
    end
    return {
        enabled = #channels > 0,
        address = 'auto',
        rtt_start_retry = 1000,
        decoders = vim.tbl_map(function(channel)
            local port = channel
            local typ = 'console'
            if type(channel) == 'table' then
                port = channel.port
                typ = channel.type
            end
            return {
                label = 'RTT:' .. port,
                port = port,
                type = typ,
            }
        end, channels),
    }
end

function M.launch_config(opts, overrides)
    local defaults = {
        type = 'cortex-debug',
        request = 'attach',
        servertype = 'jlink',
        interface = 'jtag',

        -- we get error if not provided
        preAttachCommands = {},
        postAttachCommands = {},

        serverpath = 'JLinkGDBServerCLExe',
        gdbPath = 'arm-none-eabi-gdb',
        armToolchainPath = '/usr/bin',
        toolchainPrefix = 'arm-none-eabi',

        runToEntryPoint = 'main',

        -- Use dap events to spawn console
        gdbServerConsolePort = gdb_server.gdbServerConsolePort(),

        swoConfig = { enabled = false },

        rttConfig = M.rtt_config(),

    }
    return vim.tbl_extend('force',
        vim.tbl_extend('error', defaults, opts or {}),
        overrides or {}
    )
end

return M
