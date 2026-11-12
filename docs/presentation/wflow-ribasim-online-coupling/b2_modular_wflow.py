"""From the PoC to a modular Wflow: Ribasim plugs into configurable Wflow components.

Based on the development plan: today the coupler copies and modifies the Wflow update sequence
(`get_demand!` / `update_wflow!` in online.jl); the goal is to switch components on or off in
Wflow itself and exchange states and fluxes through an interface.
"""

import matplotlib.pyplot as plt
from common import C, arrow, save, setup_style, slide_title
from matplotlib.patches import Circle, FancyBboxPatch

# The Wflow SBM update sequence as split in online.jl
COMPONENTS = [
    "Inter-\nception",
    "Snow",
    "Glacier",
    "Open-\nwater\nrunoff",
    "Water\ndemand",
    "Water\nallocation",
    "Soil",
    "Subsurface\nflow",
    "Overland\nflow",
    "River\nrouting",
]
REPLACED = {
    "Water\nallocation": "Ribasim\nallocation",
    "River\nrouting": "Ribasim\nrivers",
}

W, GAP, H = 1.45, 0.2, 1.3
X0 = 3.3


def block(
    ax,
    x,
    y,
    text,
    face,
    edge=None,
    text_color="white",
    ls="-",
    tab=True,
    alpha=1.0,
    z=3,
):
    ax.add_patch(
        FancyBboxPatch(
            (x, y),
            W,
            H,
            boxstyle="round,pad=0,rounding_size=0.18",
            facecolor=face,
            edgecolor=edge or face,
            lw=2.5,
            ls=ls,
            alpha=alpha,
            zorder=z,
        )
    )
    if tab:
        ax.add_patch(
            Circle(
                (x + W, y + H / 2),
                0.17,
                facecolor=face,
                edgecolor="none",
                alpha=alpha,
                zorder=z,
            )
        )
    ax.text(
        x + W / 2,
        y + H / 2,
        text,
        ha="center",
        va="center",
        fontsize=12.5,
        color=text_color,
        fontweight="bold",
        zorder=z + 1,
        linespacing=1.1,
    )


def toggle(ax, x, y, on, color):
    ax.add_patch(
        FancyBboxPatch(
            (x, y),
            0.7,
            0.36,
            boxstyle="round,pad=0,rounding_size=0.18",
            facecolor=color if on else "#D0D5DD",
            edgecolor="none",
            zorder=5,
        )
    )
    ax.add_patch(
        Circle(
            (x + (0.52 if on else 0.18), y + 0.18), 0.14, facecolor="white", zorder=6
        )
    )


setup_style()
fig, ax = plt.subplots(figsize=(19, 10.5))
fig.subplots_adjust(0.01, 0.01, 0.99, 0.86)
slide_title(
    fig,
    "Next step: a modular Wflow",
    "Ribasim should plug into Wflow components instead of the coupler copying Wflow code",
)
ax.set_xlim(0, 20)
ax.set_ylim(0, 11)
ax.set_axis_off()

xs = [X0 + i * (W + GAP) for i in range(len(COMPONENTS))]

# ---------------------------------------------------------------- Today
y = 7.6
ax.text(
    0.2,
    10.3,
    "Today: proof of concept",
    fontsize=21,
    fontweight="bold",
    color=C["shortage"],
)
block(ax, 0.3, y, "Wflow\ncore", C["wflow"], tab=False)
arrow(ax, (1.85, y + H / 2), (X0 - 0.25, y + H / 2), C["muted"], lw=3)
ax.text(
    (1.85 + X0) / 2 - 0.1,
    y + H + 0.15,
    "copy &\nmodify",
    ha="center",
    fontsize=12,
    color=C["muted"],
)
ax.add_patch(
    FancyBboxPatch(
        (X0 - 0.2, y - 1.15),
        xs[-1] + W - X0 + 0.45,
        H + 1.45,
        boxstyle="round,pad=0,rounding_size=0.3",
        facecolor="#FFF5F5",
        edgecolor=C["shortage"],
        lw=2.5,
        ls="--",
        zorder=1,
    )
)
ax.text(
    xs[-1] + W + 0.25,
    y + H + 0.5,
    "coupling script (online.jl): must follow every change in Wflow",
    fontsize=13,
    color=C["shortage"],
    ha="right",
    va="center",
)
for x, name in zip(xs, COMPONENTS):
    if name in REPLACED:
        block(
            ax,
            x,
            y,
            name,
            "white",
            edge=C["muted"],
            text_color=C["muted"],
            ls="--",
            tab=False,
        )
        ax.plot(
            [x + 0.15, x + W - 0.15],
            [y + 0.15, y + H - 0.15],
            color=C["shortage"],
            lw=3,
            zorder=6,
        )
        ax.plot(
            [x + 0.15, x + W - 0.15],
            [y + H - 0.15, y + 0.15],
            color=C["shortage"],
            lw=3,
            zorder=6,
        )
        block(ax, x + 0.3, y - 0.95, REPLACED[name], C["ribasim"], tab=False, z=7)
    else:
        block(
            ax,
            x,
            y,
            name,
            C["wflow_light"],
            edge=C["wflow"],
            text_color=C["wflow"],
            ls="--",
            tab=name != COMPONENTS[-1],
        )

# ---------------------------------------------------------------- Goal
y = 3.3
ax.text(
    0.2,
    6.0,
    "Goal: modular Wflow (development plan, WP1)",
    fontsize=21,
    fontweight="bold",
    color=C["ribasim"],
)
ax.add_patch(
    FancyBboxPatch(
        (X0 - 0.25, y - 0.3),
        xs[-1] + W - X0 + 0.55,
        H + 0.6,
        boxstyle="round,pad=0,rounding_size=0.3",
        facecolor="#EAF2FA",
        edgecolor=C["wflow"],
        lw=3,
        zorder=1,
    )
)
ax.text(
    xs[-1] + W + 0.25,
    y + H + 0.45,
    "Wflow core",
    ha="right",
    fontsize=14,
    fontweight="bold",
    color=C["wflow"],
)
for x, name in zip(xs, COMPONENTS):
    if name in REPLACED:
        ax.add_patch(
            FancyBboxPatch(
                (x, y),
                W,
                H,
                boxstyle="round,pad=0,rounding_size=0.18",
                facecolor="white",
                edgecolor=C["wflow"],
                lw=2,
                ls=(0, (4, 3)),
                zorder=2,
            )
        )
        block(ax, x, 0.7, REPLACED[name], C["ribasim"], tab=False)
        ax.add_patch(
            Circle((x + W / 2, 0.7 + H), 0.2, facecolor=C["ribasim"], zorder=3)
        )
        arrow(
            ax,
            (x + W / 2, 0.7 + H + 0.25),
            (x + W / 2, y - 0.05),
            C["ribasim"],
            lw=4,
            scale=26,
        )
    else:
        block(ax, x, y, name, C["wflow"], tab=name != COMPONENTS[-1])
ax.text(
    xs[5] + W + 0.35,
    1.35,
    "plugs in through an interface:\nexternal states & fluxes are injected",
    fontsize=14,
    color=C["ribasim"],
    va="center",
    fontweight="bold",
)

# Config file with toggles
ax.add_patch(
    FancyBboxPatch(
        (0.1, y - 1.25),
        2.55,
        3.55,
        boxstyle="round,pad=0,rounding_size=0.2",
        facecolor="white",
        edgecolor=C["muted"],
        lw=2,
        zorder=2,
    )
)
ax.text(
    1.4,
    y + 2.0,
    "config",
    ha="center",
    fontsize=13,
    fontweight="bold",
    color=C["muted"],
)
for k, (label, on) in enumerate(
    [("soil", True), ("allocation", False), ("rivers", False)]
):
    yy = y + 1.25 - k * 0.95
    ax.text(0.3, yy, label, fontsize=12, color=C["dark"], va="center")
    toggle(ax, 1.8, yy - 0.18, on, C["wflow"])
arrow(ax, (2.7, y + H / 2), (X0 - 0.3, y + H / 2), C["muted"], lw=3)

save(fig, "backup/b2_modular_wflow.png")
