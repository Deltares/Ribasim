using Test
using Ribasim
import BasicModelInterface as BMI

toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")

@testset "adaptive timestepping" begin
    model = BMI.initialize(Ribasim.Model, toml_path)
    @test BMI.get_time_units(model) == "s"
    dt0 = 0.011371289f0
    @test BMI.get_time_step(model) ≈ dt0 atol = 5e-3
    @test BMI.get_start_time(model) === 0.0
    @test BMI.get_current_time(model) === 0.0
    @test BMI.get_end_time(model) ≈ 3.16224e7
    BMI.update(model)
    @test BMI.get_current_time(model) ≈ dt0 atol = 5e-3
    @test_throws ErrorException BMI.update_until(model, 0.005)
    @test BMI.get_current_time(model) ≈ dt0 atol = 5e-3
    BMI.update_until(model, 86400.0)
    @test BMI.get_current_time(model) == 86400.0
end

@testset "fixed timestepping" begin
    dt = 10.0
    config = Ribasim.Config(
        toml_path;
        solver_algorithm = "ImplicitEuler",
        solver_adaptive = false,
        solver_dt = dt,
    )
    @test config.solver.algorithm == "ImplicitEuler"
    @test !config.solver.adaptive
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

@testset "get_value_ptr" begin
    model = BMI.initialize(Ribasim.Model, toml_path)
    storage0 = BMI.get_value_ptr(model, "volume")
    @test storage0 == ones(4)
    @test_throws "Unknown variable foo" BMI.get_value_ptr(model, "foo")
    BMI.update_until(model, 86400.0)
    storage = BMI.get_value_ptr(model, "volume")
    # get_value_ptr does not copy
    @test storage0 === storage != ones(4)
end

@testset "get_value_ptr_all_values" begin
    model = BMI.initialize(Ribasim.Model, toml_path)

    for name in ["volume", "level", "infiltration", "drainage"]
        value_first = BMI.get_value_ptr(model, name)
        BMI.update_until(model, 86400.0)
        value_second = BMI.get_value_ptr(model, name)
        # get_value_ptr does not copy
        @test value_first === value_second
    end
end
