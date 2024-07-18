@testitem "adaptive timestepping" begin
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    model = BMI.initialize(Ribasim.Model, toml_path)
    @test BMI.get_time_units(model) == "s"
    dt0 = 0.0001269439f0
    @test BMI.get_time_step(model) ≈ dt0 atol = 5e-3
    @test BMI.get_start_time(model) === 0.0
    @test BMI.get_current_time(model) === 0.0
    @test BMI.get_end_time(model) ≈ 3.16224e7
    BMI.update(model)
    @test BMI.get_current_time(model) ≈ dt0 atol = 5e-3
    # cannot go back in time
    @test_throws ErrorException BMI.update_until(model, dt0 / 2.0)
    @test BMI.get_current_time(model) ≈ dt0 atol = 5e-3
    BMI.update_until(model, 86400.0)
    @test BMI.get_current_time(model) == 86400.0
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
    @test storage0 === storage != ones(4)
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
        "basin.infiltration_integrated",
        "basin.drainage_integrated",
        "basin.subgrid_level",
        "user_demand.demand",
        "user_demand.realized",
    ]
        value_first = BMI.get_value_ptr(model, name)
        BMI.update_until(model, 86400.0)
        value_second = BMI.get_value_ptr(model, name)
        # get_value_ptr does not copy
        @test value_first === value_second || pointer(value_first) == pointer(value_second)
    end
end

@testitem "realized_user_demand" begin
    import BasicModelInterface as BMI

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path; allocation_use_allocation = false)
    model = Ribasim.Model(config)
    demand = BMI.get_value_ptr(model, "user_demand.demand")
    realized = BMI.get_value_ptr(model, "user_demand.realized")
    year = model.integrator.p.user_demand.demand_itp[2][1].t[2]
    demand_start = 1e-3
    slope = 1e-3 / year
    day = 86400.0
    BMI.update_until(model, day)
    @test realized ≈ [demand_start * day, demand_start * day + 0.5 * slope * day^2]
    demand_later = 2e-3
    demand[1] = demand_later
    BMI.update_until(model, 2day)
    @test realized[1] == demand_start * day + demand_later * day
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

    drainage_integrated = BMI.get_value_ptr(model, "basin.drainage_integrated")
    @test drainage_integrated ≈ Δt * drainage_flux
end
