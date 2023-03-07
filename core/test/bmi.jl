using Ribasim
import BasicModelInterface as BMI

toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
model = BMI.initialize(Ribasim.Model, toml_path)

@testset "time" begin
    @test BMI.get_time_units(model) == "s"
    @test BMI.get_time_step(model) == 86400.0
    @test BMI.get_start_time(model) === 0.0
    @test BMI.get_current_time(model) === 0.0
    @test BMI.get_end_time(model) ≈ 3.16224e7
    BMI.update(model)
    @test BMI.get_current_time(model) == 86400.0
    @test_throws ErrorException BMI.update_until(model, 1.0)
    @test BMI.get_current_time(model) == 86400.0
    BMI.update_until(model, 86400.0)
    @test BMI.get_current_time(model) == 86400.0
    # suggest a 100 second step, but due to fixed dt it takes a full timestep
    BMI.update_until(model, 86500.0)
    @test BMI.get_current_time(model) == 2 * 86400.0
end
