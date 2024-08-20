@testitem "Aqua" begin
    import Aqua
    using DataInterpolations: AbstractInterpolation
    Aqua.test_all(
        Ribasim;
        ambiguities = false,
        persistent_tasks = false,
        # TODO: Remove AbstractInterpolation exception when DataInterpolations
        # is supported in SparseConnectivityTracer
        piracies = (treat_as_own = [AbstractInterpolation],),
    )
end
