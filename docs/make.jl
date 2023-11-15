cd(@__DIR__)

using Documenter, Ribasim
using DocumenterMarkdown

DocMeta.setdocmeta!(Ribasim, :DocTestSetup, :(using Ribasim); recursive = true)

makedocs(;
    modules = [Ribasim, Ribasim.config],
    format = Markdown(),
    repo = "https://github.com/Deltares/Ribasim.jl/blob/{commit}{path}#L{line}",
    sitename = "Ribasim.jl",
    authors = "Deltares and contributors",
    doctest = false,  # we doctest as part of normal CI
)

# TODO Make fully compatible with Quarto, like LaTeX and references
