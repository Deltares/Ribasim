"""The river coupling works: outflow at the Piave outlet, coupled model vs stand-alone Wflow.

Uses the five-year (2010-2014) validation runs by rleander73 (PR #3390): the Ribasim flow on
the link into the Terminal of the coupled run, against the outlet discharge (`river_q`) of a
stand-alone Wflow run with the same forcing. The Wflow values are shifted to the start of the
timestep, like the Ribasim mean flows, as in his `plot_outflow_seasonal.py`.

The daily values are cached in data/outlet_discharge_daily.csv, so the figure can be redrawn
without the validation runs. Set VALIDATION_DIR to the folder with the runs to rebuild it.

Drawn for the left half of the results slide; the right half holds 06_river_exchange.png.
The plot shows monthly means: the volumes match, while the daily peaks of the coupled model
are lower because the Ribasim Basins store part of each flood wave (see the talking points).
"""

import os
from pathlib import Path

import geopandas as gpd
import matplotlib.pyplot as plt
import pandas as pd
import xarray as xr
from common import HALF_CONTENT_BOX, HERE, C, badge, save, setup_style

CACHE = HERE / "data" / "outlet_discharge_daily.csv"
VALIDATION_DIR = Path(
    os.environ.get(
        "VALIDATION_DIR",
        r"N:\Deltabox\Postbox\Koning,de Bart\van_Robert\wflow-ribasim-validatie",
    )
)
SINK_TYPES = ("Terminal", "LevelBoundary")


def read_validation_runs(folder: Path) -> pd.DataFrame:
    """Daily outlet discharge of the coupled Ribasim and the stand-alone Wflow run."""
    database = folder / "ribasim_piave" / "input" / "database.gpkg"
    node = gpd.read_file(database, layer="Node", fid_as_index=True)
    link = gpd.read_file(database, layer="Link", fid_as_index=True)
    sinks = node.index[node.node_type.isin(SINK_TYPES)]
    outlet_links = link.index[(link.link_type == "flow") & link.to_node_id.isin(sinks)]
    flow = xr.open_dataset(folder / "ribasim_piave" / "results" / "flow.nc")
    ribasim = flow.flow_rate.sel(link_id=list(outlet_links)).sum("link_id").to_series()

    wflow = pd.read_csv(
        folder / "wflow_piave" / "run_default_klad" / "output.csv",
        parse_dates=["time"],
        index_col="time",
    )
    wflow = wflow.filter(like="river_q").sum(axis=1)
    wflow.index = wflow.index - pd.Timedelta(days=1)

    daily = pd.DataFrame({"ribasim_m3s": ribasim, "wflow_m3s": wflow}).dropna()
    daily.index.name = "date"
    return daily


if not CACHE.exists():
    CACHE.parent.mkdir(exist_ok=True)
    read_validation_runs(VALIDATION_DIR).to_csv(CACHE, float_format="%.4f")
daily = pd.read_csv(CACHE, parse_dates=["date"], index_col="date")
monthly = daily.resample("MS").mean()
mean_ribasim, mean_wflow = daily.mean()
difference = 100 * (mean_ribasim - mean_wflow) / mean_wflow

setup_style()
fig, ax = plt.subplots(figsize=(8, 7))
ax.plot(
    monthly.index,
    monthly.wflow_m3s,
    color=C["wflow"],
    lw=4,
    label="stand-alone Wflow",
)
ax.plot(
    monthly.index,
    monthly.ribasim_m3s,
    color=C["ribasim"],
    lw=0,
    marker="o",
    markersize=8,
    markeredgecolor="white",
    markeredgewidth=1.5,
    label="coupled: Ribasim outflow",
)
ax.set_ylabel("monthly mean outflow  [m³/s]")
ax.set_ylim(0, monthly.max().max() * 1.45)
ax.legend(loc="upper right", bbox_to_anchor=(1.0, 0.86), fontsize=14)
ax.grid(axis="y", color=C["light"])
ax.xaxis.set_major_locator(plt.matplotlib.dates.YearLocator())
ax.xaxis.set_major_formatter(plt.matplotlib.dates.DateFormatter("%Y"))
badge(
    ax,
    0.03,
    0.93,
    f"same volume: mean {mean_ribasim:.0f} vs {mean_wflow:.0f} m³/s ({difference:+.1f} %)",
    C["ribasim"],
    fontsize=15,
    ha="left",
    transform=ax.transAxes,
)
fig.tight_layout()

save(fig, "08_outlet_discharge.png", box=HALF_CONTENT_BOX)
