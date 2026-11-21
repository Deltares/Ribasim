# Wflow coupled

A proof of concept for online coupling of [Ribasim](https://github.com/Deltares/Ribasim) and [Wflow](https://github.com/Deltares/Wflow.jl), see Ribasim issue [#16](https://github.com/Deltares/Ribasim/issues/16).
Wflow SBM computes the land hydrology, and the runoff that Wflow would route into its rivers is passed to Ribasim Basins and FlowBoundaries every timestep instead.

- `build_piave_wflow.py` uses HydroMT to build a Wflow model of the Piave catchment for July 2010, including non-paddy irrigation demand.
  The static maps come from the HydroMT artifact data, and the ERA5 forcing from the HydroMT `deltares_data` catalog, which requires access to the Deltares P: drive.
- `build_piave_ribasim.py` uses HydroMT-Ribasim to build a Ribasim network from the Wflow static maps, with a placeholder irrigation UserDemand for each part of a Basin, split by Wflow allocation area, that contains irrigated Wflow cells.
- `build_mapping.jl` writes `coupling.gpkg`, which maps each Wflow river cell to a Ribasim Basin or FlowBoundary, and each irrigated Wflow cell to a Ribasim UserDemand.
- `online.jl` runs both models in online coupling, configured by `coupling.toml`, and writes `coupling_diagnostics.csv`.
  Each timestep Wflow computes its irrigation demand, Ribasim supplies it through its UserDemands, Wflow applies the realized supply, and the resulting Wflow runoff enters Ribasim in the next timestep, see candidate A in Ribasim issue [#3309](https://github.com/Deltares/Ribasim/issues/3309#issuecomment-6341186300).
  Set `coupled_irrigation = false` in `coupling.toml` to only couple the runoff.
- `plotting/plot_irrigation.jl` plots the demand, allocated and realized irrigation per UserDemand from the Ribasim allocation results to `plotting/irrigation.png`.
  It uses CairoMakie, which is not a dependency of this project, so it needs to be available in for instance your default Julia environment.

This uses the `wflow-coupled` Pixi environment, from the root of the repository run:

```sh
pixi run wflow-coupled-prepare  # build the Wflow and Ribasim models, and the mapping between them
pixi run wflow-coupled-run      # run both models in online coupling
```

The Julia project in this directory is part of the Ribasim Julia workspace, so it uses Ribasim from this repository.
HydroMT-Ribasim is not yet public, so the `wflow-coupled` Pixi environment requires read access to it.
