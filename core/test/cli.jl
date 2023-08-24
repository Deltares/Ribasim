using Test
using Ribasim
using IOCapture: capture
using Logging: global_logger, ConsoleLogger

include("../../build/ribasim_cli/src/ribasim_cli.jl")

@testset "version" begin
    empty!(ARGS)
    push!(ARGS, "--version")
    (; value, output) = capture(ribasim_cli.julia_main)
    @test value == 0
    @test output == string(pkgversion(Ribasim))
end

@testset "toml_path" begin
    model_path = normpath(@__DIR__, "../../data/basic/")
    toml_path = normpath(model_path, "basic.toml")
    @test ispath(toml_path)
    empty!(ARGS)
    push!(ARGS, toml_path)
    (; value, output, error, backtrace) = capture(ribasim_cli.julia_main)
    @test value == 0
    if value != 0
        @show output
        @show error
        @show backtrace
    end
end

# the global logger is modified by ribasim_cli; set it back to the default
global_logger(ConsoleLogger())
