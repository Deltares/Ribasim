@testitem "Aqua" begin
    import Aqua
    using FindFirstFunctions: Guesser
    Aqua.test_all(
        Ribasim;
        ambiguities = false,
        persistent_tasks = false,
        # TODO: Remove after https://github.com/SciML/FindFirstFunctions.jl/pull/26
        piracies = (treat_as_own = [Guesser],),
    )
end
