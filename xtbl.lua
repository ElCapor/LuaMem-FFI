-- extension to the lua table library
function table.slice(tbl, first, N)
    local sliced = {}
    local ix = first
    local last = math.min(ix + N, #tbl)
    while ix <= last do
        sliced[#sliced + 1] = tbl[ix]
        ix = ix + 1
    end
    return sliced
end
