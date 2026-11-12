"""Roadmap for users: what the coupled model can do now, and what it will be able to do next.

Milestones follow the work packages of the development plan, phrased as user capabilities.
The order is the planned order, not a calendar schedule.
"""

import matplotlib.pyplot as plt
from common import (
    C,
    icon_box,
    icon_field,
    icon_grid,
    icon_merge,
    icon_puzzle,
    save,
    setup_style,
    slide_title,
)
from matplotlib.patches import Circle, FancyBboxPatch

DONE, NOW, NEXT = "done", "now", "next"

# title, description, status, label, colour, icon
MILESTONES = [
    (
        "Wflow runoff\ninto Ribasim rivers",
        "Wflow river cells feed\nRibasim Basins",
        DONE,
        "#3324 · merged",
        C["wflow"],
        icon_grid,
    ),
    (
        "Irrigation\nallocated by Ribasim",
        "Wflow demand, Ribasim\nshares the water",
        NOW,
        "#3333 · in review",
        C["ribasim"],
        icon_field,
    ),
    (
        "Ribasim as a\nWflow component",
        "switch on Ribasim rivers and\nallocation in the Wflow config",
        NEXT,
        "modular Wflow",
        "#6A3D9A",
        icon_puzzle,
    ),
    (
        "Build coupled\nmodels with HydroMT",
        "including lumped irrigation\nfor large areas",
        NEXT,
        "HydroMT workflows",
        C["irrigation"],
        icon_merge,
    ),
    (
        "Ready to use",
        "documentation, examples\nand installation",
        NEXT,
        "release",
        C["muted"],
        icon_box,
    ),
]

setup_style()
fig, ax = plt.subplots(figsize=(19, 8))
fig.subplots_adjust(0.01, 0.02, 0.99, 0.84)
slide_title(
    fig,
    "What's next: from proof of concept to a tool you can use",
    "Planned steps, in order",
)
ax.set_xlim(0, 20)
ax.set_ylim(1.5, 8.9)
ax.set_aspect("equal")
ax.set_axis_off()

xs = [2.0 + 4.0 * k for k in range(len(MILESTONES))]
y = 5.6

# Track: solid up to the current milestone, dotted beyond
i_now = next(k for k, m in enumerate(MILESTONES) if m[2] == NOW)
ax.plot([xs[0], xs[i_now]], [y, y], color=C["dark"], lw=6, zorder=1)
ax.plot(
    [xs[i_now], xs[-1]],
    [y, y],
    color=C["muted"],
    lw=4,
    ls=(0, (1, 2)),
    zorder=1,
)

for x, (title, description, status, label, color, icon) in zip(
    xs, MILESTONES, strict=True
):
    future = status == NEXT
    ax.add_patch(
        Circle(
            (x, y),
            0.95,
            facecolor="white" if future else color,
            edgecolor=color,
            lw=4,
            zorder=3,
        )
    )
    icon(ax, x, y, 1.0, color=color if future else "white", zorder=4)
    ax.text(
        x,
        y - 1.45,
        title,
        ha="center",
        va="top",
        fontsize=17,
        fontweight="bold",
        color=color,
    )
    ax.text(x, y - 2.75, description, ha="center", va="top", fontsize=13.5, color=C["dark"])
    ax.text(
        x,
        y + 1.3,
        label,
        ha="center",
        va="bottom",
        fontsize=13,
        color="white" if not future else color,
        fontweight="bold",
        bbox={
            "boxstyle": "round,pad=0.35,rounding_size=0.5",
            "facecolor": color if not future else "white",
            "edgecolor": color,
            "lw": 1.5,
        },
    )

# Highlight the current milestone
x_now = xs[i_now]
ax.add_patch(
    FancyBboxPatch(
        (x_now - 1.85, 1.8),
        3.7,
        6.15,
        boxstyle="round,pad=0,rounding_size=0.3",
        facecolor="none",
        edgecolor=C["shortage"],
        lw=3,
        ls="--",
        zorder=0,
    )
)
ax.text(
    x_now,
    8.1,
    "we are here",
    ha="center",
    va="bottom",
    fontsize=17,
    fontweight="bold",
    color=C["shortage"],
)

save(fig, "backup/b5_roadmap.png")
