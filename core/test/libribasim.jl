using Test
using Ribasim
import BasicModelInterface as BMI

include("../../build/libribasim/src/libribasim.jl")

toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")

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
