@testitem "Time dependent flow boundary" begin
    using Dates
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/flow_boundary_time/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test successful_retcode(model)

    flow = DataFrame(Ribasim.flow_table(model))
    # only from March to September the FlowBoundary varies
    is_summer(t::DateTime) = 3 <= month(t) < 10
    flow_1_to_2 = filter(
        [:time, :from_node_id, :to_node_id] =>
            (t, from, to) -> is_summer(t) && from == 1 && to == 2,
        flow,
    )
    t = Ribasim.seconds_since.(flow_1_to_2.time, model.config.starttime)
    flow_expected = @. 1 + sin(0.5 * π * (t - t[1]) / (t[end] - t[1]))^2
    # some difference is expected since the modeled flow is for the period up to t
    @test isapprox(flow_1_to_2.flow_rate, flow_expected, rtol = 0.005)
end

@testitem "vertical_flux_means" begin
    using DataFrames: DataFrame, groupby

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path; solver_saveat = 0)
    model = Ribasim.run(toml_path)
    (; p) = model.integrator
    (; basin) = p
    n_basin = length(basin.node_id)
    basin_table = DataFrame(Ribasim.basin_table(model))

    seconds = Ribasim.seconds_since.(unique(basin_table.time), basin_table.time[1])

    for (i, gb) in enumerate(groupby(basin_table, :node_id))
        area = basin.level_to_area[i](gb.level)
        pot_evap = basin.forcing.potential_evaporation[i](seconds)
        # high tolerance since the area is only approximate
        @test gb.evaporation ≈ area .* pot_evap atol = 1e-5
        prec = basin.forcing.precipitation[i](seconds)
        fixed_area = Ribasim.basin_areas(basin, i)[end]
        @test gb.precipitation ≈ fixed_area .* prec
    end
end

@testitem "Integrate over discontinuity" begin
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/level_demand/ribasim.toml")
    @test ispath(toml_path)
    day = 86400.0

    saveat = 20day
    config = Ribasim.Config(
        toml_path;
        solver_saveat = saveat,
        solver_dt = 5day,
        solver_algorithm = "Euler",
    )
    model = Ribasim.Model(config)
    (; basin) = model.integrator.p
    starting_precipitation =
        basin.vertical_flux.precipitation[1] * Ribasim.basin_areas(basin, 1)[end]
    BMI.update_until(model, saveat)
    mean_precipitation = only(model.saved.flow.saveval).precipitation[1]
    # Given that precipitation stops after 15 of the 20 days
    @test mean_precipitation ≈ 3 / 4 * starting_precipitation
end

@testitem "get_cyclic_tstops" begin
    using Ribasim: get_timeseries_tstops
    using DataInterpolations: LinearInterpolation, ConstantInterpolation
    using DataInterpolations.ExtrapolationType: Periodic

    itp = LinearInterpolation(zeros(3), [0.5, 1.0, 1.5])
    @test get_timeseries_tstops(itp, 5.0) == itp.t

    itp = LinearInterpolation(zeros(3), [0.5, 1.0, 1.5]; extrapolation = Periodic)
    @test get_timeseries_tstops(itp, 5.0) == 0:0.5:5

    itp = ConstantInterpolation(zeros(2), [0.3, 0.5]; extrapolation = Periodic)
    @test get_timeseries_tstops(itp, 1.0) ≈ 0.1:0.2:0.9
end

@testitem "cyclic time" begin
    using DataInterpolations.ExtrapolationType: Periodic

    toml_path = normpath(@__DIR__, "../../generated_testmodels/cyclic_time/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.Model(toml_path)
    (; level_boundary, flow_boundary, basin) = model.integrator.p

    function test_extrapolation(itp)
        @test itp.extrapolation_left == Periodic
        @test itp.extrapolation_right == Periodic
    end

    test_extrapolation(basin.forcing.precipitation[1])
    test_extrapolation(level_boundary.level[1])
    test_extrapolation(flow_boundary.flow_rate[1])
end
