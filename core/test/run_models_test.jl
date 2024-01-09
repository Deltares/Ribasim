@testitem "trivial model" begin
    using SciMLBase: successful_retcode
    using Tables: Tables
    using Tables.DataAPI: nrow
    using Dates: DateTime
    import Arrow
    using Ribasim: timesteps

    toml_path = normpath(@__DIR__, "../../generated_testmodels/trivial/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
    (; p) = model.integrator

    # read all results as bytes first to avoid memory mapping
    # which can have cleanup issues due to file locking
    flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
    basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))
    control_bytes = read(normpath(dirname(toml_path), "results/control.arrow"))
    allocation_bytes = read(normpath(dirname(toml_path), "results/allocation.arrow"))
    subgrid_bytes = read(normpath(dirname(toml_path), "results/subgrid_levels.arrow"))

    flow = Arrow.Table(flow_bytes)
    basin = Arrow.Table(basin_bytes)
    control = Arrow.Table(control_bytes)
    allocation = Arrow.Table(allocation_bytes)
    subgrid = Arrow.Table(subgrid_bytes)

    @testset "Schema" begin
        @test Tables.schema(flow) == Tables.Schema(
            (:time, :edge_id, :from_node_id, :to_node_id, :flow),
            (DateTime, Union{Int, Missing}, Int, Int, Float64),
        )
        @test Tables.schema(basin) == Tables.Schema(
            (:time, :node_id, :storage, :level),
            (DateTime, Int, Float64, Float64),
        )
        @test Tables.schema(control) == Tables.Schema(
            (:time, :control_node_id, :truth_state, :control_state),
            (DateTime, Int, String, String),
        )
        @test Tables.schema(allocation) == Tables.Schema(
            (
                :time,
                :allocation_network_id,
                :user_node_id,
                :priority,
                :demand,
                :allocated,
                :abstracted,
            ),
            (DateTime, Int, Int, Int, Float64, Float64, Float64),
        )
        @test Tables.schema(subgrid) ==
              Tables.Schema((:time, :subgrid_id, :subgrid_level), (DateTime, Int, Float64))
    end

    @testset "Results size" begin
        nsaved = length(timesteps(model))
        @test nsaved > 10
        # t0 has no flow, 2 flow edges and 2 boundary condition flows
        @test nrow(flow) == (nsaved - 1) * 4
        @test nrow(basin) == nsaved
        @test nrow(control) == 0
        @test nrow(allocation) == 0
        @test nrow(subgrid) == nsaved * length(p.subgrid.level)
    end

    @testset "Results values" begin
        @test flow.time[1] > DateTime(2020)
        @test coalesce.(flow.edge_id[1:4], -1) == [-1, -1, 9, 11]
        @test flow.from_node_id[1:4] == [6, typemax(Int), 0, 6]
        @test flow.to_node_id[1:4] == [6, typemax(Int), typemax(Int), 0]

        @test basin.storage[1] == 1.0
        @test basin.level[1] ≈ 0.044711584

        # The exporter interpolates 1:1 for three subgrid elements, but shifted by 1.0 meter.
        @test length(p.subgrid.level) == 3
        @test diff(p.subgrid.level) ≈ [-1.0, 2.0]
        # TODO The original subgrid IDs are lost and mapped to 1, 2, 3
        @test subgrid.subgrid_id[1:3] == [11, 22, 33] broken = true
        @test subgrid.subgrid_level[1:3] == [0.0, -1.0, 1.0]
        @test subgrid.subgrid_level[(end - 2):end] == p.subgrid.level
    end
end

@testitem "bucket model" begin
    using SciMLBase: successful_retcode

    toml_path = normpath(@__DIR__, "../../generated_testmodels/bucket/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
end

@testitem "basic model" begin
    using Logging: Debug, with_logger
    using SciMLBase: successful_retcode
    import Tables
    using Dates

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)

    logger = TestLogger()
    model = with_logger(logger) do
        Ribasim.run(toml_path)
    end

    @test model isa Ribasim.Model
    p = model.integrator.p
    @test p isa Ribasim.Parameters
    @test isconcretetype(typeof(p))
    @test all(isconcretetype, fieldtypes(typeof(p)))

    @test successful_retcode(model)
    @test allunique(Ribasim.timesteps(model))
    @test model.integrator.sol.u[end] ≈ Float32[519.8817, 519.8798, 339.3959, 1418.4331] skip =
        Sys.isapple() atol = 1.5

    @test length(logger.logs) == 8
    @test logger.logs[1].level == Debug
    @test logger.logs[1].message == "Read database into memory."

    table = Ribasim.flow_table(model)
    @test Tables.schema(table) == Tables.Schema(
        (:time, :edge_id, :from_node_id, :to_node_id, :flow),
        (DateTime, Union{Int, Missing}, Int, Int, Float64),
    )
    # flows are recorded at the end of each period, and are undefined at the start
    @test unique(table.time) == Ribasim.datetimes(model)[2:end]

    # inflow = outflow over FractionalFlow
    t = table.time[1]
    @test length(p.fractional_flow.node_id) == 3
    for id in p.fractional_flow.node_id
        inflow = only(table.flow[table.to_node_id .== id.value .&& table.time .== t])
        outflow = only(table.flow[table.from_node_id .== id.value .&& table.time .== t])
        @test inflow == outflow
    end
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
    @test length(model.integrator.p.basin.precipitation) == 4
    @test model.integrator.sol.u[end] ≈ Float32[472.02444, 472.02252, 367.6387, 1427.981] skip =
        Sys.isapple()
end

@testitem "allocation example model" begin
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

    @test dense_ad.integrator.sol.u[end] ≈ sparse_ad.integrator.sol.u[end] atol = 1e-3
    @test sparse_fdm.integrator.sol.u[end] ≈ sparse_ad.integrator.sol.u[end]
    @test dense_fdm.integrator.sol.u[end] ≈ sparse_ad.integrator.sol.u[end] atol = 1e-3

    config = Ribasim.Config(toml_path; solver_algorithm = "Rodas5", solver_autodiff = true)
    time_ad = Ribasim.run(config)
    @test successful_retcode(time_ad)
    @test time_ad.integrator.sol.u[end] ≈ sparse_ad.integrator.sol.u[end] atol = 1
end

@testitem "TabulatedRatingCurve model" begin
    using SciMLBase: successful_retcode

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/tabulated_rating_curve/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
    @test model.integrator.sol.u[end] ≈ Float32[7.783636, 726.16394] skip = Sys.isapple()
    # the highest level in the dynamic table is updated to 1.2 from the callback
    @test model.integrator.p.tabulated_rating_curve.tables[end].t[end] == 1.2
end

@testitem "Profile" begin
    import Tables

    "Shorthand for Ribasim.get_area_and_level"
    function lookup(profile, S)
        Ribasim.get_area_and_level(profile.S, profile.A, profile.h, S)[1:2]
    end

    n_interpolations = 100
    storage = range(0.0, 1000.0, n_interpolations)

    # Covers interpolation for constant and non-constant area, extrapolation for constant area
    A = [0.0, 100.0, 100.0]
    h = [0.0, 10.0, 15.0]
    profile = (; A, h, S = Ribasim.profile_storage(h, A))

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
        S = 500.0 + 100.0
        A, h = lookup(profile, S)
        @test h ≈ 10.0 + (S - 500.0) / 100.0
        @test A == 100.0
    end

    # Covers extrapolation for non-constant area
    A = [0.0, 100.0]
    h = [0.0, 10.0]
    profile = (; A, h, S = Ribasim.profile_storage(h, A))

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

    timesteps = model.saved.flow.t
    flow = DataFrame(Ribasim.flow_table(model))
    outlet_flow =
        filter([:from_node_id, :to_node_id] => (from, to) -> from === 2 && to === 3, flow)

    t_min_crest_level =
        level.t[2] * (outlet.min_crest_level[1] - level.u[1]) / (level.u[2] - level.u[1])

    # No outlet flow when upstream level is below minimum crest level
    @test all(@. outlet_flow.flow[timesteps <= t_min_crest_level] == 0)

    timesteps = Ribasim.timesteps(model)
    t_maximum_level = level.t[2]
    level_basin = Ribasim.get_storages_and_levels(model).level[:]

    # Basin level converges to stable level boundary level
    all(isapprox.(level_basin[timesteps .>= t_maximum_level], level.u[3], atol = 5e-2))
end

@testitem "User" begin
    using SciMLBase: successful_retcode

    toml_path = normpath(@__DIR__, "../../generated_testmodels/user/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test successful_retcode(model)

    day = 86400.0
    @test only(model.integrator.sol(0day)) == 1000.0
    # constant user withdraws to 0.9m/900m3
    @test only(model.integrator.sol(150day)) ≈ 900 atol = 5
    # dynamic user withdraws to 0.5m/509m3
    @test only(model.integrator.sol(180day)) ≈ 509 atol = 1
end

@testitem "ManningResistance" begin
    using PreallocationTools: get_tmp
    using SciMLBase: successful_retcode
    using Ribasim: NodeID

    """
    Apply the "standard step method" finite difference method to find a
    backwater curve.

    See: https://en.wikipedia.org/wiki/Standard_step_method

    * The left boundary has a fixed discharge `Q`.
    * The right boundary has a fixed level `h_right`.
    * Channel profile is rectangular.

    # Arguments
    - `Q`: discharge entering in the left boundary (m3/s)
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
    h_actual = get_tmp(p.basin.current_level, u)
    x = collect(10.0:20.0:990.0)
    h_expected = standard_step_method(x, 5.0, 1.0, 0.04, h_actual[end], 1.0e-6)

    # We test with a somewhat arbitrary difference of 0.01 m. There are some
    # numerical choices to make in terms of what the representative friction
    # slope is. See e.g.:
    # https://www.hec.usace.army.mil/confluence/rasdocs/ras1dtechref/latest/theoretical-basis-for-one-dimensional-and-two-dimensional-hydrodynamic-calculations/1d-steady-flow-water-surface-profiles/friction-loss-evaluation
    @test all(isapprox.(h_expected, h_actual; atol = 0.02))
    # Test for conservation of mass, flow at the beginning == flow at the end
    n_self_loops = length(p.graph[].flow_dict)
    @test Ribasim.get_flow(p.graph, NodeID(1), NodeID(2), 0) ≈ 5.0 atol = 0.001 skip =
        Sys.isapple()
    @test Ribasim.get_flow(p.graph, NodeID(101), NodeID(102), 0) ≈ 5.0 atol = 0.001 skip =
        Sys.isapple()
end
