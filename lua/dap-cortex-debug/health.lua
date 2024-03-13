local M = {}

local config = require('dap-cortex-debug.config')
local utils = require('dap-cortex-debug.utils')

function M.check()
    vim.health.start('nvim-dap-cortex-debug')

    if vim.fn.executable(config.node_path) == 1 then
        local ok, version = pcall(vim.fn.system, 'node --version')
        if ok and version then
            vim.health.ok('Node.js installed: ' .. vim.trim(version))
        else
            vim.health.error('Node.js executable but `node --version` failed')
        end
    else
        vim.health.error('Node.js not installed')
    end

    local extension_path = utils.get_extension_path()
    if extension_path and vim.fn.isdirectory(extension_path) == 1 then
        vim.health.ok('cortex-debug extension found: ' .. extension_path)

        local debugadapter_path = utils.get_debugadapter_path(extension_path)
        if vim.fn.filereadable(debugadapter_path) == 1 then
            vim.health.ok('Found debugadapter.js: ' .. debugadapter_path)
        else
            vim.health.error('debugadapter.js not found: ' .. debugadapter_path)
        end
    elseif extension_path then
        vim.health.error('cortex-debug extension path not a directory: ' .. extension_path)
    else
        vim.health.error('cortex-debug extension not found')
    end
end

return M
