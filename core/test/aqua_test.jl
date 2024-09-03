@testitem "Aqua" begin
    import Aqua
    using DataInterpolations: AbstractInterpolation
    Aqua.test_all(Ribasim; ambiguities = false, persistent_tasks = false)
end
