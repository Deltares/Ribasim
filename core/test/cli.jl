using Test
using Ribasim
using IOCapture: capture

include("../../build/ribasim_cli/src/ribasim_cli.jl")
include("../../utils/testdata.jl")

@testset "version" begin
    empty!(ARGS)
    push!(ARGS, "--version")
    (; value, output) = capture(ribasim_cli.julia_main)
    @test value == 0
    @test output == string(Ribasim.pkgversion(Ribasim))
end

@testset "toml_path" begin
    model_path = normpath(@__DIR__, "../../data/basic/")
    toml_path = normpath(model_path, "basic.toml")
    @test ispath(toml_path)
    empty!(ARGS)
    push!(ARGS, toml_path)
    (; value) = capture(ribasim_cli.julia_main)
    @test value == 0
end
