"""Irrigation on real data: irrigated Wflow cells are aggregated into Ribasim UserDemand nodes.

Recreates (and extends) the schematization in PR #3333. A UserDemand is created for every
intersection of a Ribasim Basin area and a Wflow allocation area that contains irrigated cells.
"""

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
from common import (
    WFLOW_DIR,
    C,
    arrow_between,
    badge,
    basin_colors,
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
from matplotlib.colors import ListedColormap
from matplotlib.lines import Line2D
from matplotlib.offsetbox import AnnotationBbox
from matplotlib.patches import Patch, Rectangle
from ribasim.node_icons import make_icon_box

UD_COLORS = ["#F28C28", "#E8C120", "#D95F9E", "#5FB4D9"]
UNCOUPLED = "#98A2B3"
AREA_COLORS = ["#C6DBEF", "#FDE0C5", "#D9F0D3", "#E5D7F0"]

setup_style()
ds = load_wflow()
lon, lat = ds.longitude.values, ds.latitude.values
extent = grid_extent(lon, lat)
elevation = north_up(ds["land_elevation"].values, lat)
irrigated = ds["demand_nonpaddy_irrigated_mask"].values == 1
catchment = gpd.read_file(WFLOW_DIR / "staticgeoms" / "basins.geojson")
allocation_areas = gpd.read_file(
    WFLOW_DIR / "staticgeoms" / "demand_allocation_area_id.geojson"
)
basin_area, flow_boundary_area, nodes, links = load_ribasim_network()
mapping = load_mapping()
coupled = mapping[mapping.node_type == "UserDemand"]
user_demands = nodes[nodes.node_type == "UserDemand"]
ud_color = {
    int(i): UD_COLORS[k % len(UD_COLORS)]
    for k, i in enumerate(sorted(user_demands.index))
}

# Categorical irrigation map: 1 = uncoupled irrigated cell, 2.. = coupled to a UserDemand
codes = np.where(irrigated, 1, 0)
ud_code = {node_id: k + 2 for k, node_id in enumerate(sorted(ud_color))}
for row in coupled.itertuples():
    i = int(np.argmin(np.abs(lat - row.latitude)))
    j = int(np.argmin(np.abs(lon - row.longitude)))
    codes[i, j] = ud_code[int(row.node_id)]
codes = north_up(codes, lat)
cmap = ListedColormap(["none", UNCOUPLED, *[ud_color[n] for n in sorted(ud_color)]])
n_uncoupled = int((codes == 1).sum())

# Zoom window around the Basins that supply the UserDemands
source_ids = links[
    links.to_node_id.isin(user_demands.index)
    & links.from_node_id.isin(nodes.index[nodes.node_type == "Basin"])
].from_node_id
x0, y0, x1, y1 = basin_area[basin_area.node_id.isin(source_ids)].total_bounds
pad = 0.02
zoom = (x0 - pad, x1 + pad, y0 - pad, y1 + pad)

fig = plt.figure(figsize=(20, 10.5))
gs = fig.add_gridspec(
    1,
    2,
    width_ratios=[0.62, 1.38],
    left=0.01,
    right=0.99,
    top=0.85,
    bottom=0.17,
    wspace=0.12,
)
slide_title(
    fig,
    "Irrigated cells become Ribasim UserDemands",
    "Irrigated Wflow cells are grouped per Basin and allocation area; each group gets one UserDemand",
)

# Left: overview
ax = fig.add_subplot(gs[0])
ax.imshow(
    hillshade_rgba(elevation, vmin=0, vmax=2600, alpha=0.55),
    extent=extent,
    interpolation="nearest",
)
# Keep the area labels clear of the irrigated cells
ii, jj = np.nonzero(irrigated)
irrigated_cells = gpd.points_from_xy(lon[jj], lat[ii]).buffer(0.04).union_all()
for k, area in enumerate(allocation_areas.itertuples()):
    gpd.GeoSeries([area.geometry]).plot(
        ax=ax, color=AREA_COLORS[k % 4], alpha=0.6, edgecolor=C["dark"], lw=1.5, ls="--"
    )
    free = area.geometry.difference(irrigated_cells)
    p = (free if not free.is_empty else area.geometry).representative_point()
    ax.text(
        p.x,
        p.y,
        f"allocation\narea {int(area.value)}",
        ha="center",
        va="center",
        fontsize=12,
        color=C["dark"],
        fontweight="bold",
    )
catchment.boundary.plot(ax=ax, color=C["dark"], lw=1.5)
ax.imshow(
    np.ma.masked_equal(codes, 0),
    cmap=cmap,
    vmin=-0.5,
    vmax=cmap.N - 0.5,
    extent=extent,
    interpolation="nearest",
    zorder=3,
)
ax.add_patch(
    Rectangle(
        (zoom[0], zoom[2]),
        zoom[1] - zoom[0],
        zoom[3] - zoom[2],
        fill=False,
        edgecolor=C["shortage"],
        lw=3,
        zorder=5,
        clip_on=False,
    )
)
map_axis(ax)
ax.set_xlim(extent[:2])
ax.set_ylim(extent[2:])
ax.set_title("Piave: irrigated cells", loc="left", color=C["irrigation"])
badge(
    ax,
    0.03,
    -0.02,
    f"{int(irrigated.sum())} irrigated Wflow cells",
    C["irrigation"],
    fontsize=13,
    ha="left",
    transform=ax.transAxes,
)

ax_overview = ax

# Right: zoom on the irrigated area
ax = fig.add_subplot(gs[1])
colors = basin_colors(basin_area.node_id)
basin_area.plot(
    ax=ax, color=basin_area.node_id.map(colors), edgecolor="white", lw=2, alpha=0.55
)
flow_boundary_area.plot(
    ax=ax, color=C["flowboundary"], edgecolor="white", lw=2, hatch="///", alpha=0.45
)
allocation_areas.boundary.plot(ax=ax, color=C["dark"], lw=2.5, ls="--")
ax.imshow(
    np.ma.masked_equal(codes, 0),
    cmap=cmap,
    vmin=-0.5,
    vmax=cmap.N - 0.5,
    extent=extent,
    interpolation="nearest",
    zorder=3,
)

# Spider lines: each coupled cell to its UserDemand
for row in coupled.itertuples():
    ud = user_demands.loc[int(row.node_id)].geometry
    ax.plot(
        [row.longitude, ud.x],
        [row.latitude, ud.y],
        color=ud_color[int(row.node_id)],
        lw=1.2,
        alpha=0.9,
        zorder=4,
    )

links.plot(ax=ax, color=C["water_dark"], lw=2.5, zorder=4)
# The outlet LevelBoundary (#33) lies exactly on Basin #1 and is left out so it does not hide it
for node_type, size in [
    ("ManningResistance", 55),
    ("FlowBoundary", 70),
    ("Basin", 80),
]:
    for geom in nodes[nodes.node_type == node_type].geometry:
        if zoom[0] < geom.x < zoom[1] and zoom[2] < geom.y < zoom[3]:
            ax.add_artist(
                AnnotationBbox(
                    make_icon_box(node_type, size=size),
                    (geom.x, geom.y),
                    frameon=False,
                    pad=0,
                    zorder=6,
                )
            )

for node_id, ud in user_demands.iterrows():
    source = links[
        (links.to_node_id == node_id)
        & links.from_node_id.isin(nodes.index[nodes.node_type == "Basin"])
    ].from_node_id.iloc[0]
    basin = nodes.loc[source].geometry
    ax.plot(
        [basin.x, ud.geometry.x],
        [basin.y, ud.geometry.y],
        color=C["water_dark"],
        lw=2.5,
        zorder=7,
    )
    ax.add_artist(
        AnnotationBbox(
            make_icon_box("UserDemand", size=95),
            (ud.geometry.x, ud.geometry.y),
            frameon=False,
            pad=0,
            zorder=8,
        )
    )
    ax.annotate(
        f"UserDemand #{node_id}\ntakes from Basin #{source}\n"
        f"for allocation area {int(ud.meta_allocation_area_id)}",
        (ud.geometry.x, ud.geometry.y),
        xytext=(14, 14),
        textcoords="offset points",
        fontsize=13,
        fontweight="bold",
        color=C["dark"],
        zorder=9,
        bbox={
            "boxstyle": "round,pad=0.3",
            "facecolor": "white",
            "edgecolor": ud_color[node_id],
            "lw": 2,
        },
    )
    ax.annotate(
        f"#{source}",
        (basin.x, basin.y),
        xytext=(-28, -28),
        textcoords="offset points",
        fontsize=12,
        color=C["water_dark"],
        fontweight="bold",
        zorder=9,
    )

map_axis(ax)
ax.set_xlim(zoom[:2])
ax.set_ylim(zoom[2:])
ax.add_patch(
    Rectangle(
        (0, 0),
        1,
        1,
        transform=ax.transAxes,
        fill=False,
        edgecolor=C["shortage"],
        lw=3,
        clip_on=False,
        zorder=10,
    )
)
ax.set_title("Zoom: cells grouped into UserDemands", loc="left", color=C["dark"])

handles = [
    Patch(facecolor=ud_color[n], label=f"irrigated → UserDemand #{n}")
    for n in sorted(ud_color)
]
handles += [
    Patch(
        facecolor=UNCOUPLED,
        label=f"irrigated, in FlowBoundary area:\nnot coupled yet ({n_uncoupled} cells)",
    ),
    Line2D([], [], color=C["dark"], ls="--", lw=2.5, label="Wflow allocation area"),
    Line2D(
        [],
        [],
        ls="",
        marker="s",
        color=C["shortage"],
        markersize=13,
        label="Ribasim UserDemand",
    ),
    Line2D(
        [],
        [],
        ls="",
        marker="o",
        color="#FF7F00",
        markersize=13,
        label="Ribasim FlowBoundary",
    ),
    Line2D(
        [],
        [],
        ls="",
        marker=[(-1, 1), (1, 1), (0.6, -1), (-0.6, -1)],
        color="#0072B2",
        markersize=13,
        label="Ribasim Basin",
    ),
    Line2D([], [], color=C["water_dark"], lw=3, label="Ribasim flow link"),
]
ax.legend(
    handles=handles,
    loc="upper center",
    bbox_to_anchor=(0.5, -0.03),
    fontsize=13,
    ncols=3,
    columnspacing=2.0,
)
arrow_between(fig, ax_overview, ax)

save(fig, "04_irrigation_cells_to_userdemand.png")
