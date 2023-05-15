using Test
using Configurations: from_dict, to_dict
using Ribasim
import BasicModelInterface as BMI

include("../../build/libribasim/src/libribasim.jl")

toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
config_template = Ribasim.parsefile(toml_path)

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

@testset "get_value_ptr" begin
    model = BMI.initialize(Ribasim.Model, toml_path)
    u0 = BMI.get_value_ptr(model, "volume")
    @test u0 == ones(4)
    @test_throws "Unknown variable foo" BMI.get_value_ptr(model, "foo")
    BMI.update_until(model, 86400.0)
    u = BMI.get_value_ptr(model, "volume")
    # get_value_ptr does not copy
    @test u0 === u != ones(4)
end

@testset "libribasim" begin
    # data from which we create pointers for libribasim
    time = [-1.0]
    var_name = "volume"
    type = ones(UInt8, 8)

    GC.@preserve time var_name value type toml_path begin
        var_name_ptr = Base.unsafe_convert(Cstring, var_name)
        time_ptr = pointer(time)
        type_ptr = Cstring(pointer(type))
        toml_path_ptr = Base.unsafe_convert(Cstring, toml_path)

        # safe to finalize uninitialized model
        @test isnothing(libribasim.model)
        @test libribasim.finalize() == 0
        @test isnothing(libribasim.model)

        # cannot get time of uninitialized model
        @test libribasim.last_error_message == ""
        retcode = libribasim.get_current_time(time_ptr)
        @test retcode == 1
        @test time[1] == -1
        @test libribasim.last_error_message == "Model not initialized"

        @test libribasim.initialize(toml_path_ptr) == 0
        @test libribasim.model isa Ribasim.Model
        @test libribasim.model.integrator.t == 0.0

        @test libribasim.get_current_time(time_ptr) == 0
        @test time[1] == 0.0

        @test libribasim.get_var_type(var_name_ptr, type_ptr) == 0
        @test unsafe_string(type_ptr) == "double"

        @test libribasim.finalize() == 0
        @test isnothing(libribasim.model)
    end
end
