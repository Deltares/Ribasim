import Pkg

"""
Update the Julia Manifest.toml and show the changes as well as outdated packages.
The output is written to a file that can be used as the body of a pull request.
"""
function (@main)(_)
    path = normpath(@__DIR__, "../.pixi/update-manifest-julia.md")
    redirect_stdio(; stdout = path, stderr = path) do
        println("Update the Julia Manifest.toml to get the latest dependencies.\n")
        println("Output of `Pkg.update()`\n```")
        Pkg.update()
        println("```\n\nOutput of `Pkg.status(; outdated=true)`\n```")
        Pkg.status(; outdated = true)
        println("```")
    end
end
