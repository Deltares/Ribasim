import Ribasim

include("utils.jl")

"""
Run a model with tracers, and return how far the Continuity tracer is from 1.

The Continuity tracer is 1 in all water that enters the model, so it stays 1 if the tracer
calculation conserves mass. A Basin without water has a concentration of 0. If evaporation
leaves its mass behind, the Continuity tracer rises, so this is not checked.
"""
function continuity_error(toml_path::String)::Float64
    config = Ribasim.Config(
        toml_path;
        experimental_concentration = true,
        results_dir = mktempdir(),
    )
    config.solver.evaporate_mass || return 0.0
    model = Ribasim.run(config)
    table = Ribasim.concentration_data(model)
    continuity = table.concentration[table.substance .== "Continuity"]
    return maximum(c -> iszero(c) ? 0.0 : abs(c - 1), continuity; init = 0.0)
end

"""
Run all testmodels and check if they pass. The models that pass are run once more with
tracers, to check that the Continuity tracer stays 1.

A selection can be made by passing the name(s) of the individual testmodel(s) as (an) argument(s).
"""
function (@main)(ARGS)::Cint
    toml_paths = get_testmodels()
    if length(ARGS) > 0
        toml_paths = filter(x -> basename(dirname(x)) in ARGS, toml_paths)
    end
    n_model = length(toml_paths)
    n_pass = 0
    n_fail = 0
    failed = fill("", length(toml_paths))

    for i in eachindex(toml_paths)
        toml_path = toml_paths[i]
        modelname = basename(dirname(toml_path))

        ret_code = Ribasim.main(toml_path)

        # Treat models starting with "invalid_" as expected to fail (non-zero ret_code means pass) :)
        if startswith(modelname, "invalid_")
            ret_code = ret_code == 0 ? 1 : 0
        elseif ret_code == 0
            error = try
                continuity_error(toml_path)
            catch e
                showerror(stdout, e)
                Inf
            end
            if error > 1.0e-8
                println("The Continuity tracer of $modelname is off by $error.")
                ret_code = 1
            end
        end

        if ret_code != 0
            failed[i] = modelname
            n_fail += 1
        else
            n_pass += 1
        end
    end

    println("Ran $n_model models, $n_pass passed, $n_fail failed.\n")

    if n_fail > 0
        println("Failed models:")
        foreach(println, failed)
        println("Model run failed")
        return 1
    end
    return 0
end
