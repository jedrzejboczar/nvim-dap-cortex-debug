local config = require('dap-cortex-debug.config')
local consoles = require('dap-cortex-debug.consoles')
local utils = require('dap-cortex-debug.utils')

local valid_rtos = {
    jlink = { 'Azure', 'ChibiOS', 'embOS', 'FreeRTOS', 'NuttX', 'Zephyr' },
    openocd = { 'ChibiOS', 'eCos', 'embKernel', 'FreeRTOS', 'mqx', 'nuttx', 'ThreadX', 'uCOS-III', 'auto' },
}

local function veirify_jlink_config(c)
    if not c.interface then
        c.interface = 'swd'
    end

    utils.assert(
        c.device,
        'Device Identifier is required for J-Link configurations. '
            .. 'Please see https://www.segger.com/downloads/supported-devices.php for supported devices'
    )

    utils.assert(
        not (
                vim.tbl_contains({ 'jtag', 'cjtag' }, c.interface)
                and c.swoConfig.enabled
                and c.swoConfig.source == 'probe'
            ),
        'SWO Decoding cannot be performed through the J-Link Probe in JTAG mode.'
    )

    local count = 0
    for _, decoder in ipairs(c.rttConfig.decoders) do
        utils.assert(
            decoder.port >= 0 and decoder.port <= 15,
            'Invalid RTT port %s, must be between 0 and 15.',
            decoder.port
        )
        count = count + 1
    end

    utils.assert(count < 2, 'JLink RTT only allows a single RTT port/channel per debugging session but got %s', count)

    if c.rtos then
        local valid = valid_rtos.jlink
        if vim.tbl_contains(valid, c.rtos) then
            c.rtos = string.format('GDBServer/RTOSPlugin_%s.%s', c.rtos, utils.get_lib_ext())
        else
            if vim.fn.fnamemodify(c.rtos, ':e') == '' then
                c.rtos = c.rtos .. '.' .. utils.get_lib_ext()
            end
            utils.assert(
                vim.fn.filereadable(c.rtos),
                'JLink RTOS plugin file not found: "%s". Supported RTOS values: %s. Or use full path to JLink plugin.',
                c.rtos,
                table.concat(valid, ', ')
            )
        end
    end

    return c
end

local function veirify_openocd_config(c)
    utils.assert(c.configFiles and #c.configFiles > 0, 'At least one OpenOCD Configuration File must be specified.')
    c.searchDir = c.searchDir or {}

    if c.rtos then
        local valid = valid_rtos.openocd
        utils.assert(
            vim.tbl_contains(valid, c.rtos),
            'Invalid RTOS for %s, available: %s',
            c.servertype,
            table.concat(valid, ', ')
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
        vscode = 'vscode',
    }
    if type(c.showDevDebugOutput) == 'string' then
        c.showDevDebugOutput = vim.trim(c.showDevDebugOutput:lower())
    end
    if vim.tbl_contains({ false, 'false', '', 'none' }, c.showDevDebugOutput) then
        c.showDevDebugOutput = nil
    elseif vim.tbl_contains({ true, 'true' }, c.showDevDebugOutput) then
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
        local old_value = vim.tbl_get(c, unpack(old_path))
        utils.assert(old_value == nil, '"%s" is not supported, use "%s"', old, new)
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
        cwd = vim.fn.getcwd(),
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

    c.runToEntryPoint = c.runToEntryPoint and vim.trim(c.runToEntryPoint)

    if c.servertype ~= 'openocd' or not vim.tbl_get(c, 'ctiOpenOCDConfig', 'enabled') then
        c.ctiOpenOCDConfig = nil
    end

    sanitize_dev_debug(c)

    -- Warn because it might be confusing
    if vim.endswith(c.toolchainPrefix, '-') then
        utils.warn_once('toolchainPrefix should not end with "-", e.g. "arm-none-eabi"')
    end

    local verify = utils.assert(verifiers[c.servertype], 'Unsupported servertype: %s', c.servertype)
    c = verify(c)

    if platform == 'windows' then
        -- This is passed to GDB so must use forward slash instead of backslash
        c.extensionPath = c.extensionPath:gsub([[\]], '/')
        c.executable = c.executable:gsub([[\]], '/')
    end

    return c
end

---Debug adapter configuration in functional variant; assignable to dap.adapters[...]
---@param callback function
---@param launch_config table
local function adapter_fn(callback, launch_config)
    -- Currently it's not strictly necessary to use functional variant, but we'll see...
    local extension_path = launch_config.extensionPath or utils.get_extension_path()
    if not extension_path then
        utils.error('Missing cortex-debug extension_path')
    end
    launch_config.extensionPath = extension_path

    -- Ensure GDB server console has been started
    local port = consoles.gdb_server_console(launch_config.dbgServerLogfile).port

    callback {
        type = 'executable',
        command = config.node_path,
        args = { utils.get_debugadapter_path(extension_path) },
        options = { detached = false },
        enrich_config = function(conf, on_config)
            local ok, conf_or_err = utils.trace_pcall(verify_config, vim.deepcopy(conf))
            if ok then
                conf = conf_or_err
            else
                utils.error('Launch config error: %s', conf_or_err)
                return false
            end

            conf.gdbServerConsolePort = port

            on_config(conf)
        end,
    }
end

return adapter_fn
