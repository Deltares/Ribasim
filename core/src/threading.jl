"""
    @threaded for i in indices
        ...
    end
    @threaded min_chunk_size for i in indices
        ...
    end

Run a `for` loop over a range of indices in parallel tasks, at most one per thread, which take
contiguous chunks of at least `min_chunk_size` (default 256) indices, see `parallel_chunks`.
With a single thread, or too few indices for two chunks, it runs as a plain loop, so small models
don't pay for task overhead. Cheap iterations need a larger `min_chunk_size` to benefit.

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
        local n_chunks = parallel_chunk_count(length(indices), $(esc(min_chunk_size)))
        if n_chunks == 1
            for $(esc(i)) in indices
                $(esc(body))
            end
        else
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
The number of chunks per thread. With more chunks than threads, a thread that is slower, such
as an efficiency core, or has more expensive indices, takes fewer chunks.
"""
const CHUNKS_PER_THREAD = 4

"""
The number of chunks for `n` indices with at least `min_chunk_size` indices per chunk: 1 with a
single thread or too few indices for two chunks, otherwise at most `CHUNKS_PER_THREAD` per thread.
"""
function parallel_chunk_count(n::Int, min_chunk_size::Int)::Int
    nthreads = Threads.nthreads()
    (nthreads == 1 || n ÷ 2 < min_chunk_size) && return 1
    return min(CHUNKS_PER_THREAD * nthreads, n ÷ min_chunk_size)
end

"The `k`-th of `n_chunks` contiguous chunks of `indices`, which differ at most 1 in length."
function chunk_range(indices::AbstractUnitRange{<:Integer}, k::Int, n_chunks::Int)::UnitRange{Int}
    n = length(indices)
    offset = first(indices) - 1
    return (offset + ((k - 1) * n) ÷ n_chunks + 1):(offset + (k * n) ÷ n_chunks)
end

"""
Call `f(k)` for each chunk `k` in `1:n_chunks`, in parallel tasks, at most one per thread. Each
task takes the next chunk when it finishes the previous one, which balances the work over the
threads. A function can process the `k`-th `chunk_range` of several loops, so that they share
one set of tasks.
"""
function parallel_chunks(f::F, n_chunks::Int)::Nothing where {F}
    next_chunk = Threads.Atomic{Int}(1)
    function take_chunks()
        while true
            k = Threads.atomic_add!(next_chunk, 1)
            k > n_chunks && return nothing
            f(k)
        end
        return
    end
    tasks = [Threads.@spawn take_chunks() for _ in 2:min(Threads.nthreads(), n_chunks)]
    try
        take_chunks()
    finally
        # Wait for all tasks, also when a chunk throws, since the others may still be writing
        waitall(tasks; failfast = false)
    end
    return nothing
end

"""
Call `f(i)` for each `i` in `indices`, divided into `n_chunks` contiguous chunks that run as
parallel tasks, see `parallel_chunks`.
"""
function parallel_foreach(
        f::F,
        indices::AbstractUnitRange{<:Integer},
        n_chunks::Int,
    )::Nothing where {F}
    parallel_chunks(k -> foreach(f, chunk_range(indices, k, n_chunks)), n_chunks)
    return nothing
end
