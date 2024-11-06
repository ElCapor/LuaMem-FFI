local ffi = require 'ffi'
local xbyte = {}

-- todo: use int32_t if long is 32 bits
function xbyte.bytes2int64(bytes)
    assert(#bytes == 8, "Expected 8 bytes to pack into a 64-bit integer")

    -- luajit bit operator doesnt support 64 bit, so we have to use ffi
    local result = ffi.new("int64_t", 0)

    -- Ppack each byte
    for i = 1, 8 do
        result = result + ffi.new("int64_t", bytes[i]) * (2 ^ ((8 - i) * 8))
    end

    return result
end

function xbyte.bytes2type(bytes, type_name)
    local type_size = ffi.sizeof(type_name)
    assert(#bytes == type_size, "Expected " .. type_size .. " bytes to pack into a " .. type_name)

    local result = ffi.new(type_name, 0)

    for i = 1, type_size do
        result = result + ffi.new(type_name, bytes[i]) * (2 ^ ((type_size - i) * 8))
    end

    return result
end


function xbyte.int642bytes(val)
    local int64_value = ffi.cast("int64_t", val);
    local bytes = {}

    for i = 8, 1, -1 do
        -- Extract the least significant byte
        bytes[i] = tonumber(int64_value % 256)
        -- Shift right by 8 bits for the next byte
        int64_value = int64_value / 256
    end

    return bytes
end

return xbyte