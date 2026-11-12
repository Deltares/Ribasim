"""Combined strengths: Wflow's detailed land hydrology + Ribasim's controlled surface water and allocation.

Left: a window of real Piave grid cells, zooming in from one cell to the Wflow SBM concept
figure from the Wflow.jl documentation.
Right: a Ribasim network with control and prioritized allocation, using `ribasim.node_icons`.
"""

import matplotlib.pyplot as plt
import numpy as np
from common import (
    SOURCE_IMAGES,
    C,
    load_wflow,
    north_up,
    save,
    setup_style,
    slide_title,
)
from matplotlib.colors import LinearSegmentedColormap, Normalize, to_rgba
from matplotlib.offsetbox import AnnotationBbox
from matplotlib.patches import (
    Circle,
    FancyBboxPatch,
    Rectangle,
)
from ribasim.node_icons import make_icon_box
from scipy import ndimage

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
fig, ax = plt.subplots(figsize=(22, 10.5))
fig.subplots_adjust(0.01, 0.01, 0.99, 0.87)
slide_title(
    fig,
    "Two strengths, one coupled model",
    "Wflow describes how water moves through the landscape; Ribasim how people store, steer and share it",
)
# The Wflow panel is wider than the Ribasim panel and extends to negative x, so the Ribasim
# coordinates below stay as they are. The figure is limited by the slide height, so the extra
# width does not shrink it.
WFLOW_LEFT = -3.1
ax.set_xlim(WFLOW_LEFT - 0.2, 20)
ax.set_ylim(0.7, 11)
ax.set_aspect("equal")
ax.set_axis_off()

# ------------------------------------------------------------------ Wflow
panel(ax, WFLOW_LEFT, 3.0, 9.3 - WFLOW_LEFT, 7.8, "#EAF2FA")
ax.text(
    WFLOW_LEFT + 0.4, 10.25, "Wflow", fontsize=26, fontweight="bold", color=C["wflow"]
)
ax.text(
    WFLOW_LEFT + 2.35,
    10.25,
    "detailed, spatially resolved hydrology",
    fontsize=16,
    color=C["wflow"],
    va="baseline",
)

# The Wflow SBM concept figure from the Wflow.jl documentation
# (Wflow.jl/docs/images/wflow_sbm_soil.png), on a white card since the image is transparent
# with black lines and labels.
sbm = plt.imread(SOURCE_IMAGES / "wflow_sbm_soil.png")
img_w = 9.0
img_h = img_w * sbm.shape[0] / sbm.shape[1]
img_x, img_y = 9.1 - img_w, 3.3

# A window of real Piave grid cells (shaded by elevation, river cells blue), zooming in from
# one land cell next to the river to the SBM concept: every cell runs this column.
N_WINDOW = 9
ds = load_wflow()
lat = ds.latitude.to_numpy()
elevation = north_up(ds["land_elevation"].to_numpy(), lat)
river = north_up(ds["river_mask"].to_numpy(), lat) == 1


def window_score(i: int, j: int) -> float:
    """Prefer complete windows with one thin river crossing close to the centre."""
    elev = elevation[i : i + N_WINDOW, j : j + N_WINDOW]
    riv = river[i : i + N_WINDOW, j : j + N_WINDOW]
    if np.isnan(elev).any() or not N_WINDOW <= riv.sum() <= N_WINDOW + 4:
        return -np.inf
    # A single connected river that enters and leaves the window
    _, n_components = ndimage.label(riv, structure=np.ones((3, 3)))
    sides = [riv[0].any(), riv[-1].any(), riv[:, 0].any(), riv[:, -1].any()]
    if n_components != 1 or sum(sides) < 2:
        return -np.inf
    # Thin: no 2x2 blocks of river cells
    blocks = riv[:-1, :-1] & riv[1:, :-1] & riv[:-1, 1:] & riv[1:, 1:]
    if blocks.any():
        return -np.inf
    centre = (N_WINDOW - 1) / 2
    distance = np.abs(np.argwhere(riv) - centre).sum(axis=1).min()
    return -float(distance) - float(np.nanstd(elev)) / 100


ni, nj = elevation.shape
i0, j0 = max(
    (
        (i, j)
        for i in range(ni - N_WINDOW)
        for j in range(nj - N_WINDOW)
        if np.isfinite(window_score(i, j))
    ),
    key=lambda ij: window_score(*ij),
)
elev = elevation[i0 : i0 + N_WINDOW, j0 : j0 + N_WINDOW]
riv = river[i0 : i0 + N_WINDOW, j0 : j0 + N_WINDOW]
# A calm single-hue ramp so the river cells stand out from the land cells
land = LinearSegmentedColormap.from_list("land", ["#DDE9C6", "#86B169"])
rgb = land(Normalize(np.nanmin(elev), np.nanmax(elev))(elev))
rgb[riv] = to_rgba(C["water"])

grid_size = 2.55
grid_x, grid_y = WFLOW_LEFT + 0.3, 5.2
cell_size = grid_size / N_WINDOW
ax.imshow(
    rgb,
    extent=(grid_x, grid_x + grid_size, grid_y, grid_y + grid_size),
    origin="upper",
    interpolation="nearest",
    zorder=2,
)
for k in range(N_WINDOW + 1):
    ax.plot(
        [grid_x, grid_x + grid_size],
        [grid_y + k * cell_size] * 2,
        color="white",
        lw=1.2,
        zorder=3,
    )
    ax.plot(
        [grid_x + k * cell_size] * 2,
        [grid_y, grid_y + grid_size],
        color="white",
        lw=1.2,
        zorder=3,
    )

# Highlight a land cell next to the river, close to the centre of the window
river_cells = np.argwhere(riv)
candidates = [
    (r, c)
    for r in range(1, N_WINDOW - 1)
    for c in range(1, N_WINDOW - 1)
    if not riv[r, c] and np.abs(river_cells - (r, c)).sum(axis=1).min() == 1
]
row, col = min(candidates, key=lambda rc: abs(rc[0] - 4) + abs(rc[1] - 4))
hx = grid_x + col * cell_size
hy = grid_y + (N_WINDOW - 1 - row) * cell_size
ax.add_patch(
    Rectangle(
        (hx, hy),
        cell_size,
        cell_size,
        facecolor="none",
        edgecolor=C["dark"],
        lw=3,
        zorder=5,
    )
)
# Zoom lines from the highlighted cell to the corners of the SBM card
for cy, iy in ((hy + cell_size, img_y + img_h), (hy, img_y)):
    ax.plot(
        [hx + cell_size, img_x],
        [cy, iy],
        color=C["dark"],
        lw=1.5,
        ls=(0, (4, 3)),
        zorder=1,
    )

ax.add_patch(
    FancyBboxPatch(
        (img_x, img_y),
        img_w,
        img_h,
        boxstyle="round,pad=0.05,rounding_size=0.2",
        facecolor="white",
        edgecolor="none",
        zorder=1,
    )
)
ax.imshow(
    sbm,
    extent=(img_x, img_x + img_w, img_y, img_y + img_h),
    zorder=2,
    interpolation="antialiased",
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
    strict=True,
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
        (WFLOW_LEFT, 0.8),
        19.8 - WFLOW_LEFT,
        1.4,
        boxstyle="round,pad=0,rounding_size=0.3",
        facecolor=C["light"],
        edgecolor="none",
    )
)
ax.text(
    (WFLOW_LEFT + 19.8) / 2,
    1.75,
    "Coupled: overland and subsurface flow and irrigation demand from every cell,",
    ha="center",
    va="center",
    fontsize=18,
    color=C["dark"],
    fontweight="bold",
)
ax.text(
    (WFLOW_LEFT + 19.8) / 2,
    1.23,
    "managed and allocated through the controlled surface water network",
    ha="center",
    va="center",
    fontsize=18,
    color=C["dark"],
    fontweight="bold",
)


save(fig, "01_combined_strengths.png")
