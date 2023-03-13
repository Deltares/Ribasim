using Main.ribasim_cli
using Ribasim

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
    empty!(Base.ARGS)
    push!(Base.ARGS, "--version")
    result, output = @capture_stdout(ribasim_cli.julia_main())
    @test result == 0
    @test output == string(Ribasim.pkgversion(Ribasim))
    empty!(Base.ARGS)
end

@testset "toml_path" begin
    toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
    @test ispath(toml_path)
    empty!(Base.ARGS)
    push!(Base.ARGS, toml_path)
    result, output = @capture_stdout(ribasim_cli.julia_main())
    @test result == 0
    # TODO
    #@test model.integrator.sol.u[end] ≈ Float32[187.27687, 138.03664, 122.17141, 1504.5299]
    empty!(Base.ARGS)
end
