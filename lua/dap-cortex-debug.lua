local M = {}

local dap = require('dap')
local config = require('dap-cortex-debug.config')
local listeners = require('dap-cortex-debug.listeners')
local adapter = require('dap-cortex-debug.adapter')
local memory = require('dap-cortex-debug.memory')
local utils = require('dap-cortex-debug.utils')

function M.setup(opts)
    config.setup(opts)
    listeners.setup()

    -- TODO: is this necessary?
    dap.defaults['cortex-debug'].auto_continue_if_many_stopped = false

    -- Could be a function(cb, config) to auto-generate docker command arguments
    dap.adapters['cortex-debug'] = adapter

    -- TODO: completion of variable names that maps them to address?
    -- TODO: handle mods for location of window
    vim.api.nvim_create_user_command('CDMemory', function(o)
        local address = utils.assert(tonumber(o.fargs[1]), 'Incorrect `address`: %s', o.fargs[1])
        local length = utils.assert(tonumber(o.fargs[2]), 'Incorrect `length`: %s', o.fargs[1])
        memory.show(address, length, { id = o.count })
    end, { desc = 'Open memory viewer', nargs = '+', range = 1 })
end

---@class RTTChannel
---@field port number
---@field type "console"|"binary"

---Generate basic RTT configuration with decoders for given channels
---@param channels? number|number[]|RTTChannel[] Channels to use
---@return table Configuration assignable to "rttConfig" field
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

function M.jlink_config(overrides)
    local defaults = {
        type = 'cortex-debug',
        request = 'attach',
        servertype = 'jlink',
        interface = 'jtag',
        serverpath = 'JLinkGDBServerCLExe',
        gdbPath = 'arm-none-eabi-gdb',
        toolchainPath = '/usr/bin',
        toolchainPrefix = 'arm-none-eabi',
        runToEntryPoint = 'main',
        swoConfig = { enabled = false },
        rttConfig = M.rtt_config(),
    }
    return vim.tbl_deep_extend('force', defaults, overrides)
end

function M.openocd_config(overrides)
    local defaults = {
        type = 'cortex-debug',
        request = 'launch',
        servertype = 'openocd',
        serverpath = 'openocd',
        gdbPath = 'arm-none-eabi-gdb',
        toolchainPath = '/usr/bin',
        toolchainPrefix = 'arm-none-eabi',
        runToEntryPoint = 'main',
        swoConfig = { enabled = false },
        rttConfig = M.rtt_config(),
    }
    return vim.tbl_deep_extend('force', defaults, overrides)
end

return M
