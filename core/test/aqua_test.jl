@testitem "Aqua" begin
    import Aqua
    Aqua.test_all(
        Ribasim;
        ambiguities = false,
        persistent_tasks = false,
        piracies = true,
    )
end
