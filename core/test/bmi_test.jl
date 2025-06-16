@testitem "adaptive timestepping" begin
    import BasicModelInterface as BMI
    using Ribasim: is_finished

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    model = BMI.initialize(Ribasim.Model, toml_path)
    @test BMI.get_time_units(model) == "s"
    dt0 = 2.8280652f-5
    @test BMI.get_time_step(model) ≈ dt0 atol = 5e-3
    @test BMI.get_start_time(model) === 0.0
    @test BMI.get_current_time(model) === 0.0
    endtime = BMI.get_end_time(model)
    @test endtime ≈ 3.16224e7
    BMI.update(model)
    @test BMI.get_current_time(model) ≈ dt0 atol = 5e-3
    BMI.update_until(model, 86400.0)
    @test BMI.get_current_time(model) == 86400.0
    # cannot go back in time
    @test_throws ErrorException BMI.update_until(model, 3600.0)
    @test BMI.get_current_time(model) == 86400.0
    @test !is_finished(model)
    @test !success(model)
    BMI.update_until(model, endtime)
    @test BMI.get_current_time(model) == endtime
    @test is_finished(model)
    @test success(model)
end

@testitem "fixed timestepping" begin
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    dt = 10.0
    config = Ribasim.Config(toml_path; solver_algorithm = "ImplicitEuler", solver_dt = dt)
    @test config.solver.algorithm == "ImplicitEuler"
    @test config.solver.dt === dt
    model = Ribasim.Model(config)

    @test BMI.get_time_step(model) == dt
    BMI.update(model)
    @test BMI.get_current_time(model) == dt
    @test_throws ErrorException BMI.update_until(model, dt - 60)
    BMI.update_until(model, dt + 60)
    @test BMI.get_current_time(model) == dt + 60
    BMI.update(model)
    @test BMI.get_current_time(model) == 2dt + 60
end

@testitem "get_value_ptr" begin
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    model = BMI.initialize(Ribasim.Model, toml_path)
    storage0 = BMI.get_value_ptr(model, "basin.storage")
    @test storage0 ≈ ones(4)
    @test_throws "Unknown variable foo" BMI.get_value_ptr(model, "foo")
    BMI.update_until(model, 86400.0)
    storage = BMI.get_value_ptr(model, "basin.storage")
    # get_value_ptr does not copy
    @test storage0 == storage != ones(4)
end

@testitem "get_value_ptr_all_values" begin
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    model = BMI.initialize(Ribasim.Model, toml_path)

    for name in [
        "basin.storage",
        "basin.level",
        "basin.infiltration",
        "basin.drainage",
        "basin.cumulative_infiltration",
        "basin.cumulative_drainage",
        "basin.subgrid_level",
        "user_demand.demand",
        "user_demand.cumulative_inflow",
    ]
        value_first = BMI.get_value_ptr(model, name)
        BMI.update_until(model, 86400.0)
        value_second = BMI.get_value_ptr(model, name)
        # get_value_ptr does not copy
        @test value_first === value_second || pointer(value_first) == pointer(value_second)
    end
end

@testitem "UserDemand inflow" begin
    import BasicModelInterface as BMI

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path; allocation_use_allocation = false)
    model = Ribasim.Model(config)
    demand = BMI.get_value_ptr(model, "user_demand.demand")
    inflow = BMI.get_value_ptr(model, "user_demand.cumulative_inflow")
    # One year in seconds
    year = model.integrator.p.p_independent.user_demand.demand_itp[2][1].t[2]
    demand_start = 1e-3
    slope = 1e-3 / year
    day = 86400.0
    BMI.update_until(model, day)
    @test inflow ≈ [demand_start * day, demand_start * day + 0.5 * slope * day^2] atol =
        1e-3
    demand_later = 2e-3
    demand[1] = demand_later
    BMI.update_until(model, 2day)
    @test inflow[1] ≈ demand_start * day + demand_later * day atol = 1e-3
end

@testitem "vertical basin flux" begin
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    model = BMI.initialize(Ribasim.Model, toml_path)
    drainage = BMI.get_value_ptr(model, "basin.drainage")
    drainage_flux = [1.0, 2.0, 3.0, 4.0]
    drainage .= drainage_flux

    Δt = 5 * 86400.0
    BMI.update_until(model, Δt)

    cumulative_drainage = BMI.get_value_ptr(model, "basin.cumulative_drainage")
    @test cumulative_drainage ≈ Δt * drainage_flux
end

@testitem "BMI logging" begin
    using Ribasim: results_path, logger_stream
    import BasicModelInterface as BMI
    using LoggingExtras: global_logger, EarlyFilteredLogger

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/invalid_unstable/ribasim.toml")
    @test ispath(toml_path)
    model = BMI.initialize(Ribasim.Model, toml_path)
    logger = global_logger()
    @test logger isa EarlyFilteredLogger
    @test logger_stream(logger) isa IOStream

    BMI.update_until(model, 1.0)
    BMI.finalize(model)

    log_path = results_path(model.config, "ribasim.log")
    @test isfile(log_path)
    log_str = read(log_path, String)
    @test occursin("Info: Starting a Ribasim simulation.", log_str)
    @test occursin(
        "Error: The model exited at model time 2020-01-01T00:00:00 with return code DtLessThanMin.",
        log_str,
    )
end
