# Wflow-Ribasim online coupling figures

This folder contains the Python generators and PNG figures for the
Wflow-Ribasim online coupling presentation, including irrigation allocation.

Run all generators from the repository root with:

```powershell
& .\.pixi\envs\default\python.exe docs\presentation\wflow-ribasim-online-coupling\make_all.py
```

The scripts use the Piave proof-of-concept data in `wflow-coupled`. Set the
`RIBASIM_REPO` environment variable when running them from another checkout.
The `source_images` folder contains the original figures from the referenced
pull requests used by the annotated presentation figures.
