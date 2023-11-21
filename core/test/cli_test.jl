@testitem "version" begin
    using IOCapture: capture
    using Logging: global_logger, ConsoleLogger

    include("../../build/ribasim_cli/src/ribasim_cli.jl")

    empty!(ARGS)
    push!(ARGS, "--version")
    (; value, output) = capture(ribasim_cli.julia_main)
    @test value == 0
    @test output == string(pkgversion(Ribasim))

    # the global logger is modified by ribasim_cli; set it back to the default
    global_logger(ConsoleLogger())
end

@testitem "toml_path" begin
    using IOCapture: capture
    using Logging: global_logger, ConsoleLogger

    include("../../build/ribasim_cli/src/ribasim_cli.jl")

    model_path = normpath(@__DIR__, "../../generated_testmodels/basic/")
    toml_path = normpath(model_path, "ribasim.toml")
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

    # the global logger is modified by ribasim_cli; set it back to the default
    global_logger(ConsoleLogger())
end
