local M = {}

local dap = require('dap')
local utils = require('dap-cortex-debug.utils')
local config = require('dap-cortex-debug.config')
local events = require('dap-cortex-debug.events')
local gdb_server = require('dap-cortex-debug.gdb_server')
local adapter = require('dap-cortex-debug.adapter')

function M.setup(opts)
    config.setup(opts)
    events.setup()

    -- TODO: is this necessary?
    dap.defaults['cortex-debug'].auto_continue_if_many_stopped = false

    -- Could be a function(cb, config) to auto-generate docker command arguments
    dap.adapters['cortex-debug'] = adapter
end

function M.rtt_config(channels)
    if type(channels) ~= 'table' then
        channels = { channels }
    end
    return {
        enabled = #channels > 0,
        address = 'auto',
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
        toolchainPath = '/usr/bin',
        toolchainPrefix = 'arm-none-eabi',

        runToEntryPoint = 'main',

        swoConfig = { enabled = false },

        rttConfig = M.rtt_config(),

    }
    return vim.tbl_extend('force',
        vim.tbl_extend('error', defaults, opts or {}),
        overrides or {}
    )
end

return M
