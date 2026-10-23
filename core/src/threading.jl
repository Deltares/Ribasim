"""
    @threaded for i in indices
        ...
    end
    @threaded min_chunk_size for i in indices
        ...
    end

Run a `for` loop over a range of indices in parallel tasks, at most one per thread, each
with a contiguous chunk of at least `min_chunk_size` (default 256) indices. With a single
thread, or too few indices for two chunks, it runs as a plain loop, so small models don't pay
for task overhead. Cheap iterations need a larger `min_chunk_size` to benefit.

The body may run concurrently for different `i`, so it may only write data belonging to `i`.
It can use `continue`, but not `break` or `return`.

This is a macro rather than a function that takes a closure, since creating the closure copies
the variables it captures, such as the parameters, which is slow compared to a small loop.
"""
macro threaded(args...)
    loop = last(args)
    min_chunk_size = length(args) == 2 ? first(args) : 256
    Meta.isexpr(loop, :for) || error("@threaded expects a for loop")
    i, range = loop.args[1].args
    body = loop.args[2]
    f = Expr(:->, i, continue_to_return(body))
    return quote
        local indices = $(esc(range))
        local min_chunk_size = $(esc(min_chunk_size))
        if Threads.nthreads() == 1 || length(indices) ÷ 2 < min_chunk_size
            for $(esc(i)) in indices
                $(esc(body))
            end
        else
            local n_chunks = min(Threads.nthreads(), length(indices) ÷ min_chunk_size)
            parallel_foreach($(esc(f)), indices, n_chunks)
        end
        nothing
    end
end

"Replace `continue` in a loop body by `return`, to use it as the body of a closure."
continue_to_return(ex) = ex
function continue_to_return(ex::Expr)
    ex.head === :continue && return Expr(:return, nothing)
    # A continue in a nested loop or function stays as is
    ex.head in (:for, :while, :function, :->) && return ex
    return Expr(ex.head, map(continue_to_return, ex.args)...)
end

"""
The `min_chunk_size` of `@threaded` for loops with little work per index, such as copying
vectors, which only benefit from multiple threads for the largest models.
"""
const CHEAP_LOOP_MIN_CHUNK_SIZE = 8192

"""
Call `f(i)` for each `i` in `indices`, divided into `n_chunks` contiguous chunks that run as
parallel tasks, see `@threaded`.
"""
function parallel_foreach(
        f::F,
        indices::AbstractUnitRange{<:Integer},
        n_chunks::Int,
    )::Nothing where {F}
    n = length(indices)
    offset = first(indices) - 1
    chunk(k) = (offset + ((k - 1) * n) ÷ n_chunks + 1):(offset + (k * n) ÷ n_chunks)
    tasks = [Threads.@spawn foreach(f, chunk(k)) for k in 2:n_chunks]
    try
        foreach(f, chunk(1))
    finally
        # Wait for all tasks, also when a chunk throws, since the others may still be writing
        wait_all(tasks)
    end
    return nothing
end

"Wait for all tasks and rethrow the first failure, like `waitall` but trim compatible."
function wait_all(tasks::Vector{Task})::Nothing
    exception = nothing
    for task in tasks
        try
            wait(task)
        catch e
            exception === nothing && (exception = e)
        end
    end
    exception === nothing || throw(exception)
    return nothing
end
