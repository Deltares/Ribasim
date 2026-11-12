"""Combined strengths: Wflow's detailed land hydrology + Ribasim's controlled surface water and allocation.

Left: a Wflow soil column on a grid with vertical and lateral processes.
Right: a Ribasim network with control and prioritized allocation, using `ribasim.node_icons`.
"""

import matplotlib.pyplot as plt
from common import C, arrow, cloud, save, setup_style, slide_title
from matplotlib.offsetbox import AnnotationBbox
from matplotlib.patches import (
    Circle,
    FancyArrowPatch,
    FancyBboxPatch,
    Polygon,
    Rectangle,
)
from matplotlib.path import Path as MplPath
from ribasim.node_icons import make_icon_box

LINK = "#3690c0"
CONTROL = "grey"


def icon(ax, node_type, xy, size=60, z=20):
    ax.add_artist(
        AnnotationBbox(
            make_icon_box(node_type, size=size), xy, frameon=False, pad=0, zorder=z
        )
    )


def link(ax, a, b, color=LINK, ls="-"):
    ax.plot(
        [a[0], b[0]],
        [a[1], b[1]],
        color=color,
        lw=3.5,
        ls=ls,
        zorder=10,
        solid_capstyle="round",
    )
    if ls == "-":
        ax.annotate(
            "",
            xy=(
                (a[0] + b[0]) / 2 + (b[0] - a[0]) * 0.05,
                (a[1] + b[1]) / 2 + (b[1] - a[1]) * 0.05,
            ),
            xytext=((a[0] + b[0]) / 2, (a[1] + b[1]) / 2),
            zorder=11,
            arrowprops={
                "arrowstyle": "-|>",
                "mutation_scale": 22,
                "color": color,
                "lw": 0.1,
                "shrinkA": 0,
                "shrinkB": 0,
            },
        )


def panel(ax, x, y, w, h, color):
    ax.add_patch(
        FancyBboxPatch(
            (x, y),
            w,
            h,
            boxstyle="round,pad=0,rounding_size=0.3",
            facecolor=color,
            edgecolor="none",
            zorder=0,
        )
    )


def strengths(ax, x, y, items, color):
    for k, text in enumerate(items):
        yy = y - 0.55 * k
        ax.add_patch(Circle((x, yy), 0.13, facecolor=color, zorder=5))
        ax.text(x + 0.3, yy, text, va="center", fontsize=15, color=C["dark"])


setup_style()
fig, ax = plt.subplots(figsize=(19, 10.5))
fig.subplots_adjust(0.01, 0.01, 0.99, 0.87)
slide_title(
    fig,
    "Two strengths, one coupled model",
    "Wflow describes how water moves through the landscape; Ribasim how people store, steer and share it",
)
ax.set_xlim(0, 20)
ax.set_ylim(0.7, 11)
ax.set_aspect("equal")
ax.set_axis_off()

# ------------------------------------------------------------------ Wflow
panel(ax, 0.2, 3.0, 9.1, 7.8, "#EAF2FA")
ax.text(0.6, 10.25, "Wflow", fontsize=26, fontweight="bold", color=C["wflow"])
ax.text(
    2.55,
    10.25,
    "detailed, spatially resolved hydrology",
    fontsize=16,
    color=C["wflow"],
    va="baseline",
)

# Wflow SBM in oblique view: one soil column per grid cell on a slope towards a river cell.
# Each column has a finite soil thickness, an unsaturated zone above and a saturated zone
# below a dynamic water table. Lateral subsurface flow (kinematic wave) runs through the
# saturated zone, follows the slope and drains into the river; below the soil there is no
# separate groundwater layer (only an optional leakage).
ox, cw, dx, dy = 0.8, 1.75, 0.55, 0.4
n_cells = 4
surface = [8.0 - 0.5 * j for j in range(n_cells)]
thickness = 2.5
# The water table drops towards the river, but less than the surface: it gets shallower
water_table_depth = [1.1, 0.85, 0.65, 0.3]
UNSAT, SAT = "#C8A97E", "#7C8C9C"
OPEN = 1  # the column drawn fully opaque, where the vertical processes are shown


def x_left(j):
    return ox + j * cw


def column_alpha(j):
    return 1.0 if j == OPEN else 0.6


for j in range(n_cells):
    x0, top = x_left(j), surface[j]
    bottom, wt = top - thickness, top - water_table_depth[j]
    alpha = column_alpha(j)
    # Step between this cell and its lower neighbour (or the outer side of the block)
    lower = surface[j + 1] if j + 1 < n_cells else bottom
    for y0, y1, color in [(wt, top, UNSAT), (bottom, wt, SAT)]:
        lo, hi = max(y0, lower), y1
        if hi > lo:
            ax.add_patch(
                Polygon(
                    [
                        (x0 + cw, lo),
                        (x0 + cw, hi),
                        (x0 + cw + dx, hi + dy),
                        (x0 + cw + dx, lo + dy),
                    ],
                    closed=True,
                    facecolor=color,
                    edgecolor="white",
                    lw=1,
                    alpha=alpha,
                    zorder=2,
                )
            )
    for y0, y1, color in [(wt, top, UNSAT), (bottom, wt, SAT)]:
        ax.add_patch(
            Rectangle(
                (x0, y0),
                cw,
                y1 - y0,
                facecolor=color,
                edgecolor="white",
                lw=1.5,
                alpha=alpha,
                zorder=3,
            )
        )
    river = j == n_cells - 1
    ax.add_patch(
        Polygon(
            [(x0, top), (x0 + cw, top), (x0 + cw + dx, top + dy), (x0 + dx, top + dy)],
            closed=True,
            facecolor=C["wflow_light"] if river else "#A7CF7E",
            edgecolor="white",
            lw=1.5,
            zorder=4,
        )
    )
    # Soil bottom: no separate groundwater layer below the soil column
    ax.plot([x0, x0 + cw], [bottom, bottom], color=C["dark"], lw=2.5, zorder=5)
    # Water table, dashed
    ax.plot(
        [x0, x0 + cw], [wt, wt], color=C["water_dark"], lw=2.5, ls="--", zorder=5
    )

x_river = x_left(n_cells - 1)
ax.add_patch(
    Rectangle(
        (x_river, surface[-1] - 0.3),
        cw,
        0.3,
        facecolor=C["water"],
        edgecolor="white",
        lw=1.5,
        zorder=4,
    )
)
ax.text(
    x_river + cw / 2 + dx / 2,
    surface[-1] + dy + 0.12,
    "river cell",
    ha="center",
    fontsize=12,
    color=C["wflow"],
    fontweight="bold",
)


def label(x, y, text, color="white", fontsize=11, **kw):
    """Process label inside the soil, in a regular weight so it does not dominate the drawing."""
    ax.text(
        x,
        y,
        text,
        fontsize=fontsize,
        color=color,
        zorder=8,
        **kw,
    )


# Vertical processes on the open column
cx = x_left(OPEN) + 0.2
top = surface[OPEN]
wt = top - water_table_depth[OPEN]
cloud(ax, cx + 0.2, 9.75, 0.45, color="#D0D5DD", zorder=6)
for k in range(4):
    ax.plot(
        [cx - 0.3 + 0.2 * k, cx - 0.4 + 0.2 * k],
        [9.35, 8.95],
        color=C["water"],
        lw=2.5,
        zorder=6,
    )
ax.text(
    cx - 0.75, 9.15, "rain\n& snow", ha="right", va="center", fontsize=12,
    color=C["water_dark"],
)
arrow(ax, (cx, top - 0.05), (cx, top - 0.5), C["wflow"], lw=3, scale=18, zorder=7)
label(cx + 0.12, top - 0.3, "infiltration", va="center")
arrow(ax, (cx, wt + 0.25), (cx, wt - 0.45), C["wflow"], lw=3, scale=18, zorder=7)
label(cx + 0.12, wt - 0.08, "recharge", va="top")
# Capillary rise on the next cell
cx2 = x_left(OPEN + 1) + 0.2
wt2 = surface[OPEN + 1] - water_table_depth[OPEN + 1]
arrow(ax, (cx2, wt2 - 0.3), (cx2, wt2 + 0.3), C["wflow"], lw=2.5, scale=16, zorder=7)
label(cx2 + 0.12, wt2 - 0.06, "capillary\nrise", va="top", fontsize=10)

# Evaporation and transpiration from the next cell
ex = x_left(OPEN + 1) + 0.9
ax.add_patch(Circle((ex, 9.55), 0.35, facecolor="#FFD166", zorder=6))
arrow(ax, (ex, surface[OPEN + 1] + dy / 2 + 0.05), (ex, 9.05), C["irrigation"], lw=2.5, scale=16)
ax.text(
    ex + 0.15, 8.6, "evaporation &\ntranspiration", ha="left", va="center",
    fontsize=12, color="#9A4D00",
)

# Lateral flows towards the river: overland flow on the surface, subsurface flow through
# the saturated zone, both downslope
# Both paths step down with the cells instead of cutting through them
overland = []
for j, top in enumerate(surface[:-1]):
    y = top + dy / 2
    overland += [(x_left(j) + 0.25 + dx / 2, y), (x_left(j + 1) + dx / 2, y)]
overland.append((x_left(n_cells - 1) + 0.55, surface[-1] + dy / 2))
ax.add_patch(
    FancyArrowPatch(
        path=MplPath(overland),
        arrowstyle="-|>",
        mutation_scale=20,
        lw=3,
        color=C["water_dark"],
        zorder=9,
    )
)
ax.text(
    x_left(0) + 0.05, surface[0] + dy + 0.12, "overland flow", fontsize=12,
    color=C["water_dark"], fontweight="bold",
)
subsurface = []
for j in range(n_cells - 1):
    y = surface[j] - water_table_depth[j] - 0.7
    subsurface += [(x_left(j) + (0.15 if j == 0 else 0.0), y), (x_left(j + 1), y)]
# In the river cell the subsurface flow drains into the river
x_drain = x_left(n_cells - 1) + 0.5
subsurface += [(x_drain, subsurface[-1][1]), (x_drain, surface[-1] - 0.32)]
ax.add_patch(
    FancyArrowPatch(
        path=MplPath(subsurface),
        arrowstyle="-|>",
        mutation_scale=20,
        lw=3,
        color=C["water_dark"],
        zorder=7,
    )
)
label(
    x_left(0) + 0.12,
    surface[0] - thickness + 0.25,
    "lateral subsurface flow",
    va="center",
)
label(
    x_left(0) + 0.12,
    surface[0] - water_table_depth[0] - 0.12,
    "water table",
    va="top",
    fontsize=10,
)
# ------------------------------------------------------------------ Ribasim
panel(ax, 10.7, 3.0, 9.1, 7.8, "#EAF6EC")
ax.text(11.1, 10.25, "Ribasim", fontsize=26, fontweight="bold", color=C["ribasim"])
ax.text(
    13.55,
    10.25,
    "controlled water systems & allocation",
    fontsize=16,
    color=C["ribasim"],
    va="baseline",
)

nodes = {
    "fb": (11.6, 8.8),
    "b1": (12.9, 7.6),
    "out": (14.2, 7.6),
    "b2": (15.6, 7.6),
    "pump": (17.0, 7.6),
    "b3": (18.4, 7.6),
    "ud1": (14.0, 5.9),
    "ud2": (15.6, 5.9),
    "ud3": (17.2, 5.9),
    "dc": (16.3, 9.2),
    "ld": (18.4, 9.2),
}
link(ax, nodes["fb"], nodes["b1"])
link(ax, nodes["b1"], nodes["out"])
link(ax, nodes["out"], nodes["b2"])
link(ax, nodes["b2"], nodes["pump"])
link(ax, nodes["pump"], nodes["b3"])
for ud in ("ud1", "ud2", "ud3"):
    link(ax, nodes["b2"], nodes[ud])
link(ax, nodes["dc"], nodes["pump"], color=CONTROL, ls="--")
link(ax, nodes["b2"], nodes["dc"], color=CONTROL, ls=":")
link(ax, nodes["ld"], nodes["b3"], color=CONTROL, ls="--")
for name, kind, size in [
    ("fb", "FlowBoundary", 110),
    ("b1", "Basin", 150),
    ("b2", "Basin", 150),
    ("b3", "Basin", 150),
    ("out", "Outlet", 120),
    ("pump", "Pump", 120),
    ("ud1", "UserDemand", 110),
    ("ud2", "UserDemand", 110),
    ("ud3", "UserDemand", 110),
    ("dc", "DiscreteControl", 130),
    ("ld", "LevelDemand", 110),
]:
    icon(ax, kind, nodes[name], size=size)

ax.text(
    nodes["dc"][0],
    nodes["dc"][1] + 0.45,
    "control rules",
    ha="center",
    fontsize=12,
    color="#984EA3",
    fontweight="bold",
)
ax.text(
    nodes["ld"][0],
    nodes["ld"][1] + 0.45,
    "target level",
    ha="center",
    fontsize=12,
    color="#B07A00",
    fontweight="bold",
)
for name, (prio, label, frac) in zip(
    ("ud1", "ud2", "ud3"),
    [(1, "drinking\nwater", 1.0), (2, "irrigation", 1.0), (3, "industry", 0.3)],
):
    x, y = nodes[name]
    ax.text(x, y - 0.55, label, ha="center", va="top", fontsize=12, color=C["dark"])
    ax.add_patch(
        Rectangle(
            (x - 0.45, y - 1.55),
            0.9,
            0.18,
            facecolor="#E4E7EC",
            edgecolor="none",
            zorder=5,
        )
    )
    ax.add_patch(
        Rectangle(
            (x - 0.45, y - 1.55),
            0.9 * frac,
            0.18,
            facecolor=C["ribasim"],
            edgecolor="none",
            zorder=6,
        )
    )
    ax.text(
        x - 0.55,
        y - 1.46,
        f"P{prio}",
        ha="right",
        va="center",
        fontsize=12,
        fontweight="bold",
        color=C["shortage"],
        zorder=21,
    )
ax.text(
    nodes["ud2"][0],
    nodes["ud2"][1] - 1.95,
    "supply by priority when water is scarce",
    ha="center",
    fontsize=11.5,
    color=C["muted"],
    style="italic",
)


# ------------------------------------------------------------------ Combined
ax.add_patch(
    Circle((10.0, 6.3), 0.55, facecolor="white", edgecolor=C["dark"], lw=3, zorder=8)
)
ax.text(
    10.0,
    6.3,
    "+",
    ha="center",
    va="center",
    fontsize=32,
    fontweight="bold",
    color=C["dark"],
    zorder=9,
)
ax.add_patch(
    FancyBboxPatch(
        (0.2, 0.8),
        19.6,
        1.4,
        boxstyle="round,pad=0,rounding_size=0.3",
        facecolor=C["light"],
        edgecolor="none",
    )
)
ax.text(
    10.0,
    1.75,
    "Coupled: realistic runoff and irrigation demand from every cell,",
    ha="center",
    va="center",
    fontsize=18,
    color=C["dark"],
    fontweight="bold",
)
ax.text(
    10.0,
    1.23,
    "managed and allocated through the controlled surface water network",
    ha="center",
    va="center",
    fontsize=18,
    color=C["dark"],
    fontweight="bold",
)


save(fig, "01_combined_strengths.png")
