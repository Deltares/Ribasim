using Ribasim

include("../../build/ribasim_cli/src/ribasim_cli.jl")

# Taken from Julia's testsuite
macro capture_stdout(ex)
    quote
        mktemp() do fname, f
            result = redirect_stdout(f) do
                $(esc(ex))
            end
            seekstart(f)
            output = read(f, String)
            result, output
        end
    end
end

@testset "version" begin
    empty!(ARGS)
    push!(ARGS, "--version")
    result, output = @capture_stdout(ribasim_cli.julia_main())
    @test result == 0
    @test output == string(Ribasim.pkgversion(Ribasim))
end

@testset "toml_path" begin
    toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
    @test ispath(toml_path)
    empty!(ARGS)
    push!(ARGS, toml_path)
    result, output = @capture_stdout(ribasim_cli.julia_main())
    @test result == 0
end
