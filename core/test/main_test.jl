@testitem "version" begin
    using IOCapture: capture

    (; value, output) = capture() do
        Ribasim.main(["--version"])
    end
    @test value == 0
    @test output == string(pkgversion(Ribasim))
end

@testitem "toml_path" begin
    using IOCapture: capture

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

@testitem "too many arguments for main" begin
    using IOCapture: capture

    (; value, output) = capture() do
        Ribasim.main(["too", "many"])
    end
    @test value == 1
    @test occursin("Exactly 1 argument expected, got 2", output)
end

@testitem "non-existing file for main" begin
    using IOCapture: capture

    (; value, output) = capture() do
        Ribasim.main(["non-existing-file.toml"])
    end
    @test value == 1
    @test occursin("File not found: non-existing-file.toml", output)
end
