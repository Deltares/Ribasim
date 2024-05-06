
@testitem "toml_path" begin
    using IOCapture: capture
    import TOML

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
