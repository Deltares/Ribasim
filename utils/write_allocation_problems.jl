import Ribasim

include("utils.jl")

"""
For all test models that use allocation, write for each subnetwork the problem to file.

A selection can be made by passing the name(s) of the individual testmodel(s) as (an) argument(s).
"""
function (@main)(ARGS)::Cint
    toml_paths = get_testmodels()
    if length(ARGS) > 0
        toml_paths = filter(x -> basename(dirname(x)) in ARGS, toml_paths)
    end

    results_path = normpath(@__DIR__, "../core/test/data/allocation_problems")
    if ispath(results_path)
        rm(results_path; recursive = true)
    end

    mkdir(results_path)

    Threads.@threads for toml_path in toml_paths
        model_name = basename(dirname(toml_path))

        if !startswith(model_name, "invalid_")
            config = Ribasim.Config(toml_path)

            if config.experimental.allocation
                try
                    model = Ribasim.Model(config)
                    (; allocation_models) = model.integrator.p.p_independent.allocation

                    if !isempty(allocation_models)
                        model_dir = normpath(results_path, model_name)
                        mkdir(model_dir)
                    end

                    for allocation_model in allocation_models
                        (; problem, subnetwork_id) = allocation_model

                        Ribasim.write_problem_to_file(
                            problem,
                            config;
                            info = false,
                            path = normpath(
                                model_dir,
                                "allocation_problem_$subnetwork_id.lp",
                            ),
                        )
                    end
                    println("Wrote allocation problem(s) for $model_name")
                catch e
                    @error "Failed to process model $model_name" exception = e
                end
            end
        end
    end
    return 0
end
