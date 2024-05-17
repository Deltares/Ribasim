import Ribasim

include("utils.jl")

"""
Run all testmodels in parallel and check if they pass.

A selection can be made by passing the name(s) of the individual testmodel(s) as (an) argument(s).
"""
function main(ARGS)
    toml_paths = get_testmodels()
    if length(ARGS) > 0
        toml_paths = filter(x -> basename(dirname(x)) in ARGS, toml_paths)
    end
    n_model = length(toml_paths)
    n_pass = 0
    n_fail = 0
    lk = ReentrantLock()
    failed = String[]

    Threads.@threads for toml_path in toml_paths
        modelname = basename(dirname(toml_path))
        ret_code = Ribasim.main(toml_path)
        lock(lk) do
            if ret_code != 0
                push!(failed, modelname)
                n_fail += 1
            else
                n_pass += 1
            end
        end
    end

    println("Ran $n_model models, $n_pass passed, $n_fail failed.\n")
    if n_fail > 0
        println("Failed models:")
        foreach(println, failed)
        error("Model run failed")
    end
end

main(ARGS)
