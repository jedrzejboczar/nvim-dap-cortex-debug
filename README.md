[![Lint](https://github.com/jedrzejboczar/nvim-dap-cortex-debug/actions/workflows/lint.yml/badge.svg)](https://github.com/jedrzejboczar/nvim-dap-cortex-debug/actions/workflows/lint.yml)

# nvim-dap-cortex-debug

An extension for [nvim-dap](https://github.com/mfussenegger/nvim-dap) providing integration with VS Code's [cortex-debug](https://github.com/Marus/cortex-debug) debug adapter.

> 🚧 This is currently a work in progress. While it should be usable, some features may be missing,
> some APIs may change. Feel free to open issues for bugs/missing features (PRs welcome).

## Features

- [x] Launch nvim-dap sessions using cortex-debug's `launch.json`
- [x] Support J-Link and OpenOCD
- [ ] Support other GDB servers (#mightwork)
- [x] Globals and Static variable scopes
- [x] Cortex Core Register Viewer (shown under "Registers" scope)
- [ ] Peripheral Register Viewer from SVD file
- [ ] SWO decoding
- [x] SEGGER RTT using OpenOCD/J-Link (currently only "console")
- [x] Raw Memory Viewer
- [ ] Dissassembly viewer
- [ ] RTOS support
- [ ] Integration with [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) (requires minor changes in nvim-dap-ui)

## Installation

Requirements:

* [cortex-debug](https://github.com/Marus/cortex-debug)
* [node](https://nodejs.org/en/) (to start cortex-debug)
* [appropriate toolchain and debugger](https://github.com/Marus/cortex-debug#installation)

To use this plugin you must first install [cortex-debug](https://github.com/Marus/cortex-debug) VS Code extension.
Simplest way is to install it from VS Code and point `extension_path` to appropriate location.
Other options include downloading the extension from [releases](https://github.com/Marus/cortex-debug/releases)
and unzipping the `.vsix` file (it is just a zip archive) or
[cloning the repo and building from sources](https://github.com/Marus/cortex-debug#how-to-build-from-sources).

Make sure that the `extension_path` (see [Configuration](#configuration)) is correct.
It should be the path to the directory in which `dist/debugadapter.js` is located.
In most cases the directory will be named `marus25.cortex-debug-x.x.x` (so there should be a
`marus25.cortex-debug-x.x.x/dist/debugadapter.js` file).

Example using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use { 'jedrzejboczar/nvim-dap-cortex-debug', requires = 'mfussenegger/nvim-dap' }
```

## Configuration

Call `require('dap-cortex-debug').setup { ... }` in your config.
Available options (with default values):

```lua
require('dap-cortex-debug').setup {
    debug = false,  -- log debug messages
    -- path to cortex-debug extension, supports vim.fn.glob
    extension_path = (is_windows() and '$USERPROFILE' or '~')
        .. '/.vscode/extensions/marus25.cortex-debug-*/',
    lib_extension = nil, -- tries auto-detecting, e.g. 'so' on unix
    node_path = 'node', -- path to node.js executable
}
```

This will configure nvim-dap adapter (i.e. assign to `dap.adapters['cortex-debug']`) and set up required nvim-dap listeners.

Now define nvim-dap configuration for debugging, the format is the same as for
[cortex-debug](https://github.com/Marus/cortex-debug/blob/master/debug_attributes.md).
You can use a `launch.json` file (see
[nvim-dap launch.json](https://github.com/mfussenegger/nvim-dap/blob/e71da68e59eec1df258acac20dad206366506438/doc/dap.txt#L276)
for details) or define the configuration in Lua.
When writing the configuration in Lua you may write the whole table manually or use one of the helper functions defined in
[dap-cortex-debug.lua](https://github.com/jedrzejboczar/nvim-dap-cortex-debug/blob/master/lua/dap-cortex-debug.lua) which sets
up some default values that get overwritten by the passed table, e.g.


```lua
local dap_cortex_debug = require('dap-cortex-debug')
require('dap').configurations.c = {
    dap_cortex_debug.openocd_config {
        name = 'Example debugging with OpenOCD',
        cwd = '${workspaceFolder}',
        executable = '${workspaceFolder}/build/app',
        configFiles = { '${workspaceFolder}/build/openocd/connect.cfg' },
        gdbTarget = 'localhost:3333',
        rttConfig = dap_cortex_debug.rtt_config(0),
        showDevDebugOutput = false,
    },
}
```

<p>
<details>
<summary style='cursor: pointer'>which should be equivalent to the following:</summary>

```lua
local dap_cortex_debug = require('dap-cortex-debug')
require('dap').configurations.c = {
    {
        name = 'Example debugging with OpenOCD',
        type = 'cortex-debug',
        request = 'launch',
        servertype = 'openocd',
        serverpath = 'openocd',
        gdbPath = 'arm-none-eabi-gdb',
        toolchainPath = '/usr/bin',
        toolchainPrefix = 'arm-none-eabi',
        runToEntryPoint = 'main',
        swoConfig = { enabled = false },
        showDevDebugOutput = false,
        gdbTarget = 'localhost:3333',
        cwd = '${workspaceFolder}',
        executable = '${workspaceFolder}/build/app',
        configFiles = { '${workspaceFolder}/build/openocd/connect.cfg' },
        rttConfig = {
            address = 'auto',
            decoders = {
                {
                    label = 'RTT:0',
                    port = 0,
                    type = 'console'
                }
            },
            enabled = true
        },
    }
}
```

</details>
</p>

GDB server output can be seen in `cotex-debug://gdb-server-console` buffer. It is hidden by default,
use `:buffer` or some buffer picker to open it. If RTT logging is enabled, a terminal buffer with
the output will be opened (with the name `cortex-debug://rtt:PORT` where `PORT` is `rttConfig.decoders[i].port`).

## Implementation notes

[cortex-debug](https://github.com/Marus/cortex-debug) implements
[Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/specification) server,
so it should be possible to use it with [nvim-dap](https://github.com/mfussenegger/nvim-dap)
which is a DAP client. However, there are some extensions to DAP that cortex-debug uses, which have
to be implemented separately to make it work with nvim-dap.

Cortex-debug [is split into two parts](https://github.com/Marus/cortex-debug#how-to-debug): frontend
and backend. Backend is what acts as DAP server and does most of the job, fronted is mostly used for
preparing configuration data and implementing additional functionality like RTT logging or SVD viewer.
For more details see [Cortex Debug: Under the hood](https://github.com/Marus/cortex-debug/wiki/Cortex-Debug:-Under-the-hood).

This plugin tries to reimplement cortex-debug frontend. It:

* takes the launch configuration, fills in missing keys, sets default values and checks config correctness;
  see `adapter.lua` (backend expects a complete configuration - no missing values)
* starts a server to which the output from gdb-server will be sent; this output is displayed in a terminal buffer
  (`cortex-debug://gdb-server-console`)
* if RTT is enabled, the plugin connects via TCP and shows RTT output in a terminal buffer
* hooks into nvim-dap event/command listeners to handle cortex-debug's custom events and fix some existing
  incompatibilities

Implementing a missing cortex-debug feature most likely requires implementing some of the custom events
and displaying the output in Neovim buffers.
