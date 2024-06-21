local M = {}

function M.escape_sequence(seq)
    -- In lua this decimal, so it's the equivalent of the usual \033 (octal)
    return '\027' .. seq
end

-- See: https://en.wikipedia.org/wiki/ANSI_M.escape_code
-- PERF: could merge multiple into one when needed, like "[1;31m"; probably not worth it
---@class CDTerminalDisplay
M.display = {
    reset = M.escape_sequence('[0m'),
    clear = M.escape_sequence('[0m'),
    bold = M.escape_sequence('[1m'),
    dim = M.escape_sequence('[2m'),
    italic = M.escape_sequence('[2m'),
    underline = M.escape_sequence('[2m'),
    fg = {
        black = M.escape_sequence('[30m'),
        red = M.escape_sequence('[31m'),
        green = M.escape_sequence('[32m'),
        yellow = M.escape_sequence('[33m'),
        blue = M.escape_sequence('[34m'),
        magenta = M.escape_sequence('[35m'),
        cyan = M.escape_sequence('[36m'),
        white = M.escape_sequence('[37m'),
        bright_black = M.escape_sequence('[90m'),
        bright_red = M.escape_sequence('[91m'),
        bright_green = M.escape_sequence('[92m'),
        bright_yellow = M.escape_sequence('[93m'),
        bright_blue = M.escape_sequence('[94m'),
        bright_magenta = M.escape_sequence('[95m'),
        bright_cyan = M.escape_sequence('[96m'),
        bright_white = M.escape_sequence('[97m'),
    },
    bg = {
        black = M.escape_sequence('[40m'),
        red = M.escape_sequence('[41m'),
        green = M.escape_sequence('[42m'),
        yellow = M.escape_sequence('[43m'),
        blue = M.escape_sequence('[44m'),
        magenta = M.escape_sequence('[45m'),
        cyan = M.escape_sequence('[46m'),
        white = M.escape_sequence('[47m'),
        bright_black = M.escape_sequence('[100m'),
        bright_red = M.escape_sequence('[101m'),
        bright_green = M.escape_sequence('[102m'),
        bright_yellow = M.escape_sequence('[103m'),
        bright_blue = M.escape_sequence('[104m'),
        bright_magenta = M.escape_sequence('[105m'),
        bright_cyan = M.escape_sequence('[106m'),
        bright_white = M.escape_sequence('[107m'),
    },
}

return M
