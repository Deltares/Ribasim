using Documenter
#using bach

pages = [
    "ModelingToolkit" => [
        "modeling_toolkit/intro.md",
    ]
    "Coupling to MODFLOW6" => [
        "modflow_coupling/modflow_concepts.md",
        "modflow_coupling/modflow_water_levels.md",
    ]
]

makedocs(
    sitename = "bach",
    format = Documenter.HTML(),
    pages = pages,
#    modules = [bach]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
