module create_binaries

using Artifacts
using PackageCompiler
using TOML
using LibGit2

export build_app, build_lib

include("add_metadata.jl")
include("create_app.jl")
include("create_lib.jl")

end
