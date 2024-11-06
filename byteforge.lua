require 'io'
local ffi = require 'ffi'
local bit = require 'bit'
require 'xtbl'
local xbyte = require 'xbyte'

local BytePlatform = {
    Linux = 0,
    Windows = 1
}

local ByteError = {
    ERROR_UNKNOWN = -1,
    ERROR_INVALID_HANDLE = -2,
}
local lib = {}

function lib:create(platform)
    self.platform = platform
    if platform == BytePlatform.Linux then
        ffi.cdef [[
            long ptrace(int request, int pid, void *addr, void *data);

            int waitpid(int pid, int* stat, int options);

            enum {
                PTRACE_TRACEME = 0,
                PTRACE_PEEKTEXT = 1,
                PTRACE_PEEKDATA = 2,
                PTRACE_PEEKUSER = 3,
                PTRACE_POKETEXT = 4,
                PTRACE_POKEDATA = 5,
                PTRACE_POKEUSER = 6,
                PTRACE_CONT = 7,
                PTRACE_KILL = 8,
                PTRACE_SINGLESTEP = 9,
                PTRACE_ATTACH = 16,
                PTRACE_DETACH = 17
            };]]
        -- load the c standard library
        self.libc = ffi.load("c")
    end
end

function lib:getpid(process_name)
    if self.platform == BytePlatform.Linux then
        local handle = io.popen("pgrep " .. process_name)
        if handle then
            local pid = handle:read("*a")
            handle:close()
            return pid
        else
            return ByteError.ERROR_INVALID_HANDLE
        end
    end
end

function lib:get_base(pid, config)
    if self.platform == BytePlatform.Linux then
        local maps_file = string.format("/proc/%d/maps", pid)
        local file = io.open(maps_file, "r")

        if not file then
            print("Error operning file: " .. maps_file)
            return nil
        end
        local config = config or {}
        -- get the default executable start
        local kind = config.kind or "r--p"
        local base = nil
        for line in file:lines() do
            if line:find(kind) and line:find("/") then
                base = line:match("^(%x+)")
                base = tonumber(base, 16)
                break
            end
        end
        file:close()
        return base
    end
end

-- you need to attach for read & write on linux
-- open process on windows too i guess
function lib:attach(pid)
    local result = nil
    if self.platform == BytePlatform.Linux then
        result = self.libc.ptrace(ffi.C.PTRACE_ATTACH, pid, ffi.cast("void*", 0), ffi.cast("void*", 0))
        -- wait for the process to be in a stable state
        if result > -1 then
            result = self.libc.waitpid(pid, ffi.cast("void*", 0), 0)
        else
            -- replace with perror
            return nil
        end
    end
    return result
end

function lib:detach(pid)
    local result = nil
    if self.platform == BytePlatform.Linux then
        result = self.libc.ptrace(ffi.C.PTRACE_DETACH, pid, ffi.cast("void*", 0), ffi.cast("void*", 0))
    end
    return result
end

function lib:read(pid, addr, config)
    local result = nil
    if self.platform == BytePlatform.Linux then
        local config = config or {}
        local size = config.size or ffi.sizeof("long")

        -- ptrace only allows to read words so we gotta trick it
        local words = math.ceil(size / ffi.sizeof("long"))
        local bytes = {}

        for i = 0, words - 1 do
            local word = self.libc.ptrace(ffi.C.PTRACE_PEEKDATA, pid, ffi.cast("void*", addr + i * ffi.sizeof("long")),
                nil)
            if word == -1 then
                print("Failed to read memory")
                return nil
            end

            -- Calculate number of bytes to copy from this word
            local nbytes = ffi.sizeof("long")
            if i == words - 1 then
                -- If it's the last word, only copy the remaining bytes we need
                nbytes = size % ffi.sizeof("long")
                if nbytes == 0 then
                    nbytes = ffi.sizeof("long")
                end
            end

            -- Copy each byte from the word into the bytes table
            for j = 0, nbytes - 1 do
                local byte = tonumber(bit.band(bit.rshift(word, j * 8), 0xFF)) -- Extract byte `j` from `word`
                table.insert(bytes, byte)
            end
        end

        result = bytes
    end
    return result
end

local function packBytesToLong(bytes)
    local long_size = ffi.sizeof("long")
    if #bytes ~= long_size then
        error("Input table must contain exactly " .. long_size .. " bytes.")
    end

    local longValue = 0
    for i = 1, long_size do
        if bytes[i] < 0 or bytes[i] > 255 then
            error("Each byte must be between 0 and 255.")
        end
        longValue = longValue + bit.lshift(bytes[i], (long_size - i) * 8)
    end
    return longValue
end


function lib:write_bytes(pid, addr, data, config)
    local result = nil
    if self.platform == BytePlatform.Linux then
        -- should be 8 on x64 systems
        local long_size = ffi.sizeof("long")
        local ret = {}
        -- length of the bytes
        local config = {}
        local length = config.size or #data
        -- number of longs we need to fit our data in
        local longs = math.ceil(length / long_size)
        print(" we need "..longs.." longs")
        -- the bytes we shoudln't touch
        local unaligned = length % long_size
        -- the number of bytes that we need to edit on the last word
        local untouched = 8 - unaligned

        print("untouched : " .. untouched, " vs unaligned " .. unaligned)
        -- we have a round number of filled bytes
        local maxidx = longs
        if unaligned > 0 then
            -- we don't, the last byte is not filled
            maxidx = longs - 1
        end

        for i = 1, maxidx do
            local val = xbyte.bytes2int64(table.slice(data, (i - 1) * long_size, i * long_size))
            self.libc.ptrace(ffi.C.PTRACE_POKEDATA, pid, ffi.cast("void*", addr + (0x8 * (i - 1))), ffi.cast("void*", val))
        end

        if unaligned > 0 then
            print("so real")

            local orig_word = lib:read(pid, addr + 0x8 * (longs - 1), {size=8})
            print(table.concat(orig_word, ":"))
            if orig_word then
                for i = 1, unaligned do
                    orig_word[i] = data[#data - unaligned + i]
                    print(table.concat(orig_word, ','))
                end
            else
                error(string.format("Failed to read address 0x%x", addr + 0x8 * longs))
                return -1
            end
            self.libc.ptrace(ffi.C.PTRACE_POKEDATA, pid, ffi.cast("void*", addr + 0x8 * (longs - 1)), ffi.cast("void*", xbyte.bytes2int64(orig_word)))
            --write(0x00 + 8 * longs, xbyte.bytes2int64(orig_word))
        end
        result = 1
    end
    return result
end

function lib:getversion()
    return "0.0.2-beta"
end

return lib
