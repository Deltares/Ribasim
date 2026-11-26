# Each script gets its own module, since they define the same names, such as `main`.

@testmodule Mapping begin
    Base.include(@__MODULE__, joinpath(@__DIR__, "..", "build_mapping.jl"))
end

@testmodule Online begin
    Base.include(@__MODULE__, joinpath(@__DIR__, "..", "online.jl"))
end

@testmodule Piave begin
    using TOML

    const SANDBOX_DIR = dirname(@__DIR__)

    "Copy the built Piave models, so that the tests don't change them. Returns the coupling TOML."
    function copy_models(; coupled_irrigation::Bool = true)::String
        models = joinpath(SANDBOX_DIR, "models")
        mapping = joinpath(SANDBOX_DIR, "coupling.gpkg")
        isdir(models) && isfile(mapping) ||
            error("Piave models not found, run `pixi run wflow-coupled-prepare` first.")

        directory = mktempdir()
        cp(models, joinpath(directory, "models"))
        cp(mapping, joinpath(directory, "coupling.gpkg"))
        config = TOML.parsefile(joinpath(SANDBOX_DIR, "coupling.toml"))
        config["coupled_irrigation"] = coupled_irrigation
        config_path = joinpath(directory, "coupling.toml")
        open(io -> TOML.print(io, config), config_path, "w")
        return config_path
    end
end
