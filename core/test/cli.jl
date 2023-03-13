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
