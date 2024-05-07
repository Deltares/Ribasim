@testitem "Aqua" begin
    import Aqua
    Aqua.test_all(Ribasim; ambiguities = false)
end
