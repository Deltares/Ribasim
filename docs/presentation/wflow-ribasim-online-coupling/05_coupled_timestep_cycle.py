"""One coupled timestep as a cycle of icons, following Candidate A in issue #3309 / online.jl."""

import matplotlib.pyplot as plt
import numpy as np
from common import (
    C,
    badge,
    icon_clock,
    icon_field,
    icon_hill_runoff,
    icon_network,
    icon_pie,
    icon_plant,
    save,
    setup_style,
    slide_title,
)
from matplotlib.patches import Circle, FancyArrowPatch
from matplotlib.path import Path

RING = 5.8
NODE = 1.3

stations = [
    # angle, colour, icon, title, subtitle
    (90, C["wflow"], "plant", "Wflow", "soil dries out → irrigation demand"),
    (
        18,
        C["ribasim"],
        "pie",
        "Ribasim allocation",
        "shares available water\nby priority",
    ),
    (
        -54,
        C["ribasim"],
        "network",
        "Ribasim physics",
        "routes water, abstracts\nwhat is really there",
    ),
    (-126, C["wflow"], "field", "Wflow", "applies realized\nirrigation to the soil"),
    (
        162,
        C["wflow"],
        "hill",
        "Wflow → Ribasim",
        "runoff of river cells\nenters the Basins",
    ),
]
exchanges = [
    ("demand", C["irrigation"], "-"),
    ("allocated", C["ribasim"], "-"),
    ("realized", C["irrigation"], "-"),
    ("soil update", C["wflow"], "-"),
    ("next day", C["muted"], "--"),
]

setup_style()
fig, ax = plt.subplots(figsize=(16, 9))
fig.subplots_adjust(left=0, right=1, top=0.86, bottom=0.02)
slide_title(
    fig,
    "One coupled day",
    "Wflow and Ribasim take turns; only data is exchanged, each model keeps its own state",
)
ax.set_xlim(-14.2, 14.2)
ax.set_ylim(-8.65, 9.35)
ax.set_aspect("equal")
ax.set_axis_off()

ax.add_patch(
    Circle((0, 0), RING, facecolor="none", edgecolor=C["light"], lw=26, zorder=0)
)

gap = np.rad2deg(NODE / RING) + 4
for k, (angle, *_rest) in enumerate(stations):
    next_angle = stations[(k + 1) % len(stations)][0]
    if next_angle > angle:
        next_angle -= 360
    a = np.deg2rad(np.linspace(angle - gap, next_angle + gap, 60))
    label, color, ls = exchanges[k]
    path = Path(np.c_[RING * np.cos(a), RING * np.sin(a)])
    ax.add_patch(
        FancyArrowPatch(
            path=path,
            arrowstyle="-|>",
            mutation_scale=30,
            lw=5,
            color=color,
            linestyle=ls,
            zorder=2,
        )
    )
    mid = np.deg2rad((angle + next_angle) / 2)
    badge(ax, RING * np.cos(mid), RING * np.sin(mid), label, color, fontsize=14)

for angle, color, icon, title, subtitle in stations:
    x, y = RING * np.cos(np.deg2rad(angle)), RING * np.sin(np.deg2rad(angle))
    ax.add_patch(
        Circle((x, y), NODE, facecolor=color, edgecolor="white", lw=5, zorder=5)
    )
    s = 1.2
    if icon == "plant":
        icon_plant(ax, x, y, s)
    elif icon == "pie":
        icon_pie(
            ax, x, y, s * 1.25, ["white", C["ribasim_light"], C["irrigation_light"]]
        )
    elif icon == "network":
        icon_network(ax, x, y + 0.1, s)
    elif icon == "field":
        icon_field(ax, x, y, s)
    elif icon == "hill":
        icon_hill_runoff(ax, x, y, s)

    c, si = np.cos(np.deg2rad(angle)), np.sin(np.deg2rad(angle))
    lx, ly = x + c * (NODE + 0.4), y + si * (NODE + 0.4)
    if abs(c) < 0.3:
        ax.text(
            lx,
            ly + 0.95,
            title,
            ha="center",
            va="bottom",
            fontsize=19,
            fontweight="bold",
            color=color,
            zorder=6,
        )
        ax.text(
            lx,
            ly + 0.05,
            subtitle,
            ha="center",
            va="bottom",
            fontsize=14.5,
            color=C["dark"],
            zorder=6,
        )
        continue
    ha = "left" if c > 0 else "right"
    ax.text(
        lx,
        ly + 0.1,
        title,
        ha=ha,
        va="bottom",
        fontsize=19,
        fontweight="bold",
        color=color,
        zorder=6,
    )
    ax.text(
        lx,
        ly - 0.1,
        subtitle,
        ha=ha,
        va="top",
        fontsize=14.5,
        color=C["dark"],
        zorder=6,
        linespacing=1.2,
    )

icon_clock(ax, 0, 0.35, 2.4, C["muted"])
ax.text(
    0,
    -1.45,
    "every day",
    ha="center",
    va="center",
    fontsize=17,
    color=C["muted"],
    fontweight="bold",
)

save(fig, "05_coupled_timestep_cycle.png", tight=False)
