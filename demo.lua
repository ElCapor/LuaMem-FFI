local lib = require("byteforge")

-- create an instance of the library for linux
-- 0 = Linux; 1 = Windows
lib:create(0)

-- PID for a test game i had
-- need to use to number because linux returns a str since it's posix
local pid = tonumber(lib:getpid("TestGame"))

-- offset for the score starting from the base of the exe
local score_offset = 0x10D404

-- get the base of the program
local program_base = lib:get_base(pid)

-- NOTE : This will start out from the first segment which is read only
-- if you want the executable segment then you gotta tell it to the lib.
-- linux only for now
-- lib:get_base(pid, {kind="r-xp"})

-- attach the pid (necessary)
lib:attach(pid)

--read the score from the game
-- lib:read query a single word from the memory by default, but you can tweak for n bytes
-- example below
local score = lib:read(pid, program_base + score_offset)

print(string.format("The score is 0x%x", score))

local instructions = 0x98F1

-- we want to read 6 bytes
local data = lib:read(pid, program_base+instructions, {size=6})

if data then
    for _,v in pairs(data) do
        print(string.format("Data 0x%x", v))
    end
end

-- detach or crash on linux
lib:detach(pid)

