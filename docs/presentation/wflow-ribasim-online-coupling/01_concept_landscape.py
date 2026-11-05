"""Illustrated concept in three steps, with one perspective for the Wflow grid, river and field.

a) Wflow stand-alone, b) Wflow + Ribasim river coupling, c) coupling with irrigation.
Ribasim nodes use the icons from `ribasim.node_icons`, as in Ribasim's own network plots.
"""

from itertools import pairwise

import matplotlib.pyplot as plt
import numpy as np
from common import C, arrow, badge, cloud, droplet, save, setup_style
from matplotlib.lines import Line2D
from matplotlib.offsetbox import AnnotationBbox
from matplotlib.patches import Circle, FancyBboxPatch, Polygon
from ribasim.node_icons import make_icon_box

LINK_COLOR = "#3690c0"  # Ribasim flow link colour
VP = (8.0, 13.0)  # vanishing point of the ground plane
HORIZON = 4.8
N_ROWS = 8
U_CELLS = np.arange(-10, 27)
FIELD = (range(10, 14), range(3, 6))  # cells (u, row) of the irrigated field


def ground_y(t):
    return HORIZON * (1 - (1 - np.asarray(t)) ** 1.7)


def project(u, t):
    """Map ground coordinates (u across, t in depth 0..1) to the screen."""
    y = ground_y(t)
    return VP[0] + (np.asarray(u) - VP[0]) * (VP[1] - y) / VP[1], y


def cell(u, k):
    t0, t1 = k / N_ROWS, (k + 1) / N_ROWS
    return [project(u, t0), project(u + 1, t0), project(u + 1, t1), project(u, t1)]


def smooth(points, iterations=4):
    pts = np.asarray(points, dtype=float)
    for _ in range(iterations):
        q = 0.75 * pts[:-1] + 0.25 * pts[1:]
        r = 0.25 * pts[:-1] + 0.75 * pts[1:]
        pts = np.vstack([pts[0], np.column_stack([q, r]).reshape(-1, 2), pts[-1]])
    return pts


def icon(ax, node_type, xy, size=34, z=20):
    ax.add_artist(
        AnnotationBbox(
            make_icon_box(node_type, size=size), xy, frameon=False, pad=0, zorder=z
        )
    )


def link(ax, a, b):
    ax.plot(
        [a[0], b[0]],
        [a[1], b[1]],
        color=LINK_COLOR,
        lw=5,
        zorder=17,
        solid_capstyle="round",
    )
    angle = np.degrees(np.arctan2(b[1] - a[1], b[0] - a[0])) - 90
    ax.plot(
        (a[0] + b[0]) / 2,
        (a[1] + b[1]) / 2,
        marker=(3, 0, angle),
        markersize=18,
        color=LINK_COLOR,
        zorder=18,
    )


RIVER_UT = smooth(
    [
        (2.6, 1.0),
        (3.4, 0.86),
        (5.0, 0.72),
        (6.6, 0.6),
        (8.0, 0.48),
        (9.6, 0.36),
        (11.2, 0.25),
        (13.2, 0.15),
        (16.5, 0.04),
    ]
)
BASINS_UT = [(5.0, 0.72), (8.2, 0.47), (11.4, 0.245), (14.6, 0.1)]
MOUNTAINS = [
    (-0.5, HORIZON - 0.3),
    (-0.5, 5.9),
    (1.4, 7.3),
    (2.4, 6.3),
    (3.8, 7.9),
    (5.3, 6.0),
    (6.6, 6.8),
    (8.8, HORIZON + 0.05),
    (9.5, HORIZON - 0.3),
]


def cell_runoff(ax, target):
    """Runoff leaving a Wflow land cell towards the river (target in screen coordinates)."""
    origin = np.mean(cell(7, 6), axis=0)
    ax.add_patch(
        Polygon(
            cell(7, 6),
            closed=True,
            facecolor="#7FB35A",
            edgecolor="white",
            lw=1.5,
            zorder=6,
        )
    )
    arrow(
        ax,
        origin,
        target,
        C["wflow"],
        lw=4,
        scale=28,
        zorder=16,
        shrinkA=0,
        shrinkB=14,
    )
    ax.text(
        origin[0] + 0.35,
        origin[1] - 0.05,
        "runoff",
        color=C["wflow"],
        fontsize=20,
        fontweight="bold",
        ha="left",
        zorder=16,
    )


def draw(variant: str) -> None:
    coupled = variant in ("river", "irrigation")
    irrigation = variant == "irrigation"

    fig, ax = plt.subplots(figsize=(16, 9))
    ax.set_xlim(0, 16)
    ax.set_ylim(0, 9)
    ax.set_aspect("equal")
    ax.set_axis_off()
    fig.subplots_adjust(0, 0, 1, 1)

    sky = plt.matplotlib.colors.LinearSegmentedColormap.from_list(
        "sky", ["#FFFFFF", "#CFE6F7"]
    )
    ax.imshow(
        np.linspace(1, 0, 256)[:, None],
        extent=(0, 16, 0, 9),
        cmap=sky,
        aspect="auto",
        zorder=0,
    )
    ax.add_patch(
        Circle((14.9, 6.6), 0.5, facecolor="#FFD166", edgecolor="none", zorder=1)
    )

    mountain = Polygon(
        MOUNTAINS, closed=True, facecolor="#A39382", edgecolor="none", zorder=2
    )
    ax.add_patch(mountain)
    # Snow caps follow the mountain edges: a fraction of each slope below the peak
    for i in (2, 4, 6):
        peak, left, right = (np.array(MOUNTAINS[j]) for j in (i, i - 1, i + 1))
        depth = 0.5  # vertical extent of the snow
        a = peak + (left - peak) * min(1, depth / (peak[1] - left[1]))
        b = peak + (right - peak) * min(1, depth / (peak[1] - right[1]))
        jag = [
            a + (b - a) * f + [0, dy]
            for f, dy in [
                (0, 0),
                (0.2, -0.12),
                (0.4, 0.04),
                (0.6, -0.14),
                (0.8, 0.03),
                (1, 0),
            ]
        ]
        ax.add_patch(
            Polygon(
                [*map(tuple, jag), tuple(peak)],
                closed=True,
                facecolor="white",
                edgecolor="none",
                zorder=3,
            )
        )
    ground = Polygon(
        [(-1, 0), (-1, HORIZON), (17, HORIZON), (17, 0)],
        closed=True,
        facecolor="#A7CF7E",
        edgecolor="none",
        zorder=2,
    )
    ax.add_patch(ground)

    # Wflow grid on the ground plane, one perspective for plain, river and field
    for u in U_CELLS:
        (x0, y0), (x1, y1) = project(u, 0), project(u, 1)
        ax.plot([x0, x1], [y0, y1], color="white", lw=1, alpha=0.8, zorder=5)
    for k in range(N_ROWS + 1):
        y = ground_y(k / N_ROWS)
        ax.plot([0, 16], [y, y], color="white", lw=1, alpha=0.8, zorder=5)

    # Irrigated field: cells of the same grid
    for u in FIELD[0]:
        for k in FIELD[1]:
            ax.add_patch(
                Polygon(
                    cell(u, k),
                    closed=True,
                    facecolor="#C9DC5C" if irrigation else "#D8CF7A",
                    edgecolor="white",
                    lw=1,
                    zorder=6,
                )
            )
    for f in np.linspace(FIELD[0][0] + 0.15, FIELD[0][-1] + 0.85, 13):
        (x0, y0), (x1, y1) = (
            project(f, FIELD[1][0] / N_ROWS),
            project(f, (FIELD[1][-1] + 1) / N_ROWS),
        )
        ax.plot(
            [x0, x1],
            [y0, y1],
            color="#6B8E23" if irrigation else "#9A8F3A",
            lw=1.8,
            zorder=7,
        )

    # River and Wflow river cells
    river_cells = {
        (int(np.floor(u)), int(np.floor(t * N_ROWS))) for u, t in RIVER_UT if 0 <= t < 1
    }
    for u, k in river_cells:
        ax.add_patch(
            Polygon(
                cell(u, k),
                closed=True,
                facecolor=C["wflow"],
                alpha=0.45,
                edgecolor="white",
                lw=1,
                zorder=6,
            )
        )
    rx, ry = project(RIVER_UT[:, 0], RIVER_UT[:, 1])
    rx = np.r_[3.6, 3.9, rx]
    ry = np.r_[6.6, 5.6, ry]
    if not coupled:
        ax.plot(rx, ry, color=C["water_dark"], lw=15, solid_capstyle="round", zorder=8)
        ax.plot(rx, ry, color=C["water"], lw=11, solid_capstyle="round", zorder=9)

    cloud(ax, 3.2, 8.35, 0.85, color="#E4E7EC", zorder=9)
    for k, x in enumerate(np.linspace(2.3, 4.2, 6)):
        ax.plot(
            [x, x - 0.25],
            [7.7, 7.0 - 0.15 * (k % 2)],
            color=C["water"],
            lw=2.5,
            solid_capstyle="round",
            zorder=9,
        )

    basins = [project(u, t) for u, t in BASINS_UT]
    legend = [
        (
            Line2D(
                [],
                [],
                ls="",
                marker="s",
                markersize=20,
                markerfacecolor="#A7CF7E",
                markeredgecolor="white",
            ),
            "Wflow cell",
        ),
        (
            Line2D(
                [],
                [],
                ls="",
                marker="s",
                markersize=20,
                markerfacecolor=C["wflow"],
                alpha=0.6,
                markeredgecolor="white",
            ),
            "Wflow river cell",
        ),
    ]

    if not coupled:
        # Wflow routes the runoff through its own river cells
        arrow(ax, (1.2, 5.6), (4.0, 4.55), C["wflow"], lw=4, rad=0.25, scale=28)
        ax.text(
            0.5,
            5.0,
            "runoff",
            color=C["wflow"],
            fontsize=20,
            fontweight="bold",
            rotation=-25,
            zorder=16,
        )
        cell_runoff(ax, project(8.0, 0.5))
        # Flow direction along the river, oriented with the local tangent
        for i in (len(rx) // 4, len(rx) // 2, 3 * len(rx) // 4):
            ax.annotate(
                "",
                xy=(rx[i + 1], ry[i + 1]),
                xytext=(rx[i - 1], ry[i - 1]),
                zorder=12,
                arrowprops={
                    "arrowstyle": "-|>",
                    "mutation_scale": 60,
                    "color": C["water_dark"],
                    "lw": 0.1,
                    "shrinkA": 0,
                    "shrinkB": 0,
                },
            )
        x, y = project(12.6, 0.0)
        badge(
            ax,
            x,
            y + 0.2,
            "Wflow river routing (kinematic wave)",
            C["wflow"],
            fontsize=15,
        )
    else:
        # Ribasim replaces the river routing: Basins connected via ManningResistance nodes
        for a, b in pairwise(basins):
            mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 + 0.05)
            link(ax, a, mid)
            link(ax, mid, b)
            icon(ax, "ManningResistance", mid, size=105)
        for b in basins:
            icon(ax, "Basin", b, size=120)
        # Headwater runoff from the mountains enters the network through a FlowBoundary
        flow_boundary = (rx[2], ry[2] + 0.35)
        link(ax, flow_boundary, basins[0])
        icon(ax, "FlowBoundary", flow_boundary, size=95)
        arrow(
            ax,
            (1.5, 5.9),
            flow_boundary,
            C["wflow"],
            lw=4,
            rad=0.2,
            scale=28,
            shrinkA=0,
            shrinkB=22,
        )
        ax.text(
            0.9,
            6.15,
            "runoff",
            color=C["wflow"],
            fontsize=20,
            fontweight="bold",
            rotation=-20,
            zorder=16,
        )
        cell_runoff(ax, (basins[1][0] - 0.05, basins[1][1] + 0.05))
        legend += [
            (make_icon_box("FlowBoundary", size=70), "Ribasim FlowBoundary"),
            (make_icon_box("Basin", size=80), "Ribasim Basin"),
            (make_icon_box("ManningResistance", size=75), "Ribasim ManningResistance"),
            (Line2D([], [], color=LINK_COLOR, lw=5), "Ribasim flow link"),
        ]

    if irrigation:
        ud = project(12.0, 4.5 / N_ROWS)
        link(ax, basins[2], ud)
        for du, dk in [(-1.5, -0.9), (1.5, -0.9), (-1.2, 1.0), (1.2, 1.0)]:
            end = project(12.0 + du, (4.5 + dk) / N_ROWS)
            arrow(ax, ud, end, C["irrigation"], lw=4, scale=22, zorder=19, shrinkA=22)
        icon(ax, "UserDemand", ud, size=95, z=21)
        top = project(12.0, (FIELD[1][-1] + 1) / N_ROWS)
        ax.text(
            top[0],
            top[1] + 0.95,
            "irrigation water",
            color="#9A4D00",
            fontsize=17,
            fontweight="bold",
            ha="center",
            zorder=16,
        )
        side = project(14.0, 4.5 / N_ROWS)
        arrow(
            ax,
            (side[0] + 0.9, side[1] + 0.35),
            (ud[0] + 0.35, ud[1] + 0.12),
            C["muted"],
            lw=2.5,
            ls="--",
            rad=0.35,
            scale=20,
            zorder=19,
        )
        ax.text(
            side[0] + 0.75,
            side[1] + 0.5,
            "demand",
            color=C["dark"],
            fontsize=16,
            zorder=16,
        )
        for k in range(6):
            x, y = project(10.4 + 0.6 * k, 6.2 / N_ROWS)
            droplet(ax, x, y + 0.35 + 0.12 * (k % 2), 0.12, C["water"], zorder=8)
        legend.append((make_icon_box("UserDemand", size=70), "Ribasim UserDemand"))
    legend.append(
        (
            Line2D(
                [],
                [],
                ls="",
                marker="s",
                markersize=20,
                markerfacecolor="#C9DC5C" if irrigation else "#D8CF7A",
                markeredgecolor="white",
            ),
            "Wflow cell with crops" if not irrigation else "irrigated Wflow cell",
        )
    )

    # Legend panel with the real Ribasim icons, in two columns when it gets long
    n = len(legend)
    row = 0.47
    ncols = 1 if n <= 4 else 2
    nrows = -(-n // ncols)
    col_width = 4.3
    ax.add_patch(
        FancyBboxPatch(
            (0.25, 0.2),
            col_width * ncols + 0.1,
            row * nrows + 0.2,
            boxstyle="round,pad=0,rounding_size=0.15",
            facecolor="white",
            alpha=0.92,
            edgecolor="none",
            zorder=30,
        )
    )
    for i, (handle, label) in enumerate(legend):
        dx = col_width * (i // nrows)
        y = 0.2 + row * (nrows - i % nrows) - 0.17
        if isinstance(handle, Line2D):
            ax.add_line(
                Line2D(
                    [dx + 0.45, dx + 0.95]
                    if handle.get_linestyle() != "None"
                    else [dx + 0.7],
                    [y, y] if handle.get_linestyle() != "None" else [y],
                    color=handle.get_color(),
                    lw=handle.get_linewidth(),
                    ls=handle.get_linestyle(),
                    marker=handle.get_marker(),
                    markersize=handle.get_markersize(),
                    markerfacecolor=handle.get_markerfacecolor(),
                    markeredgecolor=handle.get_markeredgecolor(),
                    alpha=handle.get_alpha(),
                    zorder=31,
                )
            )
        else:
            ax.add_artist(
                AnnotationBbox(handle, (dx + 0.7, y), frameon=False, pad=0, zorder=31)
            )
        ax.text(
            dx + 1.15, y, label, va="center", fontsize=15.5, color=C["dark"], zorder=31
        )

    title = {
        "standalone": "Wflow stand-alone",
        "river": "Wflow + Ribasim",
        "irrigation": "Wflow + Ribasim + irrigation",
    }[variant]
    badge(ax, 15.7, 8.35, title, C["dark"], fontsize=20, ha="right")
    badge(
        ax,
        15.7,
        7.55,
        "Wflow: rain, snow, soil & runoff on a grid",
        C["wflow"],
        fontsize=14,
        ha="right",
    )
    if coupled:
        text = (
            "Ribasim: rivers, basins & water allocation"
            if irrigation
            else "Ribasim: rivers & basins"
        )
        badge(ax, 15.7, 6.95, text, C["ribasim"], fontsize=14, ha="right")

    save(
        fig,
        {
            "standalone": "01a_concept_wflow.png",
            "river": "01b_concept_coupled.png",
            "irrigation": "01c_concept_irrigation.png",
        }[variant],
    )


setup_style()
for variant in ("standalone", "river", "irrigation"):
    draw(variant)
