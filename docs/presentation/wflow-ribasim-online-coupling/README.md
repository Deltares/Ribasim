# Wflow-Ribasim online coupling figures

This folder contains the Python generators and PNG figures for the
Wflow-Ribasim online coupling presentation, including irrigation allocation.
The talk is about 10 minutes, for modellers. The scripts are numbered in slide order:

The slide order, presenters and talking points are in `talking_points.md`.
The figures have no titles of their own: each script records its slide title in
`figures/titles.json` (set `FIGURE_TITLES=1` to draw them in the figure instead), and
`save()` enlarges text that would be smaller than 12 pt on the slide.

| Figure | Slide |
|---|---|
| `01_combined_strengths.png` | Two strengths, one coupled model |
| `02a`, `02b`, `02c_concept_*.png` | The idea, step by step (full-bleed) |
| `03_piave_grid_to_network.png` | From grid to network in the Piave |
| `08_outlet_discharge.png` | The river coupling works (left half) |
| `06_river_exchange.png` | The river coupling works (right half) |
| `04_irrigation_cells_to_userdemand.png` | Irrigated cells become Ribasim UserDemands |
| `05_coupled_timestep_cycle.png` | One coupled day |
| `07_irrigation_loop.png` | The irrigation loop works |

Backup figures are in `figures/backup`: the water balance of the exchange (`b1`), the
modular Wflow architecture (`b2`), the annotated original figures of PR #3324 and
#3333 (`b3a`-`b3c`), the irrigation results per UserDemand (`b4`) and the roadmap (`b5`).

Run all generators from the repository root with:

```powershell
& .\.pixi\envs\default\python.exe docs\presentation\wflow-ribasim-online-coupling\make_all.py
```

The scripts use the Piave proof-of-concept data in `wflow-coupled`. Set the
`RIBASIM_REPO` environment variable when running them from another checkout.
The `source_images` folder contains the original figures from the referenced
pull requests, the Wflow SBM concept figure from the Wflow.jl documentation and the
photos for the bio slides (`presenters`).

The outlet comparison (`08_outlet_discharge.py`) uses rleander73's five-year validation
runs (PR #3390), which are not in the repository. Their daily outlet discharge is cached in
`data/outlet_discharge_daily.csv`; delete it and set `VALIDATION_DIR` to the folder with the
runs to rebuild it.

Build the PowerPoint deck from the Deltares template (needs PowerPoint) with:

```powershell
& .\docs\presentation\wflow-ribasim-online-coupling\build_deck.ps1
```

It reads `template_2.pptx` and the DSD presenter bio template from `-TemplateDir`.
