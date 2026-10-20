# Wflow coupled

A proof of concept for online coupling of [Ribasim](https://github.com/Deltares/Ribasim) and [Wflow](https://github.com/Deltares/Wflow.jl), see Ribasim issue [#16](https://github.com/Deltares/Ribasim/issues/16).
Wflow SBM computes the land hydrology, and the runoff that Wflow would route into its rivers is passed to Ribasim Basins and FlowBoundaries every timestep instead.

- `build_piave_wflow.py` uses HydroMT to build a Wflow model of the Piave catchment.
- `build_piave_ribasim.py` uses HydroMT-Ribasim to build a Ribasim network from the Wflow static maps.
- `build_mapping.jl` writes `coupling.gpkg`, which maps each Wflow river cell to a Ribasim Basin or FlowBoundary.
- `online.jl` runs both models in online coupling, configured by `coupling.toml`, and writes `coupling_diagnostics.csv`.

This uses the `wflow-coupled` Pixi environment, from the root of the repository run:

```sh
pixi run wflow-coupled-prepare  # build the Wflow and Ribasim models, and the mapping between them
pixi run wflow-coupled-run      # run both models in online coupling
```

The Julia project in this directory is part of the Ribasim Julia workspace, so it uses Ribasim from this repository.
HydroMT-Ribasim is not yet public, so the `wflow-coupled` Pixi environment requires read access to it.
