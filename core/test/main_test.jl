@testitem "version" begin
    using IOCapture: capture
    using Logging: global_logger, ConsoleLogger

    (; value, output) = capture() do
        Ribasim.main(["--version"])
    end
    @test value == 0
    @test output == string(pkgversion(Ribasim))
end

@testitem "toml_path" begin
    using IOCapture: capture
    using Logging: global_logger, ConsoleLogger

    model_path = normpath(@__DIR__, "../../generated_testmodels/basic/")
    toml_path = normpath(model_path, "ribasim.toml")
    @test ispath(toml_path)
    (; value, output, error, backtrace) = capture() do
        Ribasim.main([toml_path])
    end
    @test value == 0
    if value != 0
        @show output
        @show error
        @show backtrace
    end
end
