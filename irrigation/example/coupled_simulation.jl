import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.develop(; path = joinpath(@__DIR__, "..", "..", "core"))
Pkg.instantiate()

include(joinpath(@__DIR__, "..", "src", "irrigation.jl"))

using Ribasim

toml_path = joinpath(@__DIR__, "irrigation_model", "irrigation_model.toml")
isfile(toml_path) || error("Model not found. Run generate_model.py first.")

config = Ribasim.Config(toml_path)
model = Ribasim.Model(config)

irr = model.integrator.p.p_independent.irrigation
isnothing(irr) && error("[experimental] irrigation = true not set in TOML.")
isempty(irr.forcing_timestamps) && error("No irrigation forcing in GeoPackage. Run generate_model.py first.")

n = length(irr.node_id)
forcing = Irrigation.Forcing(irr.forcing_timestamps, irr.precipitation_mmday[1], irr.potential_evaporation_mmday[1])
irr_model = Irrigation.init(; forcing, t_start = config.starttime, n)

irr.model = irr_model
irr.compute_demand! = Irrigation.get_demand!
irr.advance! = Irrigation.update!

initial_total_storage = [
    irr_model.soil.variables.total_soil_water_storage[i] * 1.0e3 +
        irr_model.interception.variables.canopy_storage[i] * 1.0e3
        for i in 1:n
]

Ribasim.solve!(model)
Ribasim.write_results(model)

Irrigation.finalize!(
    irr_model,
    joinpath(@__DIR__, "irrigation_model", "coupled_irrigation.nc");
    initial_total_storage,
    ribasim_node_ids = Int32[id.value for id in irr.node_id],
    irrigated_area_m2 = irr.irrigated_area_m2,
)
