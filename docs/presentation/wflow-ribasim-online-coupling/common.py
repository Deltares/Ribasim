"""Shared paths, styling, data loading and drawing helpers for the Wflow-Ribasim figures.

The data comes from the Piave proof of concept in the Ribasim repository (`wflow-coupled/`,
PR #3324 and #3333). Set the RIBASIM_REPO environment variable if the repository is not at
the default location. The coupled model must have been run (`pixi run wflow-coupled-run`).
"""

from __future__ import annotations

import os
from pathlib import Path

import geopandas as gpd
import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import xarray as xr
from matplotlib.colors import LightSource
from matplotlib.patches import (
    Circle,
    Ellipse,
    FancyArrowPatch,
    FancyBboxPatch,
    Polygon,
    Rectangle,
    Wedge,
)

HERE = Path(__file__).parent
OUT_DIR = HERE / "figures"
SOURCE_IMAGES = HERE / "source_images"

REPO = Path(os.environ.get("RIBASIM_REPO", Path(__file__).resolve().parents[3]))
COUPLED = REPO / "wflow-coupled"
WFLOW_DIR = COUPLED / "models" / "wflow_piave"
WFLOW_STATICMAPS = WFLOW_DIR / "staticmaps.nc"
RIBASIM_DIR = COUPLED / "models" / "ribasim_piave"
DATABASE = RIBASIM_DIR / "input" / "database.gpkg"
RESULTS = RIBASIM_DIR / "results"
MAPPING = COUPLED / "coupling.gpkg"
DIAGNOSTICS = COUPLED / "coupling_diagnostics.csv"
START = pd.Timestamp("2010-07-01")

C = {
    "wflow": "#1F6FB2",
    "wflow_light": "#A9CCE8",
    "ribasim": "#2E9E4F",
    "ribasim_light": "#BFE3C6",
    "irrigation": "#F28C28",
    "irrigation_light": "#FDD3A5",
    "shortage": "#D7263D",
    "water": "#3FA9F5",
    "water_dark": "#1B6FA8",
    "dark": "#1D2939",
    "muted": "#667085",
    "light": "#F2F4F7",
    "flowboundary": "#B8A1C9",
}

# Pastel palette for Ribasim Basin areas, cycling if there are more Basins
AREA_PALETTE = [
    "#8DD3C7",
    "#FFFFB3",
    "#BEBADA",
    "#FB8072",
    "#80B1D3",
    "#FDB462",
    "#B3DE69",
    "#FCCDE5",
    "#BC80BD",
    "#CCEBC5",
    "#FFED6F",
    "#A6CEE3",
    "#B2DF8A",
    "#FDBF6F",
    "#CAB2D6",
    "#E5D8BD",
    "#9EDAE5",
    "#F7B6D2",
    "#C7E9C0",
    "#DADAEB",
]

LAT_ASPECT = 1 / np.cos(np.deg2rad(46.2))


def setup_style() -> None:
    mpl.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Segoe UI", "DejaVu Sans"],
            "font.size": 14,
            "axes.titlesize": 18,
            "axes.titleweight": "bold",
            "axes.titlecolor": C["dark"],
            "axes.labelcolor": C["dark"],
            "axes.edgecolor": C["muted"],
            "axes.spines.top": False,
            "axes.spines.right": False,
            "xtick.color": C["muted"],
            "ytick.color": C["muted"],
            "legend.frameon": False,
            "figure.facecolor": "white",
        }
    )


def save(fig, name: str, tight: bool = True) -> Path:
    OUT_DIR.mkdir(exist_ok=True)
    path = OUT_DIR / name
    # OneDrive or an image viewer can briefly lock the file; retry a few times
    for attempt in range(10):
        try:
            fig.savefig(
                path,
                dpi=200,
                bbox_inches="tight" if tight else None,
                facecolor=fig.get_facecolor(),
            )
            break
        except OSError:
            if attempt == 9:
                raise
            import time

            time.sleep(3)
    plt.close(fig)
    print(path)
    return path


def slide_title(fig, title: str, subtitle: str | None = None) -> None:
    fig.text(
        0.02, 0.965, title, fontsize=28, fontweight="bold", color=C["dark"], va="top"
    )
    if subtitle:
        fig.text(0.02, 0.905, subtitle, fontsize=15, color=C["muted"], va="top")


# --------------------------------------------------------------------------- data


def load_wflow() -> xr.Dataset:
    return xr.open_dataset(WFLOW_STATICMAPS)


def load_ribasim_network():
    """Return Basin areas, FlowBoundary areas, nodes (indexed by node_id) and links."""
    basin_area = gpd.read_file(DATABASE, layer="Basin / area")
    flow_boundary_area = gpd.read_file(DATABASE, layer="FlowBoundary / area")
    nodes = gpd.read_file(DATABASE, layer="Node", fid_as_index=True)
    nodes.index.name = "node_id"
    links = gpd.read_file(DATABASE, layer="Link")
    return basin_area, flow_boundary_area, nodes, links


def load_mapping() -> gpd.GeoDataFrame:
    return gpd.read_file(MAPPING, layer="wflow_to_ribasim")


def basin_colors(basin_ids) -> dict[int, str]:
    return {
        int(i): AREA_PALETTE[k % len(AREA_PALETTE)]
        for k, i in enumerate(sorted(basin_ids))
    }


def grid_extent(lon: np.ndarray, lat: np.ndarray) -> list[float]:
    dx = abs(lon[1] - lon[0])
    dy = abs(lat[1] - lat[0])
    return [
        lon.min() - dx / 2,
        lon.max() + dx / 2,
        lat.min() - dy / 2,
        lat.max() + dy / 2,
    ]


def north_up(values: np.ndarray, lat: np.ndarray) -> np.ndarray:
    """Orient a (lat, lon) array such that imshow with origin='upper' is north up."""
    return values if lat[0] > lat[-1] else values[::-1]


def hillshade_rgba(elevation: np.ndarray, cmap=None, alpha=1.0, vmin=None, vmax=None):
    """Shaded relief of a (lat, lon) elevation array, transparent outside the domain."""
    mask = np.isnan(elevation)
    filled = np.where(mask, np.nanmin(elevation), elevation)
    vmin = np.nanmin(elevation) if vmin is None else vmin
    vmax = np.nanmax(elevation) if vmax is None else vmax
    light = LightSource(azdeg=315, altdeg=40)
    rgba = light.shade(
        filled,
        cmap=land_cmap() if cmap is None else plt.get_cmap(cmap),
        blend_mode="soft",
        vert_exag=0.004,
        vmin=vmin,
        vmax=vmax,
    )
    rgba[..., 3] = np.where(mask, 0.0, alpha)
    return rgba


def map_axis(ax) -> None:
    ax.set_aspect(LAT_ASPECT)
    ax.axis("off")


def land_cmap():
    """Terrain colours without the blue (sea) part, so low land does not look like water."""
    from matplotlib.colors import LinearSegmentedColormap

    return LinearSegmentedColormap.from_list(
        "land", plt.get_cmap("terrain")(np.linspace(0.25, 1.0, 256))
    )


def fig_arrow(fig, x0, y, x1, color=None, lw=6):
    """Large horizontal arrow in figure coordinates, used between panels."""
    fig.patches.append(
        FancyArrowPatch(
            (x0, y),
            (x1, y),
            transform=fig.transFigure,
            arrowstyle="-|>",
            mutation_scale=40,
            linewidth=lw,
            color=color or C["muted"],
            figure=fig,
        )
    )


def arrow_between(fig, ax_left, ax_right, y=None, color=None):
    """Arrow in the gap between two (aspect-constrained) axes."""
    fig.canvas.draw()
    left = ax_left.get_position()
    right = ax_right.get_position()
    gap = right.x0 - left.x1
    y = (left.y0 + left.y1) / 2 if y is None else y
    fig_arrow(fig, left.x1 + 0.2 * gap, y, right.x0 - 0.2 * gap, color=color)


# --------------------------------------------------------------------------- drawing


def badge(
    ax, x, y, text, color, *, fontsize=14, textcolor="white", ha="center", **kwargs
):
    return ax.text(
        x,
        y,
        text,
        ha=ha,
        va="center",
        fontsize=fontsize,
        color=textcolor,
        fontweight="bold",
        bbox={
            "boxstyle": "round,pad=0.45,rounding_size=0.6",
            "facecolor": color,
            "edgecolor": "none",
        },
        zorder=20,
        **kwargs,
    )


def arrow(
    ax,
    start,
    end,
    color,
    *,
    lw=3.0,
    rad=0.0,
    style="-|>",
    ls="-",
    scale=22,
    zorder=15,
    **kw,
):
    patch = FancyArrowPatch(
        start,
        end,
        arrowstyle=style,
        mutation_scale=scale,
        linewidth=lw,
        linestyle=ls,
        color=color,
        connectionstyle=f"arc3,rad={rad}",
        zorder=zorder,
        capstyle="round",
        **kw,
    )
    ax.add_patch(patch)
    return patch


def droplet(ax, x, y, s, color, zorder=10, **kw):
    """Teardrop with its tip up, centred at (x, y) with height 2s."""
    t = np.linspace(0, 2 * np.pi, 80)
    xs = x + 0.75 * s * np.sin(t) * np.sin(t / 2)
    ys = y + s * np.cos(t)
    ax.add_patch(
        Polygon(
            np.c_[xs, ys],
            closed=True,
            facecolor=color,
            edgecolor="none",
            zorder=zorder,
            **kw,
        )
    )


def cloud(ax, x, y, s, color="white", zorder=10, **kw):
    for dx, dy, r in [
        (-0.9, 0, 0.55),
        (-0.35, 0.3, 0.7),
        (0.35, 0.2, 0.65),
        (0.9, -0.05, 0.5),
        (0, -0.2, 0.55),
    ]:
        ax.add_patch(
            Circle(
                (x + dx * s, y + dy * s),
                r * s,
                facecolor=color,
                edgecolor="none",
                zorder=zorder,
                **kw,
            )
        )


def icon_plant(ax, x, y, s, color="white", zorder=12):
    ax.add_patch(
        Rectangle(
            (x - 0.6 * s, y - 0.65 * s),
            1.2 * s,
            0.2 * s,
            facecolor=color,
            edgecolor="none",
            zorder=zorder,
        )
    )
    ax.plot(
        [x, x],
        [y - 0.45 * s, y + 0.45 * s],
        color=color,
        lw=3,
        solid_capstyle="round",
        zorder=zorder,
    )
    ax.add_patch(
        Ellipse(
            (x - 0.28 * s, y + 0.0 * s),
            0.6 * s,
            0.26 * s,
            angle=30,
            facecolor=color,
            zorder=zorder,
        )
    )
    ax.add_patch(
        Ellipse(
            (x + 0.28 * s, y + 0.25 * s),
            0.6 * s,
            0.26 * s,
            angle=-30,
            facecolor=color,
            zorder=zorder,
        )
    )


def icon_pie(ax, x, y, s, colors, fractions=(0.5, 0.3, 0.2), zorder=12):
    start = 90.0
    for frac, col in zip(fractions, colors):
        end = start + 360 * frac
        ax.add_patch(
            Wedge(
                (x, y),
                0.6 * s,
                start,
                end,
                facecolor=col,
                edgecolor="white",
                lw=2,
                zorder=zorder,
            )
        )
        start = end


def icon_network(ax, x, y, s, color="white", zorder=12):
    pts = [(-0.55, 0.35), (0.0, -0.05), (0.55, 0.35), (0.0, -0.6)]
    pts = [(x + px * s, y + py * s) for px, py in pts]
    for a, b in [(0, 1), (2, 1), (1, 3)]:
        ax.plot(
            [pts[a][0], pts[b][0]],
            [pts[a][1], pts[b][1]],
            color=color,
            lw=3,
            zorder=zorder,
        )
    for px, py in pts:
        ax.add_patch(
            Circle(
                (px, py), 0.17 * s, facecolor=color, edgecolor="none", zorder=zorder + 1
            )
        )


def icon_field(ax, x, y, s, color="white", zorder=12):
    field = [
        (x - 0.7 * s, y - 0.6 * s),
        (x + 0.5 * s, y - 0.6 * s),
        (x + 0.7 * s, y - 0.1 * s),
        (x - 0.5 * s, y - 0.1 * s),
    ]
    ax.add_patch(
        Polygon(
            field, closed=True, facecolor="none", edgecolor=color, lw=2.5, zorder=zorder
        )
    )
    for f in (0.25, 0.5, 0.75):
        ax.plot(
            [x - 0.7 * s + 1.2 * s * f, x - 0.5 * s + 1.2 * s * f],
            [y - 0.6 * s, y - 0.1 * s],
            color=color,
            lw=1.8,
            zorder=zorder,
        )
    for dx in (-0.35, 0.05, 0.45):
        droplet(ax, x + dx * s, y + 0.3 * s, 0.17 * s, color, zorder=zorder)


def icon_hill_runoff(ax, x, y, s, color="white", zorder=12):
    ax.add_patch(
        Polygon(
            [
                (x - 0.75 * s, y - 0.55 * s),
                (x - 0.15 * s, y + 0.5 * s),
                (x + 0.35 * s, y - 0.55 * s),
            ],
            closed=True,
            facecolor=color,
            zorder=zorder,
        )
    )
    ax.plot(
        [x + 0.15 * s, x + 0.75 * s],
        [y - 0.55 * s, y - 0.55 * s],
        color=color,
        lw=4,
        zorder=zorder,
    )
    arrow(
        ax,
        (x - 0.05 * s, y + 0.15 * s),
        (x + 0.6 * s, y - 0.35 * s),
        color,
        lw=2.5,
        rad=-0.3,
        scale=14,
        zorder=zorder + 1,
    )


def icon_clock(ax, x, y, s, color, zorder=12):
    ax.add_patch(
        Circle((x, y), 0.6 * s, facecolor="white", edgecolor=color, lw=4, zorder=zorder)
    )
    ax.plot(
        [x, x],
        [y, y + 0.42 * s],
        color=color,
        lw=4,
        solid_capstyle="round",
        zorder=zorder + 1,
    )
    ax.plot(
        [x, x + 0.3 * s],
        [y, y],
        color=color,
        lw=4,
        solid_capstyle="round",
        zorder=zorder + 1,
    )


def icon_grid(ax, x, y, s, color="white", n=3, zorder=12):
    h = 0.6 * s
    for k in range(n + 1):
        f = -h + 2 * h * k / n
        ax.plot([x - h, x + h], [y + f, y + f], color=color, lw=2, zorder=zorder)
        ax.plot([x + f, x + f], [y - h, y + h], color=color, lw=2, zorder=zorder)


def icon_puzzle(ax, x, y, s, color="white", zorder=12):
    ax.add_patch(
        FancyBboxPatch(
            (x - 0.5 * s, y - 0.5 * s),
            s,
            s,
            boxstyle="round,pad=0,rounding_size=0.1",
            facecolor=color,
            edgecolor="none",
            zorder=zorder,
        )
    )
    ax.add_patch(
        Circle(
            (x + 0.5 * s, y), 0.2 * s, facecolor=color, edgecolor="none", zorder=zorder
        )
    )
    ax.add_patch(
        Circle(
            (x, y + 0.5 * s), 0.2 * s, facecolor=color, edgecolor="none", zorder=zorder
        )
    )


def icon_box(ax, x, y, s, color="white", zorder=12):
    ax.add_patch(
        Polygon(
            [
                (x - 0.6 * s, y + 0.15 * s),
                (x, y + 0.45 * s),
                (x + 0.6 * s, y + 0.15 * s),
                (x, y - 0.15 * s),
            ],
            closed=True,
            facecolor=color,
            zorder=zorder,
        )
    )
    ax.add_patch(
        Polygon(
            [
                (x - 0.6 * s, y + 0.05 * s),
                (x - 0.05 * s, y - 0.25 * s),
                (x - 0.05 * s, y - 0.7 * s),
                (x - 0.6 * s, y - 0.4 * s),
            ],
            closed=True,
            facecolor=color,
            zorder=zorder,
        )
    )
    ax.add_patch(
        Polygon(
            [
                (x + 0.6 * s, y + 0.05 * s),
                (x + 0.05 * s, y - 0.25 * s),
                (x + 0.05 * s, y - 0.7 * s),
                (x + 0.6 * s, y - 0.4 * s),
            ],
            closed=True,
            facecolor=color,
            zorder=zorder,
        )
    )


def icon_merge(ax, x, y, s, color="white", zorder=12):
    arrow(
        ax,
        (x - 0.6 * s, y + 0.5 * s),
        (x + 0.55 * s, y),
        color,
        lw=3,
        rad=0.25,
        scale=14,
        zorder=zorder,
    )
    arrow(
        ax,
        (x - 0.6 * s, y - 0.5 * s),
        (x + 0.55 * s, y),
        color,
        lw=3,
        rad=-0.25,
        scale=14,
        zorder=zorder,
    )
