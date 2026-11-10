"""Irrigation results of the coupled Piave run: demand, allocated and realized per UserDemand.

Extends the plot in PR #3333 with the shortage and its physical cause: a UserDemand stops
abstracting when the level of its source Basin drops below `min_level`.
"""

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import xarray as xr
from common import (
    DATABASE,
    DIAGNOSTICS,
    RESULTS,
    C,
    load_ribasim_network,
    save,
    setup_style,
    slide_title,
)
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

SHORTAGE_TOLERANCE = 1e-3  # m3/s

setup_style()
allocation = xr.open_dataset(RESULTS / "allocation.nc").sum("demand_priority")
basin_results = xr.open_dataset(RESULTS / "basin.nc")
static = (
    gpd.read_file(DATABASE, layer="UserDemand / static")
    .groupby("node_id")
    .min_level.min()
)
_, _, nodes, links = load_ribasim_network()
basin_ids = nodes.index[nodes.node_type == "Basin"]

time = pd.to_datetime(allocation.time.values)
dt = (time[1] - time[0]).total_seconds()
edges = np.r_[time.values, (time[-1] + (time[1] - time[0])).to_datetime64()]
node_ids = [int(n) for n in allocation.node_id.values]

diagnostics = pd.read_csv(DIAGNOSTICS)
max_error = diagnostics.error_m3s.abs().max()

demand_total = float((allocation.demand * dt).sum()) / 1e3
supplied_total = float((allocation.supplied * dt).sum()) / 1e3
shortage_total = demand_total - supplied_total

fig = plt.figure(figsize=(19, 10.5))
slide_title(
    fig,
    "Results: water is conserved, irrigation is short when the river cannot deliver",
    "Piave, July 2010: Ribasim allocates the Wflow demand, but physics decides what is really abstracted",
)
gs = fig.add_gridspec(
    len(node_ids) + 1,
    2,
    height_ratios=[0.42] + [1] * len(node_ids),
    width_ratios=[2.1, 1],
    left=0.06,
    right=0.98,
    top=0.86,
    bottom=0.08,
    hspace=0.45,
    wspace=0.12,
)

# KPI cards
kpi = fig.add_subplot(gs[0, :])
kpi.set_axis_off()
cards = [
    ("Irrigation demand  [thousand m³]", f"{demand_total:,.0f}", "", C["dark"]),
    (
        "Realized supply  [thousand m³]",
        f"{supplied_total:,.0f}",
        f"({supplied_total / demand_total:.0%})",
        C["irrigation"],
    ),
    (
        "Shortage  [thousand m³]",
        f"{shortage_total:,.0f}",
        f"({shortage_total / demand_total:.0%})",
        C["shortage"],
    ),
    (
        "Water balance error",
        f"{max_error:.0e}",
        "m³/s  (max)",
        C["ribasim"],
    ),
]
for k, (label, value, unit, color) in enumerate(cards):
    x = 0.0 + k * 0.255
    kpi.add_patch(
        plt.Rectangle(
            (x, 0.0),
            0.235,
            1.0,
            transform=kpi.transAxes,
            facecolor=C["light"],
            edgecolor="none",
        )
    )
    kpi.add_patch(
        plt.Rectangle(
            (x, 0.0),
            0.012,
            1.0,
            transform=kpi.transAxes,
            facecolor=color,
            edgecolor="none",
        )
    )
    kpi.text(
        x + 0.03,
        0.72,
        label,
        transform=kpi.transAxes,
        fontsize=15,
        color=C["muted"],
        va="center",
    )
    kpi.text(
        x + 0.03,
        0.3,
        value,
        transform=kpi.transAxes,
        fontsize=30,
        color=color,
        fontweight="bold",
        va="center",
    )
    kpi.text(
        x + 0.03 + 0.019 * len(value),
        0.27,
        unit,
        transform=kpi.transAxes,
        fontsize=14,
        color=C["muted"],
        va="center",
    )

flow_axes = []
for row, node_id in enumerate(node_ids, start=1):
    demand = allocation.demand.sel(node_id=node_id).values
    allocated = allocation.allocated.sel(node_id=node_id).values
    supplied = allocation.supplied.sel(node_id=node_id).values
    source = int(
        links[
            (links.to_node_id == node_id) & links.from_node_id.isin(basin_ids)
        ].from_node_id.iloc[0]
    )
    level = basin_results.level.sel(node_id=source).values
    min_level = float(static.loc[node_id])
    short = demand - supplied > SHORTAGE_TOLERANCE

    ax = fig.add_subplot(gs[row, 0], sharex=flow_axes[0] if flow_axes else None)
    flow_axes.append(ax)
    for i in np.nonzero(short)[0]:
        ax.axvspan(edges[i], edges[i + 1], color=C["shortage"], alpha=0.07, lw=0)
    ax.stairs(
        supplied, edges, fill=True, color=C["irrigation"], alpha=0.85, label="realized"
    )
    ax.fill_between(
        edges,
        np.r_[supplied, supplied[-1]],
        np.r_[demand, demand[-1]],
        step="post",
        where=np.r_[short, False],
        facecolor="none",
        edgecolor=C["shortage"],
        hatch="////",
        lw=0,
        label="shortage",
    )
    ax.stairs(demand, edges, color=C["dark"], lw=2.5, ls=":", label="demand")
    ax.stairs(allocated, edges, color=C["ribasim"], lw=2.2, ls="--", label="allocated")
    ax.set_ylabel("m³/s")
    ax.set_ylim(0, max(demand.max(), allocated.max()) * 1.15)
    ax.set_title(
        f"UserDemand #{node_id}  ·  from Basin #{source}", loc="left", fontsize=16
    )
    ax.grid(axis="y", color=C["light"])

    ax_level = fig.add_subplot(gs[row, 1], sharex=flow_axes[0])
    for i in np.nonzero(short)[0]:
        ax_level.axvspan(edges[i], edges[i + 1], color=C["shortage"], alpha=0.07, lw=0)
    ax_level.stairs(level, edges, color=C["water_dark"], lw=3, baseline=None)
    low = min(level.min(), min_level)
    span = max(level.max(), min_level) - low
    ax_level.set_ylim(low - 0.15 * span, max(level.max(), min_level) + 0.25 * span)
    ax_level.axhspan(
        ax_level.get_ylim()[0], min_level, color=C["shortage"], alpha=0.12, lw=0
    )
    ax_level.axhline(min_level, color=C["shortage"], lw=2, ls="--")
    ax_level.text(
        edges[len(edges) // 2],
        min_level,
        "min_level",
        color=C["shortage"],
        ha="center",
        va="top",
        fontsize=12,
        fontweight="bold",
    )
    ax_level.set_title(
        f"Basin #{source} level", loc="left", fontsize=16, color=C["water_dark"]
    )
    ax_level.set_ylabel("m")
    ax_level.grid(axis="y", color=C["light"])

for ax in fig.axes[1:]:
    # Weekly ticks within the run only, so the end of the run (1 Aug) gets no colliding label
    ax.set_xticks(pd.date_range(time[0], time[-1], freq="7D"))
    ax.xaxis.set_major_formatter(plt.matplotlib.dates.DateFormatter("%d %b"))
for ax in fig.axes[1:-2]:
    ax.tick_params(labelbottom=False)

handles = [
    Patch(facecolor=C["irrigation"], label="realized supply"),
    Line2D([], [], color=C["dark"], ls=":", lw=2.5, label="Wflow demand"),
    Line2D([], [], color=C["ribasim"], ls="--", lw=2.2, label="Ribasim allocated"),
    Patch(facecolor="none", edgecolor=C["shortage"], hatch="////", label="shortage"),
    Line2D([], [], color=C["water_dark"], lw=3, label="Basin level"),
    Line2D(
        [],
        [],
        color=C["shortage"],
        ls="--",
        lw=2,
        label="min_level (no abstraction below)",
    ),
]
fig.legend(
    handles=handles, loc="lower center", ncols=6, fontsize=13, bbox_to_anchor=(0.5, 0.0)
)

save(fig, "06_irrigation_results.png")
