# Ribasim NetCDF compression variants (issue #3358)

The `basic` test model, run once per `[results]` setting. Each `results_<variant>` directory
holds the results of `ribasim_<variant>.toml`. Open any TOML in the QGIS plugin to load the model
with that variant's results.

| Variant | `[results]` settings |
|:--|:--|
| uncompressed | `compression = false` |
| deflate1 | `compression = true`, `compression_level = 1` (current option) |
| bitround20_shuffle_deflate1 | as deflate1, plus `significant_bits = 20` |
| zstd3 | `compression = true`, `compression_algorithm = "zstd"`, `compression_level = 3` |
| bitround20_shuffle_zstd3 | as zstd3, plus `significant_bits = 20` |

- With `significant_bits = 20`, the floating point variables are quantized with BitRound and get the
  shuffle filter. Time, IDs and `basin_state.nc` are left as they are. The relative error is at most 4.77e-7.
- The zstd variants need an HDF5 zstd filter plugin (HDF5 filter ID 32015) to read. Readers without
  one fail with "NetCDF: Filter error: undefined filter encountered".
- `solver_stats.nc` `computation_time` is wall clock time, so it differs between the variants.
