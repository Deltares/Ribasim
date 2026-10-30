# Run a model once per NetCDF compression variant, see issue #3358.
# Usage: julia --project=core utils/netcdf-compression/run_variants.jl <model_dir> <out_dir>
# The zstd variants need HDF5_PLUGIN_PATH to point to the HDF5 filter plugins.
import Ribasim

model_dir, out_dir = ARGS
mkpath(out_dir)
cp(joinpath(model_dir, "input"), joinpath(out_dir, "input"); force = true)
base = read(joinpath(model_dir, "ribasim.toml"), String)
base = replace(base, "verbosity = \"debug\"" => "verbosity = \"info\"")

variants = [
    "uncompressed" => "compression = false",
    "deflate1" => "compression = true\ncompression_level = 1",
    "bitround20_shuffle_deflate1" => "compression = true\ncompression_level = 1\nsignificant_bits = 20",
    "zstd3" => "compression = true\ncompression_algorithm = \"zstd\"\ncompression_level = 3",
    "bitround20_shuffle_zstd3" => "compression = true\ncompression_algorithm = \"zstd\"\ncompression_level = 3\nsignificant_bits = 20",
]
for (name, results) in variants
    toml = replace(base, "results_dir = \"results\"" => "results_dir = \"results_$name\"")
    toml *= "\n[results]\n$results\n"
    path = joinpath(out_dir, "ribasim_$name.toml")
    write(path, toml)
    Ribasim.main(path) == 0 || error("Variant $name failed")
    rm(joinpath(out_dir, "results_$name", "ribasim.log"); force = true)
end
