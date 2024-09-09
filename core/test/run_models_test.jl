@testitem "trivial model" begin
    using SciMLBase: successful_retcode
    using Tables: Tables
    using Tables.DataAPI: nrow
    using Dates: DateTime
    import Arrow
    using Ribasim: get_tstops, tsaves

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
    @test successful_retcode(model)
    (; p) = model.integrator

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
            (:time, :edge_id, :from_node_id, :to_node_id, :flow_rate),
            (DateTime, Union{Int32, Missing}, Int32, Int32, Float64),
        )
        @test Tables.schema(basin) == Tables.Schema(
            (
                :time,
                :node_id,
                :storage,
                :level,
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
            (:time, :rhs_calls, :linear_solves, :accepted_timesteps, :rejected_timesteps),
            (DateTime, Int, Int, Int, Int),
        )
    end

    @testset "Results size" begin
        nsaved = length(tsaves(model))
        @test nsaved > 10
        # t0 has no flow, 2 flow edges
        @test nrow(flow) == (nsaved - 1) * 2
        @test nrow(basin) == nsaved - 1
        @test nrow(subgrid) == nsaved * length(p.subgrid.level)
    end

    @testset "Results values" begin
        @test flow.time[1] == DateTime(2020)
        @test coalesce.(flow.edge_id[1:2], -1) == [100, 101]
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
        @test length(p.subgrid.level) == 3
        @test diff(p.subgrid.level) ≈ [-1.0, 2.0]
        @test subgrid.subgrid_id[1:3] == [11, 22, 33]
        @test subgrid.subgrid_level[1:3] ≈
              [basin_level, basin_level - 1.0, basin_level + 1.0]
        @test subgrid.subgrid_level[(end - 2):end] == p.subgrid.level
    end
end

@testitem "bucket model" begin
    using SciMLBase: successful_retcode

    toml_path = normpath(@__DIR__, "../../generated_testmodels/bucket/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.u.storage ≈ [1000]
    vertical_flux = Ribasim.wrap_forcing(model.integrator.p.basin.vertical_flux[Float64[]])
    @test vertical_flux.precipitation == [0.0]
    @test vertical_flux.evaporation == [0.0]
    @test vertical_flux.drainage == [0.0]
    @test vertical_flux.infiltration == [0.0]
    @test successful_retcode(model)
end

@testitem "leaky bucket model" begin
    using SciMLBase: successful_retcode
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/leaky_bucket/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    @test model isa Ribasim.Model

    stor = model.integrator.u.storage
    vertical_flux = Ribasim.wrap_forcing(model.integrator.p.basin.vertical_flux[Float64[]])
    prec = vertical_flux.precipitation
    evap = vertical_flux.evaporation
    drng = vertical_flux.drainage
    infl = vertical_flux.infiltration
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
    @test successful_retcode(Ribasim.solve!(model))
end

@testitem "basic model" begin
    using Logging: Debug, with_logger
    using LoggingExtras
    using SciMLBase: successful_retcode
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
    p = model.integrator.p
    @test p isa Ribasim.Parameters
    @test isconcretetype(typeof(p))
    @test all(isconcretetype, fieldtypes(typeof(p)))

    @test successful_retcode(model)
    @test allunique(Ribasim.tsaves(model))
    @test model.integrator.u ≈ Float32[803.7093, 803.68274, 495.241, 1318.3053] skip =
        Sys.isapple() atol = 1.5

    @test length(logger.logs) > 10
    @test logger.logs[1].level == Debug
    @test logger.logs[1].message == "Read database into memory."

    table = Ribasim.flow_table(model)

    # flows are recorded at the end of each period, and are undefined at the start
    @test unique(table.time) == Ribasim.datetimes(model)[1:(end - 1)]
end

@testitem "basic arrow model" begin
    using SciMLBase: successful_retcode

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic_arrow/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
end

@testitem "basic transient model" begin
    using SciMLBase: successful_retcode

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
    @test allunique(Ribasim.tsaves(model))
    precipitation =
        Ribasim.wrap_forcing(
            model.integrator.p.basin.vertical_flux[Float64[]],
        ).precipitation
    @test length(precipitation) == 4
    @test model.integrator.u ≈ Float32[698.22736, 698.2014, 421.20447, 1334.4354] atol = 2.0 skip =
        Sys.isapple()
end

@testitem "Allocation example model" begin
    using SciMLBase: successful_retcode

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_example/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
end

@testitem "sparse and AD/FDM jac solver options" begin
    using SciMLBase: successful_retcode

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

    @test successful_retcode(sparse_ad)
    @test successful_retcode(dense_ad)
    @test successful_retcode(sparse_fdm)
    @test successful_retcode(dense_fdm)

    @test dense_ad.integrator.u ≈ sparse_ad.integrator.u atol = 0.1
    @test sparse_fdm.integrator.u ≈ sparse_ad.integrator.u atol = 4
    @test dense_fdm.integrator.u ≈ sparse_ad.integrator.u atol = 4

    config = Ribasim.Config(toml_path; solver_algorithm = "Rodas5", solver_autodiff = true)
    time_ad = Ribasim.run(config)
    @test successful_retcode(time_ad)
    @test time_ad.integrator.u ≈ sparse_ad.integrator.u atol = 4
end

@testitem "TabulatedRatingCurve model" begin
    using SciMLBase: successful_retcode

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/tabulated_rating_curve/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
    @test model.integrator.u ≈ Float32[368.31558, 365.68442] skip = Sys.isapple()
    # the highest level in the dynamic table is updated to 1.2 from the callback
    @test model.integrator.p.tabulated_rating_curve.table[end].t[end] == 1.2
end

@testitem "Profile" begin
    import Tables
    using DataInterpolations: LinearInterpolation, integral, invert_integral

    function lookup(profile, S)
        level_to_area = LinearInterpolation(profile.A, profile.h; extrapolate = true)
        storage_to_level = invert_integral(level_to_area)

        level = storage_to_level(max(S, 0.0))
        area = level_to_area(level)
        return area, level
    end

    n_interpolations = 100
    storage = range(0.0, 1000.0, n_interpolations)

    # Covers interpolation for constant and non-constant area, extrapolation for constant area
    A = [1e-9, 100.0, 100.0]
    h = [0.0, 10.0, 15.0]
    S = integral.(Ref(LinearInterpolation(A, h)), h)
    profile = (; S, A, h)

    # On profile points we reproduce the profile
    for (; S, A, h) in Tables.rows(profile)
        @test lookup(profile, S) == (A, h)
    end

    # Robust to negative storage
    @test lookup(profile, -1.0) == (profile.A[1], profile.h[1])

    # On the first segment
    S = 100.0
    A, h = lookup(profile, S)
    @test h ≈ sqrt(S / 5)
    @test A ≈ 10 * h

    # On the second segment and extrapolation
    for S in [500.0 + 100.0, 1000.0 + 100.0]
        local A, h
        S = 500.0 + 100.0
        A, h = lookup(profile, S)
        @test h ≈ 10.0 + (S - 500.0) / 100.0
        @test A == 100.0
    end

    # Covers extrapolation for non-constant area
    A = [1e-9, 100.0]
    h = [0.0, 10.0]
    S = integral.(Ref(LinearInterpolation(A, h)), h)

    profile = (; A, h, S)

    S = 500.0 + 100.0
    A, h = lookup(profile, S)
    @test h ≈ sqrt(S / 5)
    @test A ≈ 10 * h
end

@testitem "Outlet constraints" begin
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode

    toml_path = normpath(@__DIR__, "../../generated_testmodels/outlet/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test successful_retcode(model)
    p = model.integrator.p
    (; level_boundary, outlet) = p
    (; level) = level_boundary
    level = level[1]

    t = model.saved.flow.t
    flow = DataFrame(Ribasim.flow_table(model))
    outlet_flow =
        filter([:from_node_id, :to_node_id] => (from, to) -> from == 2 && to == 3, flow)

    t_min_upstream_level =
        level.t[2] * (outlet.min_upstream_level[1] - level.u[1]) / (level.u[2] - level.u[1])

    # No outlet flow when upstream level is below minimum crest level
    @test all(@. outlet_flow.flow_rate[t <= t_min_upstream_level] == 0)

    t = Ribasim.tsaves(model)
    t_maximum_level = level.t[2]
    level_basin = Ribasim.get_storages_and_levels(model).level[:]

    # Basin level converges to stable level boundary level
    all(isapprox.(level_basin[t .>= t_maximum_level], level.u[3], atol = 5e-2))
end

@testitem "UserDemand" begin
    using SciMLBase: successful_retcode
    using Dates
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/user_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test successful_retcode(model)

    seconds_in_day = 86400.0
    @test only(model.integrator.sol(0seconds_in_day)) == 1000.0
    # constant UserDemand withdraws to 0.9m or 900m3 due to min level = 0.9
    @test only(model.integrator.sol(150seconds_in_day)) ≈ 900 atol = 5
    # dynamic UserDemand withdraws to 0.5m or 500m3 due to min level = 0.5
    @test only(model.integrator.sol(220seconds_in_day)) ≈ 500 atol = 1

    # Trasient return factor
    flow = DataFrame(Ribasim.flow_table(model))
    return_factor_itp = model.integrator.p.user_demand.return_factor[3]
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
    using PreallocationTools: get_tmp
    using SciMLBase: successful_retcode
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
    @test successful_retcode(model)

    u = model.integrator.sol.u[end]
    p = model.integrator.p
    h_actual = p.basin.current_level[parent(u)][1:50]
    x = collect(10.0:20.0:990.0)
    h_expected = standard_step_method(x, 5.0, 1.0, 0.04, h_actual[end], 1.0e-6)

    # We test with a somewhat arbitrary difference of 0.01 m. There are some
    # numerical choices to make in terms of what the representative friction
    # slope is. See e.g.:
    # https://www.hec.usace.army.mil/confluence/rasdocs/ras1dtechref/latest/theoretical-basis-for-one-dimensional-and-two-dimensional-hydrodynamic-calculations/1d-steady-flow-water-surface-profiles/friction-loss-evaluation
    @test all(isapprox.(h_expected, h_actual; atol = 0.02))
    # Test for conservation of mass, flow at the beginning == flow at the end
    n_self_loops = length(p.graph[].flow_dict)
    @test Ribasim.get_flow(
        p.graph,
        NodeID(:FlowBoundary, 1, p),
        NodeID(:Basin, 2, p),
        parent(u),
    ) ≈ 5.0 atol = 0.001 skip = Sys.isapple()
    @test Ribasim.get_flow(
        p.graph,
        NodeID(:ManningResistance, 101, p),
        NodeID(:Basin, 102, p),
        parent(u),
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
