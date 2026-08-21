@testitem "Aqua" begin
    import Aqua
    using DataInterpolations
    Aqua.test_all(
        Ribasim;
        ambiguities = false,
        persistent_tasks = false,
        piracies = (; treat_as_own = [LinearInterpolationIntInv]), # Remove with https://github.com/Deltares/Ribasim/issues/3197
        stale_deps = false,
    )
end
