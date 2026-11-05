"""Roadmap of the development plan: five work packages, relative size, dependencies and status.

Bars show relative size (S, M, L, XL) from the plan, not a calendar schedule.
"""

import matplotlib.pyplot as plt
from common import (
    C,
    arrow,
    icon_box,
    icon_field,
    icon_grid,
    icon_merge,
    icon_puzzle,
    save,
    setup_style,
    slide_title,
)
from matplotlib.patches import Circle, FancyBboxPatch, RegularPolygon

UNIT = 1.75
T0 = 7.2
SIZE = {"S": 1, "M": 2, "L": 3, "XL": 4}

# name, description, size, start (in size units), colour, icon
WORK_PACKAGES = [
    (
        "WP1  Modular Wflow core",
        "switch components, inject states & fluxes",
        "XL",
        0,
        C["wflow"],
        icon_puzzle,
    ),
    (
        "WP2  Distributed coupling",
        "river exchange + irrigation allocation",
        "M",
        0,
        C["ribasim"],
        icon_grid,
    ),
    (
        "WP3  Integration",
        "one framework, no duplicated logic",
        "M",
        4,
        "#6A3D9A",
        icon_merge,
    ),
    (
        "WP4  Lumped irrigation",
        "on modular Wflow, HydroMT workflows",
        "L",
        4,
        C["irrigation"],
        icon_field,
    ),
    ("WP5  Packaging", "docs, examples, distribution", "S", 6, C["muted"], icon_box),
]

setup_style()
fig, ax = plt.subplots(figsize=(19, 10))
fig.subplots_adjust(0.01, 0.02, 0.99, 0.86)
slide_title(
    fig,
    "Roadmap: from proof of concept to product",
    "Work packages of the development plan (bar length = relative size, not a schedule)",
)
ax.set_xlim(0, 20.5)
ax.set_ylim(-0.6, 10.4)
ax.set_axis_off()

rows = {}
for k, (name, description, size, start, color, icon) in enumerate(WORK_PACKAGES):
    y = 9.0 - 2.0 * k
    rows[k] = y
    ax.add_patch(Circle((0.75, y), 0.62, facecolor=color, zorder=2))
    icon(ax, 0.75, y, 0.75, zorder=3)
    ax.text(
        1.6, y + 0.22, name, fontsize=17, fontweight="bold", color=color, va="center"
    )
    ax.text(1.6, y - 0.32, description, fontsize=13, color=C["dark"], va="center")
    x0, width = T0 + start * UNIT, SIZE[size] * UNIT
    dashed = name.startswith("WP5")
    ax.add_patch(
        FancyBboxPatch(
            (x0, y - 0.38),
            width - 0.08,
            0.76,
            boxstyle="round,pad=0,rounding_size=0.2",
            facecolor="white" if dashed else color,
            edgecolor=color,
            lw=2.5,
            ls="--" if dashed else "-",
            zorder=2,
        )
    )
    ax.text(
        x0 + width / 2,
        y,
        size,
        ha="center",
        va="center",
        fontsize=16,
        fontweight="bold",
        color=color if dashed else "white",
        zorder=3,
    )

# WP5 can run in parallel: a faint track over the whole roadmap
y5 = rows[4]
ax.plot([T0, T0 + 7 * UNIT], [y5, y5], color=C["muted"], lw=2, ls=":", zorder=1)
ax.text(
    T0 + 3 * UNIT,
    y5 + 0.55,
    "can run in parallel",
    ha="center",
    fontsize=12,
    color=C["muted"],
    style="italic",
)

# Dependencies
arrow(
    ax,
    (T0 + 4 * UNIT, rows[0] - 0.4),
    (T0 + 4 * UNIT + 0.25, rows[2] + 0.42),
    C["muted"],
    lw=2.5,
    rad=0.25,
)
arrow(
    ax,
    (T0 + 4 * UNIT - 0.2, rows[0] - 0.4),
    (T0 + 4 * UNIT + 0.1, rows[3] + 0.42),
    C["muted"],
    lw=2.5,
    rad=0.3,
)
arrow(
    ax,
    (T0 + 2 * UNIT, rows[1] - 0.3),
    (T0 + 4 * UNIT, rows[2]),
    C["muted"],
    lw=2.5,
    rad=0.25,
)
arrow(
    ax,
    (T0 + 1.0 * UNIT, rows[1] + 0.42),
    (T0 + 1.0 * UNIT, rows[0] - 0.42),
    C["ribasim"],
    lw=2.5,
    style="<|-|>",
    ls="--",
)
ax.text(
    T0 + 1.0 * UNIT + 0.15,
    (rows[0] + rows[1]) / 2,
    "early feedback\non interfaces",
    fontsize=12,
    color=C["ribasim"],
    va="center",
)

# Status on WP2: the two proof-of-concept PRs
y2 = rows[1]
for frac, label, done in [
    (0.2, "#3324\nriver coupling\n(merged)", True),
    (0.72, "#3333\nirrigation\n(in review)", False),
]:
    x = T0 + frac * 2 * UNIT
    ax.add_patch(
        RegularPolygon(
            (x, y2),
            4,
            radius=0.3,
            facecolor="white" if not done else C["dark"],
            edgecolor=C["dark"],
            lw=2,
            zorder=4,
        )
    )
    ax.text(
        x,
        y2 - 0.65,
        label,
        ha="center",
        va="top",
        fontsize=12,
        color=C["dark"],
        zorder=4,
    )

x_here = T0 + 0.72 * 2 * UNIT
ax.annotate(
    "we are here",
    xy=(x_here, y2 + 0.4),
    xytext=(T0 + 2 * UNIT + 0.6, y2 + 0.75),
    fontsize=15,
    fontweight="bold",
    color=C["shortage"],
    va="center",
    arrowprops={
        "arrowstyle": "-|>",
        "color": C["shortage"],
        "lw": 2.5,
        "mutation_scale": 20,
    },
)

save(fig, "08_roadmap.png")
