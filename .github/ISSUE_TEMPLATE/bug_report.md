---
name: Bug report
about: Something does not work correctly
title: ''
labels: bug
assignees: jedrzejboczar

---

**Describe the bug**

Describe the problem and what would be the expected behavior. Provide steps to reproduce the bug.

**Context**

Check the following things and provide them if there is something that might be helpful:

1. Provide your plugin config passed to `require('dap-cortex-debug').setup {}`
2. Run `:checkhealth dap-cortex-debug` and provide the output.
3. Provide DAP launch configuration (either `.vscode/launch.json` or directly in Lua)
4. Use `:DapSetLogLevel DEBUG`, then reproduce the issue. Attach the output of `:DapShowLog`. 
5. Use `require('dap-cortex-debug').setup { debug = true, ... }`, reproduce the issue and attach the output.
