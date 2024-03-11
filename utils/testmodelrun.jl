using Ribasim

include("utils.jl")

function main(ARGS)
    toml_paths = get_testmodels()
    n_model = length(toml_paths)
    n_pass = 0
    n_fail = 0
    failed = String[]

    for toml_path in toml_paths
        modelname = basename(dirname(toml_path))
        @info "Running model $modelname"
        if Ribasim.main(toml_path) != 0
            @error "Simulation failed" modelname
            push!(failed, modelname)
            n_fail += 1
        else
            n_pass += 1
        end
    end

    @info "Ran $n_model models, $n_pass passed, $n_fail failed."
    if n_fail > 0
        println("Failed models:")
        foreach(println, failed)
    end
end

main(ARGS)
