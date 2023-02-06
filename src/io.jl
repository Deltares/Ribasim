"""
Searchsorted on an Arrow.DictEncoded vector.

Finds the 0-based index in the encoding, and use that to get the range of indices
that belong to the value `x` The `a.indices` start at row 1 with 0 and increase for every
new value found. If a new row has a value it saw before, it will decrease, and this
method cannot be used. However, note that the values in `a` don't need to be sorted,
only the indices, so ['c','b','a'] would still have sorted indices.
"""
function searchsorted_arrow(a::Arrow.DictEncoded, x)
    idx = findfirst(==(x), a.encoding)
    if idx === nothing
        # return the empty range at the insertion point like Base.searchsorted
        n = length(a)
        return (n + 1):n
    end
    return searchsorted(a.indices, idx - 1)
end

function searchsorted_forcing(vars::Arrow.DictEncoded, locs::Arrow.DictEncoded, var, loc)
    # get the global index range of the variable
    var_rows = searchsorted_arrow(vars, var)
    # get the index range of the location in the variable range
    idx = findfirst(==(loc), locs.encoding)
    if idx === nothing
        # return the empty range at the insertion point like Base.searchsorted
        n = length(vars)
        return (n + 1):n
    end
    indices = view(locs.indices, var_rows)
    col_rows = searchsorted(indices, idx - 1)
    # return the global index range of the variable and location combination
    return var_rows[col_rows]
end

function searchsorted_forcing(vars, locs, var, loc)
    # get the global index range of the variable
    var_rows = searchsorted(vars, var)
    locs_sel = view(locs, var_rows)
    col_rows = searchsorted(locs_sel, loc)
    # return the global index range of the variable and location combination
    return var_rows[col_rows]
end
