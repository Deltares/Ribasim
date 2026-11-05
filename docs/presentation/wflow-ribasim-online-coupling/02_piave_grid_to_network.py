"""Piave proof of concept on real data: Wflow grid, Ribasim network, and the cell-to-node mapping.

Recreates (and extends) the QGIS figure in PR #3324: every Wflow river cell sends its runoff to
exactly one Ribasim Basin or FlowBoundary.
"""

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
from common import (
    WFLOW_DIR,
    C,
    badge,
    basin_colors,
    fig_arrow,
    grid_extent,
    hillshade_rgba,
    load_mapping,
    load_ribasim_network,
    load_wflow,
    map_axis,
    north_up,
    save,
    setup_style,
    slide_title,
)
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

NODE_STYLE = {
    "Basin": {
        "marker": [(-1, 1), (1, 1), (0.6, -1), (-0.6, -1)],
        "color": "#0072B2",
        "s": 110,
    },
    "FlowBoundary": {"marker": "o", "color": "#FF7F00", "s": 90},
    "ManningResistance": {"marker": "v", "color": "#F0E442", "s": 45},
    "LinearResistance": {"marker": "^", "color": "#009E73", "s": 45},
    "UserDemand": {"marker": "s", "color": "#E41A1C", "s": 80},
}

setup_style()
ds = load_wflow()
lon, lat = ds.longitude.values, ds.latitude.values
extent = grid_extent(lon, lat)
elevation = north_up(ds["land_elevation"].values, lat)
river_mask = north_up(ds["river_mask"].values, lat)
region = gpd.read_file(WFLOW_DIR / "staticgeoms" / "basins.geojson")
basin_area, flow_boundary_area, nodes, links = load_ribasim_network()
mapping = load_mapping()
rivers = mapping[mapping.node_type != "UserDemand"]
colors = basin_colors(basin_area.node_id)

fig, axes = plt.subplots(1, 3, figsize=(20, 9.2))
fig.subplots_adjust(left=0.01, right=0.99, top=0.75, bottom=0.1, wspace=0.08)
slide_title(
    fig,
    "From grid to network: the Piave catchment",
    "Every Wflow river cell delivers its runoff to exactly one Ribasim node",
)

# (a) Wflow: elevation and river cells on the grid
ax = axes[0]
ax.imshow(
    hillshade_rgba(elevation, vmin=0, vmax=2600), extent=extent, interpolation="nearest"
)
river_rgba = np.zeros((*river_mask.shape, 4))
river_rgba[river_mask == 1] = (0.12, 0.44, 0.70, 1.0)
ax.imshow(river_rgba, extent=extent, interpolation="nearest")
region.boundary.plot(ax=ax, color=C["dark"], lw=1.5)
map_axis(ax)
ax.set_title(
    "Wflow: grid cells (~1 km)", color=C["wflow"], loc="left", fontsize=24, pad=38
)
ax.text(
    0,
    1.01,
    "data from HydroMT Wflow",
    transform=ax.transAxes,
    fontsize=19,
    color=C["dark"],
    va="bottom",
    fontweight="bold",
)
n_land = int(np.isfinite(elevation).sum())
badge(
    ax,
    0.03,
    -0.07,
    f"{n_land:,} land cells\n{len(rivers)} river cells",
    C["wflow"],
    fontsize=17,
    ha="left",
    transform=ax.transAxes,
)

# (b) Ribasim: areas and network
ax = axes[1]
basin_area.plot(ax=ax, color=basin_area.node_id.map(colors), edgecolor="white", lw=1.2)
flow_boundary_area.plot(
    ax=ax, color=C["flowboundary"], edgecolor="white", lw=1.2, hatch="///", alpha=0.75
)
links.plot(ax=ax, color=C["dark"], lw=1.4)
for node_type, style in NODE_STYLE.items():
    sub = nodes[nodes.node_type == node_type]
    if len(sub):
        ax.scatter(
            sub.geometry.x,
            sub.geometry.y,
            edgecolor="white",
            linewidth=1,
            zorder=5,
            **style,
        )
map_axis(ax)
ax.set_xlim(extent[:2])
ax.set_ylim(extent[2:])
ax.set_title(
    "Ribasim: areas + node network",
    color=C["ribasim"],
    loc="left",
    fontsize=24,
    pad=38,
)
ax.text(
    0,
    1.01,
    "data from HydroMT Ribasim",
    transform=ax.transAxes,
    fontsize=19,
    color=C["dark"],
    va="bottom",
    fontweight="bold",
)
counts = nodes.node_type.value_counts()
badge(
    ax,
    0.03,
    -0.07,
    f"{counts.get('Basin', 0)} Basins\n{counts.get('FlowBoundary', 0)} FlowBoundaries",
    C["ribasim"],
    fontsize=17,
    ha="left",
    transform=ax.transAxes,
)
handles = [
    Line2D(
        [],
        [],
        ls="",
        marker=s["marker"],
        color=s["color"],
        markersize=14,
        markeredgecolor="white",
        label=t,
    )
    for t, s in NODE_STYLE.items()
    if t in counts.index and t != "LinearResistance"
]
handles.append(
    Patch(
        facecolor=C["flowboundary"],
        hatch="///",
        edgecolor="white",
        label="FlowBoundary area",
    )
)
ax.legend(
    handles=handles,
    loc="lower right",
    fontsize=16,
    ncols=1,
    bbox_to_anchor=(1.08, 0.08),
)

# (c) Coupling: river cells coloured by the receiving node
ax = axes[2]
basin_area.plot(
    ax=ax, color=basin_area.node_id.map(colors), edgecolor="white", lw=1.2, alpha=0.35
)
flow_boundary_area.plot(
    ax=ax, color=C["flowboundary"], edgecolor="white", lw=1.2, alpha=0.35
)
in_basin = rivers.node_type == "Basin"

cell_colors = [
    c if b else C["flowboundary"]
    for c, b in zip(rivers.node_id.map(colors), in_basin, strict=False)
]
ax.scatter(
    rivers.longitude,
    rivers.latitude,
    s=26,
    marker="s",
    c=cell_colors,
    edgecolor=C["dark"],
    linewidth=0.5,
    zorder=4,
)
basins = nodes[nodes.node_type.isin(["Basin", "FlowBoundary"])]
for node_id, node in basins.iterrows():
    ax.annotate(
        f"#{node_id}",
        (node.geometry.x, node.geometry.y),
        fontsize=13,
        ha="center",
        va="center",
        color=C["dark"],
        bbox={
            "boxstyle": "round,pad=0.15",
            "facecolor": "white",
            "edgecolor": "none",
            "alpha": 0.8,
        },
        zorder=6,
    )
map_axis(ax)
ax.set_xlim(extent[:2])
ax.set_ylim(extent[2:])
ax.set_title(
    "Coupling: river cell → node", color="#6A3D9A", loc="left", fontsize=24, pad=38
)
ax.text(
    0,
    1.01,
    "coupler logic",
    transform=ax.transAxes,
    fontsize=19,
    color=C["dark"],
    va="bottom",
    fontweight="bold",
)
n_basin = int(in_basin.sum())
badge(
    ax,
    0.03,
    -0.07,
    f"{n_basin} cells → Basins\n{len(rivers) - n_basin} cells → FlowBoundaries",
    "#6A3D9A",
    fontsize=17,
    ha="left",
    transform=ax.transAxes,
)

for x in (0.338, 0.664):
    fig_arrow(fig, x - 0.018, 0.47, x + 0.018)

save(fig, "02_piave_grid_to_network.png")
