import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

include("../src/irrigation.jl")
using CairoMakie

function plot_results(
        results,
        nsteps::Int,
        initial_total_storage::Union{Float64, Vector{Float64}},
        file::String;
        icol::Int = 1,
    )
    initial_storage_col =
        isa(initial_total_storage, Float64) ? initial_total_storage :
        initial_total_storage[icol]
    (;
        rec_wt_depth,
        rec_sat_storage,
        rec_unsat_storage,
        rec_actual_et,
        rec_interception,
        rec_infiltration,
        rec_infiltration_excess,
        rec_saturated_excess,
        rec_net_runoff_soil,
        rec_storage,
        rec_leakage,
        rec_demand,
        rec_irrigation,
        rec_canopy_storage,
        rec_precip,
    ) = results

    rec_demand_plot = rec_demand[icol, :]
    rec_irrigation_plot = rec_irrigation[icol, :]
    rec_wt_depth_plot = rec_wt_depth[icol, :]
    rec_actual_et_plot = rec_actual_et[icol, :]
    rec_interception_plot = rec_interception[icol, :]
    rec_net_runoff_plot = rec_net_runoff_soil[icol, :]
    rec_storage_plot = rec_storage[icol, :]
    rec_leakage_plot = rec_leakage[icol, :]
    rec_canopy_storage_plot = rec_canopy_storage[icol, :]

    days = collect(1:nsteps)

    # Storage change: soil + canopy  [mm/day]
    total_storage = rec_storage_plot .+ rec_canopy_storage_plot   # mm
    Δstorage = diff([initial_storage_col; total_storage])

    # Total ET (soil AET + interception ET)
    rec_total_et = rec_actual_et_plot .+ rec_interception_plot

    rec_net_runoff = rec_net_runoff_plot

    # Balance error
    balance_error =
        (rec_precip .+ rec_irrigation_plot) .- rec_total_et .- rec_net_runoff .-
        rec_leakage_plot .- Δstorage
    println(
        "\nBalance error (mm/day): min=$(round(minimum(balance_error), digits = 3))  max=$(round(maximum(balance_error), digits = 3))  mean=$(round(sum(balance_error) / nsteps, digits = 3))",
    )

    # Decompose storage change into release (positive) and gain (negative)
    stor_release = max.(-Δstorage, 0.0)   # storage releasing water → positive contribution
    stor_gain = max.(Δstorage, 0.0)   # storage gaining water   → negative contribution

    # Positive side (above zero): storage release, then precipitation, then irrigation on top
    pos1_top = stor_release
    pos2_top = stor_release .+ rec_precip
    pos3_top = pos2_top .+ rec_irrigation_plot

    # Negative side (below zero): interception ET | soil AET | infil excess | sat excess | leakage | stor gain
    neg1_bot = .-rec_interception_plot
    neg2_bot = neg1_bot .- rec_actual_et_plot
    neg3_bot = neg2_bot .- rec_net_runoff
    neg4_bot = neg3_bot .- rec_leakage_plot
    neg5_bot = neg4_bot .- stor_gain

    fig = Figure(; size = (1000, 1100))
    ax = Axis(
        fig[1, 1];
        title = "Daily water budget  [+ in / − out]  — land balance (mass_balance.jl)",
        xlabel = "Day",
        ylabel = "mm/day",
        xticks = 1:5:nsteps,
    )

    # Positive bars (stacked upward)
    barplot!(
        ax,
        days,
        pos1_top;
        fillto = zeros(nsteps),
        color = (:goldenrod, 0.85),
        label = "Storage release",
    )
    barplot!(
        ax,
        days,
        pos2_top;
        fillto = pos1_top,
        color = (:steelblue, 0.85),
        label = "Precipitation",
    )
    barplot!(
        ax,
        days,
        pos3_top;
        fillto = pos2_top,
        color = (:dodgerblue, 0.85),
        label = "Irrigation (external)",
    )

    # Negative bars (stacked downward)
    barplot!(
        ax,
        days,
        neg1_bot;
        fillto = zeros(nsteps),
        color = (:skyblue, 0.85),
        label = "Interception ET",
    )
    barplot!(
        ax,
        days,
        neg2_bot;
        fillto = neg1_bot,
        color = (:seagreen, 0.85),
        label = "Soil AET",
    )
    barplot!(
        ax,
        days,
        neg3_bot;
        fillto = neg2_bot,
        color = (:orange, 0.85),
        label = "Net runoff (infil + sat excess)",
    )
    barplot!(
        ax,
        days,
        neg4_bot;
        fillto = neg3_bot,
        color = (:mediumpurple, 0.85),
        label = "Leakage",
    )
    barplot!(
        ax,
        days,
        neg5_bot;
        fillto = neg4_bot,
        color = (:goldenrod, 0.85),
        label = nothing,
    )

    hlines!(ax, [0]; color = :black, linewidth = 1)
    axislegend(ax; position = :lt)

    # ── Panel 2: water table depth ────────────────────────────────────────────────
    ax2 = Axis(
        fig[2, 1];
        title = "Water table depth below surface",
        xlabel = "Day",
        ylabel = "depth [m]",
        xticks = 1:5:nsteps,
        yreversed = true,
    )
    lines!(ax2, days, rec_wt_depth_plot; color = :steelblue, linewidth = 2)
    scatter!(ax2, days, rec_wt_depth_plot; color = :steelblue, markersize = 5)

    # ── Panel 3: irrigation demand vs allocation ───────────────────────────────────
    # demand    = rec_demand  (soil-moisture-deficit driven, from NonPaddyModel) [mm/day]
    # allocation = rec_irrigation = fraction_realised × demand  (external supply, e.g. Ribasim)
    # In a real coupling, Ribasim reads demand via BMI get_value, routes water through its
    # network, and returns the achievable allocation which may be < demand.
    ax3 = Axis(
        fig[3, 1];
        title = "Irrigation: demand vs allocation",
        xlabel = "Day",
        ylabel = "mm/day",
        xticks = 1:5:nsteps,
    )
    barplot!(
        ax3,
        days,
        rec_irrigation_plot;
        color = (:dodgerblue, 0.85),
        label = "Allocation (external)",
    )
    stairs!(
        ax3,
        [days; nsteps + 1] .- 0.5,
        [rec_demand_plot; rec_demand_plot[end]];
        color = :navy,
        linewidth = 2,
        step = :post,
        label = "Demand (soil moisture deficit)",
    )
    axislegend(ax3; position = :rt)

    # ── Panel 4: cumulative water budget ──────────────────────────────────────────
    ax4 = Axis(
        fig[4, 1];
        title = "Cumulative fluxes",
        xlabel = "Day",
        ylabel = "mm",
        xticks = 1:5:nsteps,
    )
    lines!(
        ax4,
        days,
        cumsum(rec_precip);
        color = :steelblue,
        linewidth = 2,
        label = "Precipitation",
    )
    lines!(
        ax4,
        days,
        cumsum(rec_irrigation_plot);
        color = :dodgerblue,
        linewidth = 2,
        label = "Irrigation",
    )
    lines!(
        ax4,
        days,
        cumsum(rec_total_et);
        color = :seagreen,
        linewidth = 2,
        label = "Total ET",
    )
    lines!(
        ax4,
        days,
        cumsum(rec_net_runoff);
        color = :orange,
        linewidth = 2,
        label = "Net runoff",
    )
    lines!(
        ax4,
        days,
        cumsum(rec_leakage_plot);
        color = :mediumpurple,
        linewidth = 2,
        label = "Leakage",
    )
    axislegend(ax4; position = :lt)
    save(file, fig)
    return println("Plot saved to: $file")
end

# -- inputs --------------------------------------------------------------------
forcing = Irrigation.default_forcing()   # 30-day synthetic series, edit or replace

# -- run simulation without allocation -----------------------------------------
m = Irrigation.init(; forcing)

# read initial storage before any update
initial_total_storage =
    m.soil.variables.total_soil_water_storage[1] * 1.0e3 +
    m.interception.variables.canopy_storage[1] * 1.0e3   # mm

# runs full simulation at ones for reference, without any allocation
nsteps = length(forcing.timestamps)
Irrigation.update_until!(m, nsteps * m.dt)
plot_results(m.logger, nsteps, initial_total_storage, joinpath(@__DIR__, "single_column_no_allocation.png"))
Irrigation.finalize!(m, joinpath(@__DIR__, "single_column_no_allocation.nc"); initial_total_storage)

# -- run simulation with allocation --------------------------------------------
m = Irrigation.init(; forcing)

# read initial storage before any update
initial_total_storage =
    m.soil.variables.total_soil_water_storage[1] * 1.0e3 +
    m.interception.variables.canopy_storage[1] * 1.0e3   # mm

nsteps = length(forcing.timestamps)
for step in 1:nsteps
    demand = Irrigation.get_demand!(m)
    Irrigation.set_allocated!(m, demand .* 0.5)  # 50% reduction
    print(step, step * m.dt)
    Irrigation.update_until!(m, step * m.dt)
end
plot_results(m.logger, nsteps, initial_total_storage, joinpath(@__DIR__, "single_column_allocation.png"))
Irrigation.finalize!(m, joinpath(@__DIR__, "single_column_allocation.nc"); initial_total_storage)

# -- run multi column simulation with allocation --------------------------------
m = Irrigation.init(; forcing, n = 4)

# read initial storage before any update — one value per cell (all identical at init)
initial_total_storage_multicol = [
    m.soil.variables.total_soil_water_storage[icol] * 1.0e3 +
        m.interception.variables.canopy_storage[icol] * 1.0e3 for icol in 1:4
]

nsteps = length(forcing.timestamps)
fraction_realised = [1.0, 0.75, 0.25, 0.0]
for step in 1:nsteps
    demand = Irrigation.get_demand!(m)
    Irrigation.set_allocated!(m, demand .* fraction_realised)
    print(step, step * m.dt)
    Irrigation.update_until!(m, step * m.dt)
end
for icol in 1:4
    plot_results(
        m.logger,
        nsteps,
        initial_total_storage_multicol,
        joinpath(@__DIR__, "multi_column_col$(icol).png");
        icol,
    )
end
Irrigation.finalize!(m, joinpath(@__DIR__, "multi_column.nc"); initial_total_storage = initial_total_storage_multicol)
