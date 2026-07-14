"""
Generate the Ribasim irrigation coupling example model.

Starts from the standard ``allocation_example_model`` (two basins, two
UserDemand nodes, a LinearResistance connector, and a TabulatedRatingCurve
outlet) and enables the irrigation coupling flag so the Julia side knows to
wire in the Wflow soil model.

Topology (from the allocation docs example)::

    FlowBoundary 1 ─► Basin 2 ─► UserDemand 3 (priority 1)
                         └► LinearResistance 4 ─► Basin 5 ─► UserDemand 6 (priority 3)
                                                          └► TabulatedRatingCurve 7 ─► Terminal 8

The model runs for 30 days (2020-01-01 to 2020-01-31) to match the 30-day
default synthetic forcing of the irrigation module.

Run from the repo root::

    pixi run python irrigation/example/generate_model.py
"""

import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd
from ribasim.config import Allocation, Experimental
from ribasim_testmodels import allocation_example_model

sys.path.insert(0, str(Path(__file__).parent))
from plot_results import plot_results, read_allocation, read_logger

sys.path.insert(0, str(Path(__file__).parent))

OUT_DIR = Path(__file__).parent / "irrigation_model" / "irrigation_model.toml"

# ───────────────────────────────────────────────────────────────────────────
model = allocation_example_model()

# Extend to 30 days so it matches the irrigation module default forcing length
model.endtime = datetime(2020, 1, 31)

# Run allocation every day to match the soil model's daily timestep
model.allocation = Allocation(dt=86400.0)

# Enable irrigation coupling (keeps allocation=True and concentration=True from the base model)
model.experimental = Experimental(
    allocation=True,
    concentration=True,
    irrigation=True,
)

# ── Irrigation soil model inputs ──────────────────────────────────────────────
# Irrigated area per UserDemand node [m²] — 10 km² creates realistic demand vs 2 m³/s supply
IRRIGATED_AREA_M2 = 1e7
user_demand_node_ids = list(model.user_demand.node.df.index)

model.user_demand.irrigation_static.df = pd.DataFrame(
    {
        "node_id": user_demand_node_ids,
        "irrigated_area_m2": [IRRIGATED_AREA_M2] * len(user_demand_node_ids),
    }
)

# 30-day synthetic forcing matching Irrigation.default_forcing():
#   precipitation : 1 mm/day for days 1-15, 30 mm/day for days 16-30
#   potential ET  : 6 mm/day for days 1-15,  0 mm/day for days 16-30
timestamps = [model.starttime + timedelta(days=i) for i in range(1, 31)]
precip = [1.0] * 15 + [30.0] * 15
pet = [6.0] * 15 + [0.0] * 15

rows = []
for node_id in user_demand_node_ids:
    for t, p, e in zip(timestamps, precip, pet, strict=True):
        rows.append(
            {
                "node_id": node_id,
                "time": t,
                "precipitation": p,
                "potential_evaporation": e,
            }
        )
model.user_demand.irrigation_forcing.df = pd.DataFrame(rows)

# ───────────────────────────────────────────────────────────────────────────
OUT_DIR.parent.mkdir(exist_ok=True)
model.write(OUT_DIR)
print(f"Model written to: {OUT_DIR.resolve()}")
print(f"UserDemand nodes: {list(model.user_demand.node.df.index)}")

# ── Run the coupled Julia simulation ──────────────────────────────────────────
REPO_ROOT = Path(__file__).parent.parent.parent
coupled_script = Path(__file__).parent / "coupled_irrigation.jl"
print("\nRunning coupled_irrigation.jl …")
result = subprocess.run(
    ["julia", f"--project={Path(__file__).parent.parent}", str(coupled_script)],
    cwd=REPO_ROOT,
)
if result.returncode != 0:
    print("coupled_irrigation.jl failed — skipping plots.")
    sys.exit(result.returncode)

# ── Plot irrigation results ───────────────────────────────────────────────────
NC_DIR = OUT_DIR.parent
nc_path = NC_DIR / "coupled_irrigation.nc"
allocation_nc = NC_DIR / "results" / "allocation.nc"

if nc_path.exists():
    results, nsteps, initial_total_storage, ribasim_node_ids, irrigated_area_m2 = (
        read_logger(nc_path)
    )
    allocation = read_allocation(allocation_nc) if allocation_nc.exists() else None
    if allocation is None:
        print("No allocation.nc found — plotting without Ribasim network results.")
    n_cols = results["rec_demand"].shape[0]
    for icol in range(n_cols):
        node_id = int(ribasim_node_ids[icol]) if ribasim_node_ids is not None else None
        plot_results(
            results,
            nsteps,
            initial_total_storage,
            NC_DIR / f"coupled_irrigation_col{icol}.png",
            icol=icol,
            ribasim_node_id=node_id,
            allocation=allocation,
            irrigated_area_m2=float(irrigated_area_m2[icol]),
        )
else:
    print(f"Skipping plot — {nc_path} not found.")
