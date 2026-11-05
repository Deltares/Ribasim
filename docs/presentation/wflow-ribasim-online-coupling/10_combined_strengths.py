"""Combined strengths: Wflow's detailed land hydrology + Ribasim's controlled surface water and allocation.

Left: a Wflow soil column on a grid with vertical and lateral processes.
Right: a Ribasim network with control and prioritized allocation, using `ribasim.node_icons`.
"""

import matplotlib.pyplot as plt
from common import C, arrow, cloud, save, setup_style, slide_title
from matplotlib.offsetbox import AnnotationBbox
from matplotlib.patches import Circle, FancyBboxPatch, Polygon, Rectangle
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
ax.set_ylim(1.2, 11)
ax.set_aspect("equal")
ax.set_axis_off()

# ------------------------------------------------------------------ Wflow
panel(ax, 0.2, 3.3, 9.1, 7.5, "#EAF2FA")
ax.text(0.6, 10.25, "Wflow", fontsize=26, fontweight="bold", color=C["wflow"])
ax.text(
    2.55,
    10.25,
    "detailed, spatially resolved hydrology",
    fontsize=16,
    color=C["wflow"],
    va="baseline",
)

# Grid of columns in oblique view; the middle one is cut open to show the layers
ox, oy, cw, ch, dx, dy = 1.2, 4.3, 1.15, 3.4, 0.55, 0.4
layers = [
    ("unsaturated\nzone", "#C8A97E", 1.1),
    ("saturated\nzone", "#9C7B55", 1.3),
    ("", "#7A5C3E", 1.0),
]
for j in range(4):
    x0 = ox + j * cw
    top = oy + ch
    ax.add_patch(
        Polygon(
            [(x0, top), (x0 + cw, top), (x0 + cw + dx, top + dy), (x0 + dx, top + dy)],
            closed=True,
            facecolor="#A7CF7E" if j != 3 else C["wflow_light"],
            edgecolor="white",
            lw=1.5,
            zorder=3,
        )
    )
    y = top
    for name, color, h in layers:
        ax.add_patch(
            Rectangle(
                (x0, y - h),
                cw,
                h,
                facecolor=color,
                edgecolor="white",
                lw=1.5,
                zorder=3,
                alpha=1.0 if j == 1 else 0.55,
            )
        )
        if False:
            ax.text(
                x0 + cw / 2,
                y - h / 2,
                name,
                ha="center",
                va="center",
                fontsize=10.5,
                color="white",
                fontweight="bold",
                zorder=4,
            )
        y -= h
xr = ox + 4 * cw
ax.add_patch(
    Polygon(
        [(xr, oy), (xr, oy + ch), (xr + dx, oy + ch + dy), (xr + dx, oy + dy)],
        closed=True,
        facecolor="#8E7350",
        edgecolor="white",
        zorder=2,
    )
)
ax.text(
    ox + 3.5 * cw + 0.3,
    oy + ch + dy + 0.1,
    "river cell",
    ha="center",
    fontsize=11,
    color=C["wflow"],
    fontweight="bold",
)

# Vertical processes on the open column
cx = ox + 1.5 * cw
cloud(ax, cx + 0.2, 9.4, 0.45, color="#D0D5DD", zorder=6)
for k in range(4):
    ax.plot(
        [cx - 0.3 + 0.2 * k, cx - 0.4 + 0.2 * k],
        [9.0, 8.6],
        color=C["water"],
        lw=2.5,
        zorder=6,
    )
ax.add_patch(Circle((ox + 2.9 * cw, 9.35), 0.35, facecolor="#FFD166", zorder=6))
arrow(ax, (ox + 2.9 * cw, 8.1), (ox + 2.9 * cw, 8.9), C["irrigation"], lw=2.5, scale=16)
ax.text(
    cx - 0.75,
    8.75,
    "rain\n& snow",
    ha="right",
    va="center",
    fontsize=12,
    color=C["water_dark"],
)
ax.text(
    ox + 2.9 * cw + 0.15,
    8.45,
    "evaporation",
    ha="left",
    va="center",
    fontsize=12,
    color="#9A4D00",
)
ax.text(
    cx + 0.12,
    oy + ch - 0.55,
    "infiltration",
    ha="left",
    va="center",
    fontsize=11,
    color="white",
    fontweight="bold",
    zorder=6,
)
ax.text(
    cx + 0.42,
    oy + ch - 1.55,
    "percolation",
    ha="left",
    va="center",
    fontsize=11,
    color="white",
    fontweight="bold",
    zorder=6,
)
ax.text(
    ox + 0.2,
    oy + ch + 0.42,
    "overland flow",
    fontsize=12,
    color=C["water_dark"],
    fontweight="bold",
)
ax.text(
    ox + 0.1,
    oy + ch - 2.05,
    "subsurface flow",
    fontsize=12,
    color="white",
    fontweight="bold",
    zorder=6,
)
arrow(ax, (cx, oy + ch - 0.05), (cx, oy + ch - 0.95), C["wflow"], lw=3, scale=18)
arrow(
    ax, (cx + 0.3, oy + ch - 1.2), (cx + 0.3, oy + ch - 1.9), C["wflow"], lw=3, scale=18
)
for k, (yy, label) in enumerate(
    [(oy + ch + 0.15, "overland flow"), (oy + ch - 1.7, "subsurface flow")]
):
    arrow(
        ax,
        (ox + 0.2, yy),
        (ox + 3.9 * cw, yy - 0.05),
        C["water_dark"],
        lw=3,
        scale=20,
        rad=0.0,
    )
labels = ["rain & snow", "interception", "evaporation", "infiltration", "percolation"]
icons_x = 8.55
ax.text(
    ox + 4.35 * cw + 0.75,
    oy + 1.6,
    "vertical\n+\nlateral",
    ha="left",
    va="center",
    fontsize=14,
    color=C["wflow"],
    fontweight="bold",
)

# ------------------------------------------------------------------ Ribasim
panel(ax, 10.7, 3.3, 9.1, 7.5, "#EAF6EC")
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
    [(1, "drinking\nwater", 1.0), (2, "irrigation", 0.7), (3, "industry", 0.3)],
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
        x + 0.38,
        y + 0.3,
        f"P{prio}",
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
        (2.5, 1.4),
        15.0,
        1.4,
        boxstyle="round,pad=0,rounding_size=0.3",
        facecolor=C["dark"],
        edgecolor="none",
    )
)
ax.text(
    10.0,
    2.35,
    "Coupled: realistic runoff and irrigation demand from every cell,",
    ha="center",
    va="center",
    fontsize=18,
    color="white",
    fontweight="bold",
)
ax.text(
    10.0,
    1.83,
    "managed and allocated through the controlled surface water network",
    ha="center",
    va="center",
    fontsize=18,
    color="white",
    fontweight="bold",
)


save(fig, "10_combined_strengths.png")
