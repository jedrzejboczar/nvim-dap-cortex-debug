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
        black = M.escape_sequence('[30'),
        red = M.escape_sequence('[31'),
        green = M.escape_sequence('[32'),
        yellow = M.escape_sequence('[33'),
        blue = M.escape_sequence('[34'),
        magenta = M.escape_sequence('[35'),
        cyan = M.escape_sequence('[36'),
        white = M.escape_sequence('[37'),
        bright_black = M.escape_sequence('[90'),
        bright_red = M.escape_sequence('[91'),
        bright_green = M.escape_sequence('[92'),
        bright_yellow = M.escape_sequence('[93'),
        bright_blue = M.escape_sequence('[94'),
        bright_magenta = M.escape_sequence('[95'),
        bright_cyan = M.escape_sequence('[96'),
        bright_white = M.escape_sequence('[97'),
    },
    bg = {
        black = M.escape_sequence('[40'),
        red = M.escape_sequence('[41'),
        green = M.escape_sequence('[42'),
        yellow = M.escape_sequence('[43'),
        blue = M.escape_sequence('[44'),
        magenta = M.escape_sequence('[45'),
        cyan = M.escape_sequence('[46'),
        white = M.escape_sequence('[47'),
        bright_black = M.escape_sequence('[100'),
        bright_red = M.escape_sequence('[101'),
        bright_green = M.escape_sequence('[102'),
        bright_yellow = M.escape_sequence('[103'),
        bright_blue = M.escape_sequence('[104'),
        bright_magenta = M.escape_sequence('[105'),
        bright_cyan = M.escape_sequence('[106'),
        bright_white = M.escape_sequence('[107'),
    },
}

return M
