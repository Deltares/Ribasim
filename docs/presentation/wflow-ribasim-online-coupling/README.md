# Wflow-Ribasim online coupling figures

This folder contains the Python generators and PNG figures for the
Wflow-Ribasim online coupling presentation, including irrigation allocation.
The talk is about 10 minutes, for modellers. The scripts are numbered in slide order:

| Slide | Message | Figure |
|---|---|---|
| 1 | Title | |
| 2 | Two strengths, one model: Wflow hydrology + Ribasim water management | `01_combined_strengths.png` |
| 3 | The idea, step by step (one slide per build step) | `02a_concept_wflow.png`, `02b_concept_coupled.png`, `02c_concept_irrigation.png` |
| 4 | From grid to network in the Piave | `03_piave_grid_to_network.png` |
| 5 | Irrigated cells become Ribasim UserDemands | `04_irrigation_cells_to_userdemand.png` |
| 6 | One coupled day | `05_coupled_timestep_cycle.png` |
| 7 | Results: water is conserved, irrigation is short when the river cannot deliver | `06_irrigation_results.png` |
| 8 | What's next | `07_roadmap.png` |

Backup slides are in `figures/backup`: the water balance of the exchange (`b1`), the
modular Wflow architecture (`b2`) and the annotated original figures of PR #3324 and
#3333 (`b3a`-`b3c`).

Run all generators from the repository root with:

```powershell
& .\.pixi\envs\default\python.exe docs\presentation\wflow-ribasim-online-coupling\make_all.py
```

The scripts use the Piave proof-of-concept data in `wflow-coupled`. Set the
`RIBASIM_REPO` environment variable when running them from another checkout.
The `source_images` folder contains the original figures from the referenced
pull requests used by the annotated presentation figures.
