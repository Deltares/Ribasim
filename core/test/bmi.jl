using Ribasim
import BasicModelInterface as BMI

toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
model = BMI.initialize(Ribasim.Model, toml_path)

@testset "time" begin
    @test BMI.get_time_units(model) == "s"
    @test BMI.get_time_step(model) ≈ 0.011461467f0
    @test BMI.get_start_time(model) === 0.0
    @test BMI.get_current_time(model) === 0.0
    @test BMI.get_end_time(model) ≈ 3.16224e7
    BMI.update(model)
    @test BMI.get_current_time(model) ≈ 0.011461467f0
    @test_throws ErrorException BMI.update_until(model, 0.005)
    @test BMI.get_current_time(model) ≈ 0.011461467f0
    BMI.update_until(model, 86400.0)
    # TODO it oversteps here to 103995.266f0
    @test BMI.get_current_time(model) == 86400.0 broken = true
    # TODO test fixed timestep, and determin correct update_until behavior for both cases
end
