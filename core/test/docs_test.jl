using Test
using Documenter
using Ribasim

DocMeta.setdocmeta!(Ribasim, :DocTestSetup, :(using Ribasim); recursive = true)

@testset "Doctests" begin
    doctest(Ribasim; manual = false)
end
