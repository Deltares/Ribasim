# adapted from https://gist.github.com/mkborregaard/81825c3d370bb4d8dbfe59c3b2ae4b33
# by mkborregaard

const callchains = OrderedSet{Vector{Method}}()
const modules = Set{Module}()

function callchain(frame::JuliaInterpreter.Frame)
    chain = Method[]
    sc = JuliaInterpreter.scopeof(frame)
    while sc isa Method
        push!(chain, sc)
        frame = frame.caller
        frame === nothing && break
        sc = JuliaInterpreter.scopeof(frame)
    end
    return chain
end

function log_far!(@nospecialize(recurse), frame, istoplevel::Bool = false)
    chain = callchain(frame)
    chain[1].module ∈ modules && push!(callchains, chain)
    return JuliaInterpreter.finish_and_return!(recurse, frame, istoplevel)
end

function encode_vertices(callchains)
    i = 0
    vertices = Dict{Array{Method}, Int}()
    for chain in callchains
        for ind in length(chain):-1:1
            vert = chain[ind:end]
            haskey(vertices, vert) || (vertices[vert] = (i += 1))
        end
    end
    vertices
end

# per vertex: (module, name, file)
function getdata(vertices)
    data = Vector{Tuple{Symbol, Symbol, Symbol, Int}}(undef, length(vertices))
    for (k, v) in vertices
        k1 = first(k)
        file = Symbol(last(split(String(k1.file), "\\")))
        data[v] = (Symbol(k1.module), k1.name, file, k1.line)
    end
    data
end

@kwdef struct NodeMetadata
    i::Int
    mod::Symbol
    name::Symbol
    file::Symbol
    line::Int
    loc::Vector{Float64} = fill(NaN, 2)
    depth::Base.RefValue{Int} = Ref(0)
    isleaf::Base.RefValue{Bool} = Ref(false)
end

function Base.show(io::IO, nm::NodeMetadata)
    (; mod, name, line) = nm
    print(io, "$mod.$name (L$line)")
end

function construct_graph(callchains)
    vertices = encode_vertices(callchains)
    data = getdata(vertices)

    graph = MetaGraph(DiGraph(); label_type = Int, vertex_data_type = NodeMetadata)

    for (i, dat) in enumerate(data)
        mod, name, file, line = dat
        graph[i] = NodeMetadata(; i, mod, name, file, line)
    end

    for chain in callchains
        for ind in (length(chain) - 1):-1:1
            src = vertices[chain[(ind + 1):end]]
            dst = vertices[chain[ind:end]]
            graph[src, dst] = nothing
        end
    end

    graph, vertices
end

function tracecall(mods::Tuple, call, args)
    empty!(callchains)
    empty!(modules)
    for m in mods
        push!(modules, m)
    end
    frame = JuliaInterpreter.enter_call(call, args...)
    log_far!(log_far!, frame, false)
    construct_graph(callchains)
end
