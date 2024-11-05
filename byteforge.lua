require 'io'
local ffi = require 'ffi'

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
        ffi.cdef[[
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
            print("Error operning file: "..maps_file)
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
            result =  self.libc.waitpid(pid, ffi.cast("void*", 0), 0)
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

function lib:read(pid, addr)
    local result = nil
    if self.platform == BytePlatform.Linux then
        local data = self.libc.ptrace(ffi.C.PTRACE_PEEKDATA, pid, ffi.cast("void *", addr), nil)
        if data == -1 then
            print("Error read")
        end
        result = data
    end
    return result
end

function lib:getversion()
    return "0.0.1-beta"
end
return lib