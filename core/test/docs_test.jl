@testitem "Doctests" begin
    using Documenter

    DocMeta.setdocmeta!(Ribasim, :DocTestSetup, :(using Ribasim); recursive = true)

    doctest(Ribasim; manual = false)
end
