@testitem "trivial model" begin
    using Tables: Tables
    using Tables.DataAPI: nrow
    using Dates: DateTime
    import Arrow
    using Ribasim: get_tstops, tsaves, StateRanges

    toml_path = normpath(@__DIR__, "../../generated_testmodels/trivial/ribasim.toml")
    @test ispath(toml_path)

    # There is no control. That means we don't write the control.arrow,
    # and we remove it if it exists.
    control_path = normpath(dirname(toml_path), "results/control.arrow")
    mkpath(dirname(control_path))
    touch(control_path)
    @test ispath(control_path)

    config = Ribasim.Config(toml_path)
    model = Ribasim.run(config)
    @test model isa Ribasim.Model
    @test success(model)
    (; p_non_diff) = model.integrator.p

    @test p_non_diff.node_id == [0, 6, 6]
    @test p_non_diff.state_ranges ==
          StateRanges(; tabulated_rating_curve = 1:1, evaporation = 2:2, infiltration = 3:3)

    @test !ispath(control_path)

    # read all results as bytes first to avoid memory mapping
    # which can have cleanup issues due to file locking
    flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
    basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))
    subgrid_bytes = read(normpath(dirname(toml_path), "results/subgrid_level.arrow"))
    solver_stats_bytes = read(normpath(dirname(toml_path), "results/solver_stats.arrow"))

    flow = Arrow.Table(flow_bytes)
    basin = Arrow.Table(basin_bytes)
    subgrid = Arrow.Table(subgrid_bytes)
    solver_stats = Arrow.Table(solver_stats_bytes)

    @testset "Schema" begin
        @test Tables.schema(flow) == Tables.Schema(
            (:time, :link_id, :from_node_id, :to_node_id, :flow_rate),
            (DateTime, Union{Int32, Missing}, Int32, Int32, Float64),
        )
        @test Tables.schema(basin) == Tables.Schema(
            (
                :time,
                :node_id,
                :level,
                :storage,
                :inflow_rate,
                :outflow_rate,
                :storage_rate,
                :precipitation,
                :evaporation,
                :drainage,
                :infiltration,
                :balance_error,
                :relative_error,
            ),
            (
                DateTime,
                Int32,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
            ),
        )
        @test Tables.schema(subgrid) == Tables.Schema(
            (:time, :subgrid_id, :subgrid_level),
            (DateTime, Int32, Float64),
        )
        @test Tables.schema(solver_stats) == Tables.Schema(
            (
                :time,
                :computation_time,
                :rhs_calls,
                :linear_solves,
                :accepted_timesteps,
                :rejected_timesteps,
            ),
            (DateTime, Float64, Int, Int, Int, Int),
        )
    end

    @testset "Results size" begin
        nsaved = length(tsaves(model))
        @test nsaved > 10
        # t0 has no flow, 2 flow links
        @test nrow(flow) == (nsaved - 1) * 2
        @test nrow(basin) == nsaved - 1
        @test nrow(subgrid) == nsaved * length(p_non_diff.subgrid.level)
    end

    @testset "Results values" begin
        @test flow.time[1] == DateTime(2020)
        @test coalesce.(flow.link_id[1:2], -1) == [100, 101]
        @test flow.from_node_id[1:2] == [6, 0]
        @test flow.to_node_id[1:2] == [0, 2147483647]

        @test basin.storage[1] ≈ 1.0
        @test basin.level[1] ≈ 0.044711584
        @test basin.storage_rate[1] ≈
              (basin.storage[2] - basin.storage[1]) / config.solver.saveat
        @test all(==(0), basin.inflow_rate)
        @test all(>(0), basin.outflow_rate)
        @test flow.flow_rate[1] == basin.outflow_rate[1]
        @test all(==(0), basin.drainage)
        @test all(==(0), basin.infiltration)
        @test all(q -> abs(q) < 1e-7, basin.balance_error)
        @test all(q -> abs(q) < 0.01, basin.relative_error)

        # The exporter interpolates 1:1 for three subgrid elements, but shifted by 1.0 meter.
        basin_level = basin.level[1]
        @test length(p_non_diff.subgrid.level) == 3
        @test diff(p_non_diff.subgrid.level) ≈ [-1.0, 2.0]
        @test subgrid.subgrid_id[1:3] == [11, 22, 33]
        @test subgrid.subgrid_level[1:3] ≈
              [basin_level, basin_level - 1.0, basin_level + 1.0]
        @test subgrid.subgrid_level[(end - 2):end] == p_non_diff.subgrid.level
    end
end

@testitem "bucket model" begin
    using OrdinaryDiffEqCore: get_du

    toml_path = normpath(@__DIR__, "../../generated_testmodels/bucket/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    (; p_non_diff, diff_cache) = model.integrator.p
    (; basin, state_ranges) = p_non_diff
    @test diff_cache.current_storage ≈ [1000]
    @test basin.vertical_flux.precipitation == [0.0]
    @test basin.vertical_flux.drainage == [0.0]
    du = get_du(model.integrator)
    du_evaporation = view(du, state_ranges.evaporation)
    du_infiltration = view(du, state_ranges.infiltration)
    @test du_evaporation == [0.0]
    @test du_infiltration == [0.0]
    @test success(model)
end

@testitem "leaky bucket model" begin
    using OrdinaryDiffEqCore: get_du
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/leaky_bucket/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    @test model isa Ribasim.Model

    (; integrator) = model
    du = get_du(integrator)
    (; u, p, t) = integrator
    (; p_non_diff, diff_cache) = p
    (; basin, state_ranges) = p_non_diff

    Ribasim.water_balance!(du, u, p, t)
    stor = diff_cache.current_storage
    prec = basin.vertical_flux.precipitation
    evap = view(du, state_ranges.evaporation)
    drng = basin.vertical_flux.drainage
    infl = view(du, state_ranges.infiltration)
    # The dynamic data has missings, but these are not set.
    @test prec == [0.0]
    @test evap == [0.0]
    @test drng == [0.003]
    @test infl == [0.0]
    init_stor = 1000.0
    @test stor == [init_stor]
    BMI.update_until(model, 1.5 * 86400)
    @test prec == [0.0]
    @test evap == [0.0]
    @test drng == [0.003]
    @test infl == [0.001]
    stor ≈ Float32[init_stor + 86400 * (0.003 * 1.5 - 0.001 * 0.5)]
    BMI.update_until(model, 2.5 * 86400)
    @test prec == [0.00]
    @test evap == [0.0]
    @test drng == [0.001]
    @test infl == [0.002]
    stor ≈ Float32[init_stor + 86400 * (0.003 * 2.0 + 0.001 * 0.5 - 0.001 - 0.002 * 0.5)]
    @test success(Ribasim.solve!(model))
end

@testitem "basic model" begin
    using Logging: Debug, with_logger
    using LoggingExtras
    using OrdinaryDiffEqBDF: QNDF
    import Tables
    using Dates

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)

    logger = TestLogger(; min_level = Debug)
    filtered_logger = LoggingExtras.EarlyFilteredLogger(Ribasim.is_current_module, logger)
    model = with_logger(filtered_logger) do
        Ribasim.run(toml_path)
    end

    @test model isa Ribasim.Model

    (; integrator) = model
    (; p, alg) = integrator
    (; p_non_diff, diff_cache) = p

    @test p isa Ribasim.Parameters
    @test isconcretetype(typeof(p_non_diff))
    @test all(isconcretetype, fieldtypes(typeof(p_non_diff)))
    @test p_non_diff.node_id == [4, 5, 8, 7, 10, 12, 2, 1, 3, 6, 9, 1, 3, 6, 9]

    @test alg isa QNDF
    @test alg.step_limiter! == Ribasim.limit_flow!

    @test success(model)
    @test length(model.integrator.sol) == 2 # start and end
    @test diff_cache.current_storage ≈ Float32[804.22156, 803.6474, 495.18243, 1318.3053] skip =
        Sys.isapple() atol = 1.5

    @test length(logger.logs) > 10
    @test logger.logs[1].level == Debug
    @test logger.logs[1].message == "Read database into memory."

    table = Ribasim.flow_table(model)

    # flows are recorded at the end of each period, and are undefined at the start
    @test unique(table.time) == Ribasim.datetimes(model)[1:(end - 1)]

    @test isfile(joinpath(dirname(toml_path), "results/concentration.arrow"))
    table = Ribasim.concentration_table(model)
    @test "Continuity" in table.substance
    @test all(isapprox.(table.concentration[table.substance .== "Continuity"], 1.0))
end

@testitem "basic arrow model" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic_arrow/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test success(model)
end

@testitem "basic transient model" begin
    using OrdinaryDiffEqCore: get_du

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test success(model)
    @test allunique(Ribasim.tsaves(model))
    (; p_non_diff, diff_cache) = model.integrator.p
    precipitation = p_non_diff.basin.vertical_flux.precipitation
    @test length(precipitation) == 4
    @test diff_cache.current_storage ≈ Float32[698.6895, 698.143, 420.57407, 1334.486] atol =
        2.0 skip = Sys.isapple()
end

@testitem "Allocation example model" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_example/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test success(model)
end

@testitem "sparse and AD/FDM jac solver options" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")

    config = Ribasim.Config(toml_path; solver_sparse = true, solver_autodiff = true)
    sparse_ad = Ribasim.run(config)
    config = Ribasim.Config(toml_path; solver_sparse = false, solver_autodiff = true)
    dense_ad = Ribasim.run(config)
    config = Ribasim.Config(toml_path; solver_sparse = true, solver_autodiff = false)
    sparse_fdm = Ribasim.run(config)
    config = Ribasim.Config(toml_path; solver_sparse = false, solver_autodiff = false)
    dense_fdm = Ribasim.run(config)

    @test success(sparse_ad)
    @test success(dense_ad)
    @test success(sparse_fdm)
    @test success(dense_fdm)

    @test dense_ad.integrator.u ≈ sparse_ad.integrator.u atol = 0.1
    @test sparse_fdm.integrator.u ≈ sparse_ad.integrator.u atol = 4
    @test dense_fdm.integrator.u ≈ sparse_ad.integrator.u atol = 4

    config = Ribasim.Config(toml_path; solver_algorithm = "Rodas5P", solver_autodiff = true)
    time_ad = Ribasim.run(config)
    @test success(time_ad)
    @test time_ad.integrator.u ≈ sparse_ad.integrator.u atol = 10
end

@testitem "TabulatedRatingCurve model" begin
    using DataInterpolations.ExtrapolationType: Constant, Periodic

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/tabulated_rating_curve/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test success(model)
    (; p_non_diff, diff_cache) = model.integrator.p
    @test diff_cache.current_storage ≈ Float32[368.31558, 365.68442] skip = Sys.isapple()
    (; tabulated_rating_curve) = p_non_diff
    # The first node is static, the first interpolation object always applies
    index_itp1 = tabulated_rating_curve.current_interpolation_index[1]
    @test only(index_itp1.u) == 1
    @test index_itp1.extrapolation_left == Constant
    @test index_itp1.extrapolation_right == Constant
    # The second node is dynamic, switching from interpolation 2 to 3 to 4
    index_itp2 = tabulated_rating_curve.current_interpolation_index[2]
    @test index_itp2.u == [2, 3, 4, 2]
    @test index_itp2.t ≈ [0.0f0, 2.6784f6, 5.184f6, 7.8624e6]
    @test index_itp2.extrapolation_left == Periodic
    @test index_itp2.extrapolation_right == Periodic
    @test length(tabulated_rating_curve.interpolations) == 5
    # the highest level in the dynamic table is updated to 1.2 from the callback
    @test tabulated_rating_curve.interpolations[4].t[end] == 1.2
end

@testitem "Outlet constraints" begin
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/outlet/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)
    (; level_boundary, outlet) = model.integrator.p.p_non_diff
    (; level) = level_boundary
    level = level[1]

    t = model.saved.flow.t
    flow = DataFrame(Ribasim.flow_table(model))
    outlet_flow =
        filter([:from_node_id, :to_node_id] => (from, to) -> from == 2 && to == 3, flow)

    t_min_upstream_level =
        level.t[2] * (outlet.min_upstream_level[1](0.0) - level.u[1]) /
        (level.u[2] - level.u[1])

    # No outlet flow when upstream level is below minimum upstream level
    @test all(@. outlet_flow.flow_rate[t <= t_min_upstream_level] == 0)

    t = Ribasim.tsaves(model)
    t_maximum_level = level.t[2]
    level_basin = Ribasim.get_storages_and_levels(model).level[:]

    # Basin level converges to stable level boundary level
    all(isapprox.(level_basin[t .>= t_maximum_level], level.u[3], atol = 5e-2))
end

@testitem "UserDemand" begin
    using Dates
    using DataFrames: DataFrame
    using Ribasim: formulate_storages!
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/user_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)

    (; integrator) = model
    (; u, p, t, sol) = integrator
    (; p_non_diff, diff_cache) = p
    (; p_non_diff, diff_cache) = model.integrator.p

    day = 86400.0

    @test only(diff_cache.current_storage) ≈ 1000.0
    # constant UserDemand withdraws to 0.9m or 900m3 due to min level = 0.9
    BMI.update_until(model, 150day)
    formulate_storages!(u, p, t)
    @test only(diff_cache.current_storage) ≈ 900 atol = 5
    # dynamic UserDemand withdraws to 0.5m or 500m3 due to min level = 0.5
    BMI.update_until(model, 220day)
    formulate_storages!(u, p, t)
    @test only(diff_cache.current_storage) ≈ 500 atol = 1

    # Trasient return factor
    flow = DataFrame(Ribasim.flow_table(model))
    return_factor_itp = p_non_diff.user_demand.return_factor[3]
    flow_in =
        filter([:from_node_id, :to_node_id] => (from, to) -> (from, to) == (1, 4), flow)
    flow_out =
        filter([:from_node_id, :to_node_id] => (from, to) -> (from, to) == (4, 5), flow)
    time_seconds = Ribasim.seconds_since.(flow_in.time, model.config.starttime)
    @test isapprox(
        flow_out.flow_rate,
        return_factor_itp.(time_seconds) .* flow_in.flow_rate,
        rtol = 1e-1,
    )
end

@testitem "ManningResistance" begin
    using OrdinaryDiffEqCore: get_du
    using Ribasim: NodeID

    """
    Apply the "standard step method" finite difference method to find a
    backwater curve.

    See: https://en.wikipedia.org/wiki/Standard_step_method

    * The left boundary has a fixed flow rate `Q`.
    * The right boundary has a fixed level `h_right`.
    * Channel profile is rectangular.

    # Arguments
    - `Q`: flow rate entering in the left boundary (m3/s)
    - `w`: width (m)
    - `n`: Manning roughness
    - `h_right`: water level on the right boundary
    - `h_close`: when to stop iteration

    Returns
    -------
    S_f: friction slope
    """
    function standard_step_method(x, Q, w, n, h_right, h_close)
        """Manning's friction slope"""
        function friction_slope(Q, w, d, n)
            A = d * w
            R_h = A / (w + 2 * d)
            S_f = Q^2 * (n^2) / (A^2 * R_h^(4 / 3))
            return S_f
        end

        h = fill(h_right, length(x))
        Δx = diff(x)

        # Iterate backwards, from right to left.
        h1 = h_right
        for i in reverse(eachindex(Δx))
            h2 = h1  # Initial guess
            Δh = h_close + 1.0
            L = Δx[i]
            while Δh > h_close
                sf1 = friction_slope(Q, w, h1, n)
                sf2 = friction_slope(Q, w, h2, n)
                h2new = h1 + 0.5 * (sf1 + sf2) * L
                Δh = abs(h2new - h2)
                h2 = h2new
            end

            h[i] = h2
            h1 = h2
        end

        return h
    end

    toml_path = normpath(@__DIR__, "../../generated_testmodels/backwater/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test success(model)

    du = get_du(model.integrator)
    (; p, t) = model.integrator
    (; p_non_diff, diff_cache) = p
    (; current_level) = diff_cache
    h_actual = current_level[1:50]
    x = collect(10.0:20.0:990.0)
    h_expected = standard_step_method(x, 5.0, 1.0, 0.04, h_actual[end], 1.0e-6)

    # We test with a somewhat arbitrary difference of 0.01 m. There are some
    # numerical choices to make in terms of what the representative friction
    # slope is. See e.g.:
    # https://www.hec.usace.army.mil/confluence/rasdocs/ras1dtechref/latest/theoretical-basis-for-one-dimensional-and-two-dimensional-hydrodynamic-calculations/1d-steady-flow-water-surface-profiles/friction-loss-evaluation
    @test all(isapprox.(h_expected, h_actual; atol = 0.02))
    # Test for conservation of mass, flow at the beginning == flow at the end
    @test Ribasim.get_flow(
        du,
        p_non_diff,
        t,
        (NodeID(:FlowBoundary, 1, p_non_diff), NodeID(:Basin, 2, p_non_diff)),
    ) ≈ 5.0 atol = 0.001 skip = Sys.isapple()
    @test Ribasim.get_flow(
        du,
        p_non_diff,
        t,
        (NodeID(:ManningResistance, 101, p_non_diff), NodeID(:Basin, 102, p_non_diff)),
    ) ≈ 5.0 atol = 0.001 skip = Sys.isapple()
end

@testitem "mean_flow" begin
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/flow_boundary_time/ribasim.toml")
    @test ispath(toml_path)
    function get_flow(solver_dt::Union{Float64, Nothing}, solver_saveat::Float64)
        config = Ribasim.Config(toml_path; solver_dt, solver_saveat)
        model = Ribasim.run(config)
        df = DataFrame(Ribasim.flow_table(model))
        flow =
            filter(
                [:from_node_id, :to_node_id] => (from, to) -> from == 3 && to == 2,
                df,
            ).flow_rate
        flow, Ribasim.tsaves(model)
    end

    Δt = 24 * 24 * 60.0
    t_end = 3.16224e7 # 366 days

    # t_end % saveat = 0
    saveat = 86400.0
    flow, tstops = get_flow(nothing, saveat)
    @test all(flow .≈ 1.0)
    @test length(flow) == t_end / saveat
    @test length(tstops) == t_end / saveat + 1

    flow, tstops = get_flow(Δt, saveat)
    @test all(flow .≈ 1.0)
    @test length(flow) == t_end / saveat
    @test length(tstops) == t_end / saveat + 1

    # t_end % saveat != 0
    saveat = round(10000 * π)
    flow, tstops = get_flow(nothing, saveat)
    @test all(flow .≈ 1.0)
    @test length(flow) == ceil(t_end / saveat)
    @test length(tstops) == ceil(t_end / saveat) + 1

    flow, tstops = get_flow(Δt, saveat)
    @test all(flow .≈ 1.0)
    @test length(flow) == ceil(t_end / saveat)
    @test length(tstops) == ceil(t_end / saveat) + 1

    # Only save average over all flows in tspan
    saveat = Inf
    flow, tstops = get_flow(nothing, saveat)
    @test all(flow .≈ 1.0)
    @test length(flow) == 1
    @test length(tstops) == 2

    flow, tstops = get_flow(Δt, saveat)
    @test all(flow .≈ 1.0)
    @test length(flow) == 1
    @test length(tstops) == 2

    # Save all flows
    saveat = 0.0
    flow, tstops = get_flow(nothing, saveat)
    @test all(flow .≈ 1.0)
    @test length(flow) == length(tstops) - 1

    flow, tstops = get_flow(Δt, saveat)
    @test all(flow .≈ 1.0)
    @test length(flow) == length(tstops) - 1
end

@testitem "stroboscopic_forcing" begin
    using SciMLBase: successful_retcode
    using Ribasim: is_finished
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/bucket/ribasim.toml")
    model = BMI.initialize(Ribasim.Model, toml_path)

    drn = BMI.get_value_ptr(model, "basin.drainage")
    drn_sum = BMI.get_value_ptr(model, "basin.cumulative_drainage")
    inf = BMI.get_value_ptr(model, "basin.infiltration")
    inf_sum = BMI.get_value_ptr(model, "basin.cumulative_infiltration")

    nday = 300
    inf_out = fill(NaN, nday)
    drn_out = fill(NaN, nday)

    Δt::Float64 = 86400.0

    for day in 0:(nday - 1)
        if iseven(day)
            drn .= 25.0 / Δt
            inf .= 0.0
        else
            drn .= 0.0
            inf .= 25.0 / Δt
        end
        BMI.update_until(model, day * Δt)

        inf_out[day + 1] = only(inf_sum)
        drn_out[day + 1] = only(drn_sum)
    end

    @test successful_retcode(model.integrator.sol)
    @test !is_finished(model)

    Δdrn = diff(drn_out)
    Δinf = diff(inf_out)

    @test all(Δdrn[1:2:end] .== 0.0)
    @test all(isapprox.(Δdrn[2:2:end], 25.0; atol = 1e-10))
    @test all(isapprox.(Δinf[1:2:end], 25.0; atol = 1e-10))
    @test all(Δinf[2:2:end] .== 0.0)
end

@testitem "two_basin" begin
    using DataFrames: DataFrame, nrow
    using Dates: DateTime
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/two_basin/ribasim.toml")
    model = Ribasim.run(toml_path)
    df = DataFrame(Ribasim.subgrid_level_table(model))

    ntime = 367
    @test nrow(df) == ntime * 2
    @test df.subgrid_id == repeat(1:2; outer = ntime)
    @test extrema(df.time) == (DateTime(2020), DateTime(2021))
    @test allunique(df.time[1:2:(end - 1)])
    @test all(df.subgrid_level[1:2] .== 0.01)

    # After a month the h(h) of subgrid_id 2 increases by a meter
    i_change = searchsortedfirst(df.time, DateTime(2020, 2))
    @test df.subgrid_level[i_change + 1] - df.subgrid_level[i_change - 1] ≈ 1.0f0

    # Besides the 1 meter shift the h(h) relations are 1:1
    basin_level = copy(BMI.get_value_ptr(model, "basin.level"))
    basin_level[2] += 1
    @test basin_level ≈ df.subgrid_level[(end - 1):end]
    @test basin_level ≈ model.integrator.p.p_non_diff.subgrid.level
end

@testitem "junction" begin
    import SQLite
    import MetaGraphsNext: labels

    # Combined (confluence and bifurcation) model
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/junction_combined/ribasim.toml")

    config = Ribasim.Config(toml_path)
    db_path = Ribasim.database_path(config)
    db = SQLite.DB(db_path)
    graph = Ribasim.create_graph(db, config)

    (; internal_flow_links, external_flow_links, flow_link_map) = graph.graph_data
    @test length(internal_flow_links) == 8
    @test length(external_flow_links) == 10
    @test all(node.type != Ribasim.NodeType.Junction for node in labels(graph))

    # Chained model
    model = Ribasim.run(toml_path)

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/junction_chained/ribasim.toml")

    config = Ribasim.Config(toml_path)
    db_path = Ribasim.database_path(config)
    db = SQLite.DB(db_path)
    graph = Ribasim.create_graph(db, config)

    (; internal_flow_links, external_flow_links, flow_link_map) = graph.graph_data
    @test length(internal_flow_links) == 6
    @test length(external_flow_links) == 8
    @test all(node.type != Ribasim.NodeType.Junction for node in labels(graph))

    model = Ribasim.run(toml_path)
end
