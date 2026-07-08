module Irrigation

using Dates
using Wflow
using StaticArrays: SVector
using FillArrays

include("irrigation_utils.jl")

# ── Allocation stub ────────────────────────────────────────────────────────────
struct ExternalIrrigationAllocation <: Wflow.AbstractAllocationModel
    n::Int
    irrigation_allocation::Vector{Float64}   # [m/s], set externally each step
end
ExternalIrrigationAllocation(n::Int) = ExternalIrrigationAllocation(n, zeros(n))
Wflow.get_irrigation_allocated(a::ExternalIrrigationAllocation) = a.irrigation_allocation
Wflow.get_groundwater_abstraction_flux(a::ExternalIrrigationAllocation) =
    FillArrays.Zeros(a.n)

# ── State struct ───────────────────────────────────────────────────────────────
mutable struct IrrigationModel
    n::Int
    # Wflow components (unpacked for direct access)
    soil::Wflow.SbmSoilModel
    interception::Wflow.GashInterceptionModel
    runoff::Wflow.OpenWaterRunoff
    demand::Wflow.DemandModel
    allocation::ExternalIrrigationAllocation
    atmospheric_forcing::Wflow.AtmosphericForcing
    snow::Wflow.NoSnowModel
    glacier::Wflow.NoGlacierModel
    config::Wflow.Config
    exfiltwater_average::Vector{Float64}
    # Forcing
    forcing::Forcing
    t_start::DateTime
    irr_config::IrrigationConfig
    dt::Float64
    # Clock
    tcurrent::Float64   # seconds elapsed since t_start
    # Logger
    logger::IrrigationLogger
end

# ── init ───────────────────────────────────────────────────────────────────────
function init(;
        forcing::Forcing = default_forcing(),
        t_start::DateTime = forcing.timestamps[1] - Day(1),
        dt::Float64 = 86400.0,
        n::Int = 1,
        soil_cfg::SoilConfig = SoilConfig(),
        veg_cfg::VegetationConfig = VegetationConfig(),
        irr_cfg::IrrigationConfig = IrrigationConfig(),
    )
    sc = soil_cfg
    vc = veg_cfg
    ic = irr_cfg

    N = length(sc.layer_thickness)
    cumulative_depth = SVector(0.0, cumsum(sc.layer_thickness)...)
    soil_thickness = sum(sc.layer_thickness)
    brooks_corey_exp = SVector(ntuple(_ -> sc.brooks_corey_exponent, N)...)
    kv_factor_vec = SVector(ntuple(_ -> sc.kv_factor, N)...)

    atmospheric_forcing = Wflow.AtmosphericForcing(; n)

    vegetation_parameters = Wflow.VegetationParameters(;
        leaf_area_index = nothing,
        canopy_gap_fraction = fill(vc.canopy_gap_fraction, n),
        maximum_canopy_storage = fill(vc.maximum_canopy_storage, n),
        rooting_depth = fill(vc.rooting_depth, n),
        crop_coefficient = fill(vc.crop_coefficient, n),
    )

    interception = Wflow.GashInterceptionModel(;
        n,
        parameters = Wflow.GashParameters(;
            evaporation_to_precipitation_ratio = fill(
                vc.evaporation_to_precipitation_ratio,
                n,
            ),
            vegetation_parameter_set = vegetation_parameters,
        ),
    )

    snow = Wflow.NoSnowModel(n)
    glacier = Wflow.NoGlacierModel(n)
    runoff = Wflow.OpenWaterRunoff(; n)

    soil_parameters = Wflow.SbmSoilParameters(;
        maximum_number_of_layers = N,
        number_of_layers = fill(N, n),
        vegetation_parameter_set = vegetation_parameters,
        kv_profile = Wflow.KvExponential(fill(sc.ksat_surface, n), fill(sc.ksat_decay, n)),
        theta_s = fill(sc.theta_s, n),
        theta_r = fill(sc.theta_r, n),
        theta_fc = fill(sc.theta_fc, n),
        soil_water_capacity = fill((sc.theta_s - sc.theta_r) * soil_thickness, n),
        soil_thickness = fill(soil_thickness, n),
        actual_layer_thickness = fill(sc.layer_thickness, n),
        cumulative_layer_depth = fill(cumulative_depth, n),
        air_entry_pressure = fill(sc.air_entry_pressure, n),
        brooks_corey_exponent = fill(brooks_corey_exp, n),
        vertical_hydraulic_conductivity_factor = fill(kv_factor_vec, n),
        rootfraction = fill(sc.rootfraction, n),
        infiltration_capacity_compacted_soil = fill(sc.infiltration_capacity_compacted, n),
        infiltration_capacity_soil = fill(sc.infiltration_capacity_soil, n),
        maximum_leakage = fill(sc.maximum_leakage, n),
        cap_hmax = fill(sc.cap_hmax, n),
        cap_n = fill(sc.cap_n, n),
        w_soil = fill(sc.w_soil, n),
        cf_soil = fill(sc.cf_soil, n),
        compacted_soil_area_fraction = fill(sc.compacted_area_fraction, n),
        wet_root_distribution_parameter = fill(sc.wet_root_distribution_parameter, n),
        h1 = fill(sc.h1, n),
        h2 = fill(sc.h2, n),
        h3_high = fill(sc.h3_high, n),
        h3_low = fill(sc.h3_low, n),
        h4 = fill(sc.h4, n),
        alpha_h1 = fill(sc.alpha_h1, n),
        soil_fraction = fill(sc.soil_fraction, n),
    )

    soil = Wflow.SbmSoilModel(;
        n,
        parameters = soil_parameters,
        variables = Wflow.SbmSoilVariables(n, soil_parameters),
    )

    demand = Wflow.DemandModel(;
        domestic = Wflow.NoNonIrrigationDemandModel(n),
        industry = Wflow.NoNonIrrigationDemandModel(n),
        livestock = Wflow.NoNonIrrigationDemandModel(n),
        paddy = Wflow.NoIrrigationPaddyModel(n),
        nonpaddy = Wflow.NonPaddyModel(;
            n,
            parameters = Wflow.NonPaddyParameters(;
                irrigation_efficiency = fill(ic.irrigation_efficiency, n),
                maximum_irrigation_rate = fill(ic.maximum_irrigation_rate, n),
                irrigation_areas = fill(true, n),
                irrigation_trigger = fill(true, n),
            ),
        ),
        variables = Wflow.DemandVariables(; n),
    )

    allocation = ExternalIrrigationAllocation(n)

    fill!(runoff.variables.runoff_river, 0.0)
    fill!(runoff.variables.runoff_land, 0.0)
    fill!(runoff.variables.actual_open_water_evaporation_land, 0.0)
    fill!(runoff.variables.actual_open_water_evaporation_river, 0.0)
    fill!(runoff.variables.net_runoff_river, 0.0)

    config = Wflow.Config(
        Dict{String, Any}(
            "path" => "",
            "model" => Dict{String, Any}(
                "type" => "sbm",
                "snow__flag" => false,
                "soil_infiltration_reduction__flag" => false,
            ),
            "input" => Dict{String, Any}(
                "path_forcing" => "",
                "path_static" => "",
                "basin__local_drain_direction" => "",
                "river_location__mask" => "",
                "subbasin_location__count" => "",
                "forcing" => Dict{String, Any}(),
                "static" => Dict{String, Any}(),
            ),
        );
        path = "",
    )

    nsteps = length(forcing.timestamps)
    println("Irrigation model initialised.")

    return IrrigationModel(
        n,
        soil,
        interception,
        runoff,
        demand,
        allocation,
        atmospheric_forcing,
        snow,
        glacier,
        config,
        zeros(n),                    # exfiltwater_average
        forcing,
        t_start,
        irr_cfg,
        dt,
        0.0,                         # tcurrent [s]
        IrrigationLogger(n, nsteps),
    )
end

# ── update! ────────────────────────────────────────────────────────────────────
function update!(m::IrrigationModel)
    (;
        soil,
        interception,
        runoff,
        demand,
        allocation,
        atmospheric_forcing,
        snow,
        glacier,
        config,
        exfiltwater_average,
        forcing,
        t_start,
        dt,
    ) = m

    # derive current DateTime (right-labelled: end of the interval being computed)
    t_now = t_start + Second(round(Int, m.tcurrent + dt))
    step = searchsortedfirst(forcing.timestamps, t_now)   # logger index
    precip_mmday, pet_mmday = get_forcing(forcing, t_now)

    dummy_subsurface = (; variables = (; exfiltwater_average))

    fill!(atmospheric_forcing.precipitation, precip_mmday * 1.0e-3 / dt)
    fill!(atmospheric_forcing.potential_evaporation, pet_mmday * 1.0e-3 / dt)
    fill!(atmospheric_forcing.temperature, 283.15)

    Wflow.update_interception_model!(interception, atmospheric_forcing, dt)

    Wflow.get_water_flux_surface!(
        runoff.boundary_conditions.water_flux_surface,
        snow,
        glacier,
        interception,
    )

    Wflow.update_bc_soil_model!(
        soil,
        atmospheric_forcing,
        (; interception, runoff, demand, allocation),
        dt,
    )

    Wflow.update_soil_water_flow!(
        soil,
        atmospheric_forcing,
        (; snow, runoff, demand),
        config,
        dt,
    )

    for cell_idx in 1:m.n
        zi_prev = soil.variables.water_table_depth[cell_idx]
        net_flux = soil.variables.recharge[cell_idx]
        specific_yield = Wflow.lower_bound_drainable_porosity(
            soil.parameters.theta_s[cell_idx],
            soil.parameters.theta_fc[cell_idx],
        )
        dh, exfilt = Wflow.water_table_change(soil, net_flux, specific_yield, cell_idx, dt)
        new_wt_depth = clamp(zi_prev - dh, 0.0, soil.parameters.soil_thickness[cell_idx])
        Wflow.update_ustorelayerdepth!(soil, zi_prev, new_wt_depth, cell_idx)
        exfiltwater_average[cell_idx] = exfilt
    end

    Wflow.update_soil_water_storage!(
        soil,
        (; runoff, demand, subsurface_flow = dummy_subsurface),
        dt,
    )

    log!(m.logger, step, soil, interception, demand, allocation, precip_mmday, dt)

    @. soil.variables.actual_evapotranspiration += interception.variables.interception_rate

    return m.tcurrent += dt
end

# ── update_until! ──────────────────────────────────────────────────────────────
function update_until!(m::IrrigationModel, t_end::Float64)
    while m.tcurrent < t_end - 0.5 * m.dt
        update!(m)
    end
    return
end

# ── public API ─────────────────────────────────────────────────────────────────
function get_demand!(m::IrrigationModel)
    Wflow.update_water_demand_model!(m.demand, m.soil, m.dt)
    return m.demand.nonpaddy.variables.demand_gross
end

function set_allocated!(m::IrrigationModel, allocation::AbstractVector{Float64})
    return m.allocation.irrigation_allocation .= allocation
end

end # module Irrigation
