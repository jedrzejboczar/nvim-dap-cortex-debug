local config = require('dap-cortex-debug.config')
local gdb_server = require('dap-cortex-debug.gdb_server')
local utils = require('dap-cortex-debug.utils')

local function get_extension_path()
    if config.extension_path and vim.fn.isdirectory(config.extension_path) then
        return utils.path_sanitize(config.extension_path)
    end
    local paths = vim.fn.glob(config.extension_path_glob, false, true)
    if paths and paths[1] then
        return utils.path_sanitize(paths[1])
    end
    utils.warn_once('Missing cortex-debug extension_path')
end

local function get_debugadapter_path(extension_path)
    -- TODO: does this solve Windows compatibility?
    local paths = vim.fn.glob(extension_path .. '/dist/debugadapter.js', true, true)
    return paths and utils.path_sanitize(paths[1])
end

local valid_rtos = {
    jlink = { 'Azure', 'ChibiOS', 'embOS', 'FreeRTOS', 'NuttX', 'Zephyr' },
    openocd = { 'ChibiOS', 'eCos', 'embKernel', 'FreeRTOS', 'mqx', 'nuttx', 'ThreadX', 'uCOS-III', 'auto' },
}

local function resolve_rtos(conf)
    if valid[conf.servertype] then
        -- TODO: openocd support
        if conf.servertype == 'jlink' then
            return string.format('GDBServer/RTOSPlugin_%s.%s', conf.rtos, utils.get_lib_ext())
        end
    end
    utils.warn('Could not resolve RTOS "%s"', conf.rtos)
end

local function veirify_jlink_config(c)
    if not c.interface then
        c.interface = 'swd'
    end

    assert(c.device, 'Device Identifier is required for J-Link configurations. Please see https://www.segger.com/downloads/supported-devices.php for supported devices')

    assert(
        not (vim.tbl_contains({'jtag', 'cjtag'}, c.interface) and c.swoConfig.enabled and c.swoConfig.source == 'probe'),
        'SWO Decoding cannot be performed through the J-Link Probe in JTAG mode.'
    )

    local count = 0
    for _, decoder in ipairs(c.rttConfig.decoders) do
        assert(
            decoder.port >= 0 and decoder.port <= 15,
            string.format('Invalid RTT port %s, must be between 0 and 15.', decoder.port)
        )
        count = count + 1
    end

    assert(count < 2, 'JLink RTT only allows a single RTT port/channel per debugging session but got ' .. count)

    if c.rtos then
        -- TODO: allow arbitrary paths
        assert(
            valid_rtos.jlink[c.rtos],
            string.format('Invalid RTOS for %s, available: %s', c.servertype, table.concat(valid_rtos.jlink, ', '))
        )

        if not vim.fn.filereadable(c.rtos) then
            utils.warn('jlink RTOS plugin file not readable: ' .. c.rtos)
        end
    end


    c.rtos = string.format('GDBServer/RTOSPlugin_%s.%s', c.rtos, utils.get_lib_ext())

    return c
end

local function veirify_openocd_config(c)
    assert(c.configFiles and #c.configFiles > 0, 'At least one OpenOCD Configuration File must be specified. ')
    c.searchDir = c.searchDir or {}

    if c.rtos then
        assert(
            valid_rtos.jlink[c.rtos],
            string.format('Invalid RTOS for %s, available: %s', c.servertype, table.concat(valid_rtos.jlink, ', '))
        )
    end

    return c
end

local verifiers = {
    jlink = veirify_jlink_config,
    openocd = veirify_openocd_config,
}

local function sanitize_dev_debug(c)
    local modes = {
        none = 'none',
        parsed = 'parsed',
        both = 'both',
        raw = 'raw',
        vscode = 'vscode'
    }
    if type(c.showDevDebugOutput) == 'string' then
        c.showDevDebugOutput = vim.trim(c.showDevDebugOutput:lower())
    end
    if vim.tbl_contains({false, 'false', '', 'none'}, c.showDevDebugOutput) then
        c.showDevDebugOutput = nil
    elseif vim.tbl_contains({true, 'true'}, c.showDevDebugOutput) then
        c.showDevDebugOutput = modes.raw
    elseif not modes[c.showDevDebugOutput] then
        c.showDevDebugOutput = 'vscode'
    end
end

-- Imitate cortex-debug/src/frontend/configprovider.ts
local function verify_config(c)
    -- Flatten platform specific config
    local platform = utils.get_platform()
    c = vim.tbl_extend('force', c, c[platform] or {})
    c[platform] = nil

    -- There is some code that makes sure to resolve deprecated options but we won't support this.
    local assert_deprecated = function(old, new)
        local old_path = vim.split(old, '.', { plain = true })
        local msg = string.format('"%s" is not supported, use "%s"', old, new)
        assert(vim.tbl_get(c, unpack(old_path)) == nil, msg)
    end
    assert_deprecated('debugger_args', 'debuggerArgs')
    assert_deprecated('swoConfig.ports', 'swoConfig.decoders')
    assert_deprecated('runToMain', 'runToEntryPoint = "main"')
    assert_deprecated('armToolchainPath', 'toolchainPath')
    assert_deprecated('jlinkpath', 'serverpath')
    assert_deprecated('jlinkInterface', 'interface')
    assert_deprecated('openOCDPath', 'serverpath')

    -- TODO: pvtAvoidPorts
    -- TODO: chained configs?

    -- Ensure that following keys exist even if not provided or debug adapter may fail
    local defaults = {
        debuggerArgs = {},
        swoConfig = { enabled = false, decoders = {}, cpuFrequency = 0, swoFrequency = 0, source = 'probe' },
        rttConfig = { enabled = false, decoders = {} },
        graphConfig = {},
        preLaunchCommands = {},
        postLaunchCommands = {},
        preAttachCommands = {},
        postAttachCommands = {},
        preRestartCommands = {},
        postRestartCommands = {},
        toolchainPrefix = 'arm-none-eabi',
        registerUseNaturalFormat = true,
        variableUseNaturalFormat = true,
    }
    c = vim.tbl_deep_extend('keep', c, defaults)

    c.runToEntryPoint = vim.trim(c.runToEntryPoint)

    if c.servertype ~= 'openocd' or not vim.tbl_get(c, 'ctiOpenOCDConfig', 'enabled') then
        c.ctiOpenOCDConfig = nil
    end

    sanitize_dev_debug(c)

    -- Warn because it might be confusing
    if vim.endswith(c.toolchainPrefix, '-') then
        utils.warn_once('toolchainPrefix should not end with "-", e.g. "arm-none-eabi"')
    end

    if c.rtos and valid_rtos[c.servertype] then
        local valid = valid_rtos[c.servertype]
        assert(valid[c.rtos], string.format('Invalid RTOS for %s, available: %s', c.servertype, table.concat(valid, ', ')))
    end

    local verify = assert(verifiers[c.servertype], 'Unsupported servertype: ' .. c.servertype)
    c = verify(c)

    return c
end

---Debug adapter configuration in functional variant; assignable to dap.adapters[...]
---@param callback function
---@param launch_config table
---@return function
local function adapter_fn(callback, launch_config)
    -- Currently it's not strictly necessary to use functional variant, but we'll see...
    local extension_path = launch_config.extensionPath or get_extension_path()
    launch_config.extensionPath = extension_path

    callback {
        type = 'executable',
        command = 'node',
        args = { get_debugadapter_path(extension_path) },
        options = { detached = false, },
        enrich_config = function(conf, on_config)
            local ok, conf_or_err = pcall(verify_config, vim.deepcopy(conf))
            if ok then
                conf = conf_or_err
            else
                utils.error('invalid launch config: %s', conf_or_err)
                return false
            end

            -- Start GDB server console before we launch debug adapter
            conf.gdbServerConsolePort = utils.get_free_port(55878)
            gdb_server.start(conf.gdbServerConsolePort)

            on_config(conf)
        end
    }
end

return adapter_fn
