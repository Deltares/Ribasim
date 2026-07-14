# Included inside module Irrigation (irrigation.jl).
# Requires: Dates, Wflow, FillArrays already imported by the parent file.

# ── Forcing ───────────────────────────────────────────────────────────────────
struct Forcing
    timestamps::Vector{DateTime}           # right-labelled: timestamp = end of interval
    precipitation::Vector{Float64}         # mm/day
    potential_evaporation::Vector{Float64} # mm/day
end

function default_forcing(t_start::DateTime = DateTime(2000, 1, 1))
    timestamps = [t_start + Day(i) for i in 1:30]
    return Forcing(
        timestamps,
        [repeat([1.0], 15); repeat([30.0], 15)],
        [repeat([6.0], 15); repeat([0.0], 15)],
    )
end

function get_forcing(forcing::Forcing, t::DateTime)
    idx = searchsortedfirst(forcing.timestamps, t)
    return forcing.precipitation[idx], forcing.potential_evaporation[idx]
end

# ── Config structs ──────────────────────────────────────────────────────────────
@kwdef struct VegetationConfig
    canopy_gap_fraction::Float64 = 0.35
    maximum_canopy_storage::Float64 = 5.0e-4   # m (~0.5 mm)
    rooting_depth::Float64 = 0.5      # m
    crop_coefficient::Float64 = 1.0
    evaporation_to_precipitation_ratio::Float64 = 0.25
end

struct SoilConfig{N}
    layer_thickness::SVector{N, Float64}
    rootfraction::SVector{N, Float64}
    theta_s::Float64
    theta_r::Float64
    theta_fc::Float64
    ksat_surface::Float64
    ksat_decay::Float64
    brooks_corey_exponent::Float64
    kv_factor::Float64
    air_entry_pressure::Float64
    wet_root_distribution_parameter::Float64
    h1::Float64
    h2::Float64
    h3_high::Float64
    h3_low::Float64
    h4::Float64
    alpha_h1::Float64
    infiltration_capacity_soil::Float64
    infiltration_capacity_compacted::Float64
    compacted_area_fraction::Float64
    maximum_leakage::Float64
    cap_hmax::Float64
    cap_n::Float64
    w_soil::Float64
    cf_soil::Float64
    soil_fraction::Float64
end

function SoilConfig(;
        layer_thickness = SVector(0.05, 0.1, 0.2, 0.8),  # m
        rootfraction = SVector(0.4, 0.3, 0.2, 0.1),
        theta_s = 0.45,
        theta_r = 0.05,
        theta_fc = 0.29,
        ksat_surface = 5.0e-7,   # m/s
        ksat_decay = 4.0,      # m⁻¹
        brooks_corey_exponent = 9.0,   # uniform across layers
        kv_factor = 1.0,      # uniform across layers
        air_entry_pressure = -0.1,
        wet_root_distribution_parameter = -500.0,
        h1 = 0.0,
        h2 = -0.1,
        h3_high = -4.0,
        h3_low = -10.0,
        h4 = -40.0,
        alpha_h1 = 1.0,
        infiltration_capacity_soil = 5.0e-6,  # m/s
        infiltration_capacity_compacted = 0.0,
        compacted_area_fraction = 0.0,
        maximum_leakage = 1.0e-3,  # m/s
        cap_hmax = 2.0,
        cap_n = 2.0,
        w_soil = 0.1125,
        cf_soil = 0.038,
        soil_fraction = 1.0,
    )
    N = length(layer_thickness)
    return SoilConfig{N}(
        SVector{N, Float64}(layer_thickness),
        SVector{N, Float64}(rootfraction),
        theta_s,
        theta_r,
        theta_fc,
        ksat_surface,
        ksat_decay,
        brooks_corey_exponent,
        kv_factor,
        air_entry_pressure,
        wet_root_distribution_parameter,
        h1,
        h2,
        h3_high,
        h3_low,
        h4,
        alpha_h1,
        infiltration_capacity_soil,
        infiltration_capacity_compacted,
        compacted_area_fraction,
        maximum_leakage,
        cap_hmax,
        cap_n,
        w_soil,
        cf_soil,
        soil_fraction,
    )
end

@kwdef struct IrrigationConfig
    irrigation_efficiency::Float64 = 0.8
    maximum_irrigation_rate::Float64 = 5.0e-6   # m/s (~432 mm/day)
end

# ── Logger ────────────────────────────────────────────────────────────────────
mutable struct IrrigationLogger
    rec_wt_depth::Matrix{Float64}          # n × nsteps
    rec_sat_storage::Matrix{Float64}
    rec_unsat_storage::Matrix{Float64}
    rec_actual_et::Matrix{Float64}
    rec_interception::Matrix{Float64}
    rec_infiltration::Matrix{Float64}
    rec_infiltration_excess::Matrix{Float64}
    rec_saturated_excess::Matrix{Float64}
    rec_net_runoff_soil::Matrix{Float64}
    rec_storage::Matrix{Float64}
    rec_leakage::Matrix{Float64}
    rec_demand::Matrix{Float64}
    rec_irrigation::Matrix{Float64}
    rec_canopy_storage::Matrix{Float64}
    rec_precip::Vector{Float64}            # uniform forcing — same for all cells
end

IrrigationLogger(n::Int, nsteps::Int) = IrrigationLogger(
    zeros(n, nsteps),  # rec_wt_depth
    zeros(n, nsteps),  # rec_sat_storage
    zeros(n, nsteps),  # rec_unsat_storage
    zeros(n, nsteps),  # rec_actual_et
    zeros(n, nsteps),  # rec_interception
    zeros(n, nsteps),  # rec_infiltration
    zeros(n, nsteps),  # rec_infiltration_excess
    zeros(n, nsteps),  # rec_saturated_excess
    zeros(n, nsteps),  # rec_net_runoff_soil
    zeros(n, nsteps),  # rec_storage
    zeros(n, nsteps),  # rec_leakage
    zeros(n, nsteps),  # rec_demand
    zeros(n, nsteps),  # rec_irrigation
    zeros(n, nsteps),  # rec_canopy_storage
    zeros(nsteps),     # rec_precip
)

function log!(
        logger::IrrigationLogger,
        step::Int,
        soil::Wflow.SbmSoilModel,
        interception::Wflow.GashInterceptionModel,
        demand::Wflow.DemandModel,
        allocation::Wflow.AbstractAllocationModel,
        precip_mmday::Float64,
        dt::Float64,
    )
    logger.rec_wt_depth[:, step] .= soil.variables.water_table_depth
    logger.rec_sat_storage[:, step] .= soil.variables.saturated_water_depth
    logger.rec_unsat_storage[:, step] .= soil.variables.unsaturated_store_depth
    logger.rec_actual_et[:, step] .= soil.variables.actual_evapotranspiration .* (dt * 1.0e3)
    logger.rec_interception[:, step] .=
        interception.variables.interception_rate .* (dt * 1.0e3)
    logger.rec_infiltration[:, step] .= soil.variables.actual_infiltration .* (dt * 1.0e3)
    logger.rec_infiltration_excess[:, step] .=
        soil.variables.infiltration_excess .* (dt * 1.0e3)
    logger.rec_saturated_excess[:, step] .=
        soil.variables.saturation_excess_water .* (dt * 1.0e3)
    logger.rec_net_runoff_soil[:, step] .= soil.variables.net_runoff .* (dt * 1.0e3)
    logger.rec_storage[:, step] .= soil.variables.total_soil_water_storage .* 1.0e3
    logger.rec_leakage[:, step] .= soil.variables.actual_leakage .* (dt * 1.0e3)
    logger.rec_demand[:, step] .= demand.nonpaddy.variables.demand_gross .* (dt * 1.0e3)
    logger.rec_irrigation[:, step] .=
        Wflow.get_irrigation_allocated(allocation) .* (dt * 1.0e3)
    logger.rec_canopy_storage[:, step] .= interception.variables.canopy_storage .* 1.0e3
    return logger.rec_precip[step] = precip_mmday
end
