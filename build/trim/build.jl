# Build a trimmed Ribasim executable, see build/trim/README.md
# Usage: julia --project build/trim/build.jl
using JuliaC

output_dir = abspath(joinpath(@__DIR__, "out"))
rm(output_dir; force = true, recursive = true)

ld_flags = String[]
# Use Julia's bundled lld, see build/build.jl
if Sys.islinux()
    bundled_lld = normpath(Sys.BINDIR, "..", "libexec", "julia", "lld")
    lld_dir = mktempdir()
    symlink(bundled_lld, normpath(lld_dir, "ld"))
    ld_flags = ["-B$lld_dir"]
end

image_recipe = ImageRecipe(;
    output_type = "--output-exe",
    file = joinpath(@__DIR__, "ribasim_trim.jl"),
    project = normpath(@__DIR__, "../../core"),
    trim_mode = "safe",
    # JuliaC's default when not set, for binaries that run on other machines
    cpu_target = get(ENV, "RIBASIM_TRIM_CPU_TARGET", nothing),
    verbose = true,
)
link_recipe = LinkRecipe(;
    image_recipe,
    outname = joinpath(output_dir, "bin", "ribasim_trim"),
    rpath = "@bundle",
    ld_flags,
)
bundle_recipe = BundleRecipe(; link_recipe, output_dir)

compile_products(image_recipe)
link_products(link_recipe)
bundle_products(bundle_recipe)
