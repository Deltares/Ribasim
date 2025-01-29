@testitem "main output" begin
    using IOCapture: capture
    import TOML
    using Ribasim: Config, results_path

    model_path = normpath(@__DIR__, "../../generated_testmodels/basic/")
    toml_path = normpath(model_path, "ribasim.toml")

    # change the ribasim_version in the toml file to check warning
    toml_dict = TOML.parsefile(toml_path)
    toml_dict["ribasim_version"] = "a_different_version"
    open(toml_path, "w") do io
        TOML.print(io, toml_dict)
    end

    @test ispath(toml_path)
    (; value, output, error, backtrace) = capture() do
        Ribasim.main(toml_path)
    end
    @test value == 0
    if value != 0
        @show output
        @show error
        @show backtrace
    end
    @test occursin("version in the TOML config file does not match", output)
end

@testitem "main error logging" begin
    using IOCapture: capture
    import TOML
    using Ribasim: Config, results_path

    model_path = normpath(@__DIR__, "../../generated_testmodels/invalid_link_types/")
    toml_path = normpath(model_path, "ribasim.toml")

    @test ispath(toml_path)
    (; value, output) = capture() do
        Ribasim.main(toml_path)
    end
    @test value == 1

    # Stacktraces should be written to both the terminal and log file.
    @test occursin("\nStacktrace:\n", output)
    config = Config(toml_path)
    log_path = results_path(config, "ribasim.log")
    @test ispath(log_path)
    log_str = read(log_path, String)
    @test occursin("\nStacktrace:\n", log_str)
end
