using Configurations: from_dict, to_dict
using Ribasim
import BasicModelInterface as BMI

toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
config_template = Ribasim.parsefile(toml_path)
model = BMI.initialize(Ribasim.Model, toml_path)

@testset "adaptive timestepping" begin
    @test BMI.get_time_units(model) == "s"
    dt0 = 0.011461467f0
    @test BMI.get_time_step(model) ≈ dt0
    @test BMI.get_start_time(model) === 0.0
    @test BMI.get_current_time(model) === 0.0
    @test BMI.get_end_time(model) ≈ 3.16224e7
    BMI.update(model)
    @test BMI.get_current_time(model) ≈ dt0
    @test_throws ErrorException BMI.update_until(model, 0.005)
    @test BMI.get_current_time(model) ≈ dt0
    BMI.update_until(model, 86400.0)
    @test BMI.get_current_time(model) == 86400.0
end

@testset "fixed timestepping" begin
    dict = to_dict(config_template)
    dt = 3600
    dict["solver"] = Ribasim.Solver(; algorithm = "Euler", dt)
    config = from_dict(Ribasim.Config, dict)
    @test config.solver.algorithm == "Euler"
    model = BMI.initialize(Ribasim.Model, config)

    @test BMI.get_time_step(model) == dt
    BMI.update(model)
    @test BMI.get_current_time(model) == dt
    @test_throws ErrorException BMI.update_until(model, dt - 60)
    BMI.update_until(model, dt + 60)
    @test BMI.get_current_time(model) == dt + 60
    BMI.update(model)
    @test BMI.get_current_time(model) == 2dt + 60
end
