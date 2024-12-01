---@param cfg BenchmarkConfig
---@return BenchmarkResult
local function benchmark(cfg, fn, ...)
    local mem_usage = 0
    local total_time = 0
    local count = 0

    local max_count = cfg.max_iterations - 1
    local min_time = cfg.min_time * 1e9
    local end_time = vim.uv.hrtime() + cfg.max_duration * 1e9
    while vim.uv.hrtime() < end_time and (count < max_count or total_time < min_time) do
        collectgarbage('collect')

        local mem_start = collectgarbage('count')
        local time_start = vim.uv.hrtime()
        fn(...)
        local time_end = vim.uv.hrtime()
        local mem_end = collectgarbage('count')

        total_time = total_time + (time_end - time_start)
        mem_usage = mem_usage + (mem_end - mem_start)
        count = count + 1
    end

    return {
        n = count,
        time = total_time,
        mem = mem_usage,
    }
end

local function human_size(size)
    local unit = 1
    local units = { '', 'K', 'M', 'G' }
    while unit < #units and size >= 1000 do
        size = size / 1024
        unit = unit + 1
    end
    return string.format('%6.2f %s', size, units[unit])
end

---@param name string
---@param result BenchmarkResult
local function summarize(name, input, result)
    return string.format(
        '%-16s %9.3f ms, %6.2f MB mem, %sB/s bw, %3d iters, %3.1f s total',
        name,
        result.time / 1e6 / result.n,
        result.mem / 1024 / result.n,
        human_size(#input.data / (result.time / 1e9)),
        result.n,
        result.time / 1e9
    )
end

--------------------------------------------------------------------------------

local impls = {}

-- function impls.iter1(data)
--     local chars = {}
--     for _, byte in ipairs(data) do
--         table.insert(chars, string.char(byte))
--     end
--     return table.concat(chars)
-- end
--
-- function impls.iter2(data)
--     local chars = {}
--     for _, byte in ipairs(data) do
--         chars[#chars + 1] = string.char(byte)
--     end
--     return table.concat(chars)
-- end

function impls.iter(data)
    local chars = {}
    for i, byte in ipairs(data) do
        chars[i] = string.char(byte)
    end
    return table.concat(chars)
end

function impls.unpack(data)
    local CHUNK = 7997
    local n = #data
    local got = 0
    local parts = {}
    while got < n do
        local chunk = math.min(CHUNK, n - got)
        table.insert(parts, string.char(unpack(data, got + 1, got + 1 + chunk - 1)))
        got = got + chunk
    end
    return table.concat(parts)
end

function impls.stringbuf(data)
    local stringbuffer = require('string.buffer')
    local n = #data
    local buf = stringbuffer.new(n)
    for i = 1, n do
        buf:put(string.char(data[i]))
    end
    return tostring(buf)
end

local cfg = { min_time = 0.5, max_duration = 3, max_iterations = 100 }
local lines = { 'Benchmark:' }

local KB, MB = 1024, 1024 * 1024
local counts = { small = 200, mid = 16 * KB, big = 2 * MB }
local inputs = {}
for count, n in pairs(counts) do
    local data = {}
    inputs[count] = { data = data }
    for _ = 1, n do
        table.insert(data, math.random(0, 255))
    end
end

for count, input in pairs(inputs) do
    for impl, fn in pairs(impls) do
        local name = table.concat({ count, impl }, '.')
        local result = benchmark(cfg, fn, input.data)
        table.insert(lines, '  ' .. summarize(name, input, result))
    end
end

print(table.concat(lines, '\n'))

-- Benchmark: (CHUNK=7997)
--   big.iter            46.924 ms,  17.75 MB mem,   1.52 MB/s bw,  28 iters, 1.3 s total
--   big.unpack           5.491 ms,   5.08 MB mem,   7.92 MB/s bw,  46 iters, 0.3 s total
--   big.stringbuf        6.088 ms,   4.00 MB mem,   7.14 MB/s bw,  46 iters, 0.3 s total
--   small.iter           0.037 ms,   0.00 MB mem, 102.57 KB/s bw,  51 iters, 0.0 s total
--   small.unpack         0.011 ms,   0.00 MB mem, 360.83 KB/s bw,  51 iters, 0.0 s total
--   small.stringbuf      0.008 ms,   0.00 MB mem, 459.16 KB/s bw,  51 iters, 0.0 s total
--   mid.iter             0.399 ms,   0.14 MB mem, 785.39 KB/s bw,  51 iters, 0.0 s total
--   mid.unpack           0.063 ms,   0.11 MB mem,   4.90 MB/s bw,  51 iters, 0.0 s total
--   mid.stringbuf        0.045 ms,   0.03 MB mem,   6.72 MB/s bw,  52 iters, 0.0 s total
