@testitem "Accuracy" begin
    @test Ribasim.kahan_sum(1.0, 1.0e16, 1.0, -1.0e16) ≈ 2.0
end
