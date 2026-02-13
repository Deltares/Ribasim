import math
from pathlib import Path

import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.patches import PathPatch
from matplotlib.path import Path as MplPath

# dir where this script is located
script_dir = Path(__file__).resolve().parent

results_dir = script_dir / "node_icons"
results_dir.mkdir(parents=True, exist_ok=True)

svg_dir = results_dir / "svg"
svg_dir.mkdir(parents=True, exist_ok=True)

png_dir = results_dir / "png"
png_dir.mkdir(parents=True, exist_ok=True)

# fmt: off
data = [
    ("basin",                  "#0072B2", "trapezium",      "Trapezium"),
    ("manning_resistance",     "#F0E442", "v",              "Down triangle"),
    ("linear_resistance",      "#009E73", "^",              "Up triangle"),
    ("flow_boundary",          "#FF7F00", "o",              ""),
    ("level_boundary",         "#FFFFFF", "o",              "Empty circle"),
    ("tabulated_rating_curve", "#CC79A7", "D",              "Diamond"),
    ("pump",                   "#999999", "H",              "Hexagon (flat top)"),
    ("outlet",                 "#D55E00", "pentagon",       "Pentagon"),
    ("user_demand",            "#E41A1C", "s",              "Square"),
    ("level_demand",           "#E69F00", "half_square_t",  "Square half-filled"),
    ("flow_demand",            "#228B22", "half_square_b",  "Square half-filled"),
    ("discrete_control",       "#984EA3", "star5",          "5-point star"),
    ("pid_control",            "#006400", "star6",          "6-point star (snowflake)"),
    ("continuous_control",     "#999999", "star4",          "4-point star"),
    ("terminal",               "#000000", "rectangle",      "horizontal rectangle"),
    ("junction",               "#000000", "o",              "filled circle"),
]
# fmt: on

df = pd.DataFrame(
    data, columns=["node_type", "color", "shape_code", "shape_description"]
)


def create_star(num_points, inner_radius=0.1, outer_radius=0.25):
    verts = []
    codes = [MplPath.MOVETO]
    angle = 2 * np.pi / (num_points * 2)

    for i in range(num_points * 2):
        r = outer_radius if i % 2 == 0 else inner_radius
        x = r * np.cos(i * angle - np.pi / 2)
        y = r * np.sin(i * angle - np.pi / 2)
        verts.append((x, y))
        codes.append(MplPath.LINETO)

    verts.append(verts[0])  # close path
    codes[-1] = MplPath.CLOSEPOLY
    return PathPatch(
        MplPath(verts, codes), facecolor=None, edgecolor="black", linewidth=1
    )


MARKER_BASE = 800

# Scale factor per shape, applied to:
# - patch coordinates directly
# - scatter marker size as MARKER_BASE * scale²
# fmt: off
ICON_SCALE = {
    "rectangle":      2.4,
    "trapezium":      1.1,
    "pentagon":       1.5,
    "star5":          1.8,
    "star6":          1.8,
    "star4":          1.8,
    "half_square_t":  1.2,
    "half_square_b":  1.2,
    "D":              1.8,
    "^":              2.1,
    "v":              2.1,
    "s":              2.2,
    "o":              2.2,
    "H":              2.4,
}
# fmt: on


def draw_icon(ax, shape, color, node_type):
    """Draw a node icon on the given axes, centered at (0, 0)."""
    s = ICON_SCALE[shape]

    if shape == "rectangle":
        w, h = 0.4 * s, 0.2 * s
        rect = mpatches.Rectangle(
            (-w / 2, -h / 2), w, h, facecolor=color, edgecolor="black"
        )
        ax.add_patch(rect)

    elif shape == "trapezium":
        tw = 0.3 * s
        bw = 0.15 * s
        hh = 0.25 * s
        verts = [
            (-tw, hh),
            (tw, hh),
            (bw, -hh),
            (-bw, -hh),
        ]
        trapezium = mpatches.Polygon(
            verts, closed=True, facecolor=color, edgecolor="black", linewidth=1
        )
        ax.add_patch(trapezium)

    elif shape == "pentagon":
        r = 0.25 * s
        verts = [
            (
                r * np.cos(i * 2 * np.pi / 5 - np.pi / 2),
                r * np.sin(i * 2 * np.pi / 5 - np.pi / 2),
            )
            for i in range(5)
        ]
        pentagon = mpatches.Polygon(
            verts, closed=True, facecolor=color, edgecolor="black", linewidth=1
        )
        ax.add_patch(pentagon)

    elif shape == "star5":
        star = create_star(num_points=5, inner_radius=0.12 * s, outer_radius=0.25 * s)
        star.set_facecolor(color)
        ax.add_patch(star)

    elif shape == "star6":
        star = create_star(num_points=6, inner_radius=0.12 * s, outer_radius=0.25 * s)
        star.set_facecolor(color)
        ax.add_patch(star)

    elif shape == "star4":
        star = create_star(num_points=4, inner_radius=0.14 * s, outer_radius=0.25 * s)
        star.set_facecolor(color)
        ax.add_patch(star)

    elif shape == "half_square_t":
        half = 0.25 * s
        square = mpatches.Rectangle(
            (-half, -half),
            2 * half,
            2 * half,
            facecolor="white",
            edgecolor="black",
            linewidth=1,
        )
        fill = mpatches.Rectangle(
            (-half, 0), 2 * half, half, facecolor=color, edgecolor="black"
        )
        ax.add_patch(square)
        ax.add_patch(fill)

    elif shape == "half_square_b":
        half = 0.25 * s
        square = mpatches.Rectangle(
            (-half, -half),
            2 * half,
            2 * half,
            facecolor="white",
            edgecolor="black",
            linewidth=1,
        )
        fill = mpatches.Rectangle(
            (-half, -half), 2 * half, half, facecolor=color, edgecolor="black"
        )
        ax.add_patch(square)
        ax.add_patch(fill)

    else:
        safe_edgecolor_shapes = {"^", "v", "s", "D", "o", "H"}
        use_edge = shape in safe_edgecolor_shapes
        marker_size = MARKER_BASE * s * s
        ax.scatter(
            0,
            0,
            marker=shape,
            color=color,
            s=marker_size,
            edgecolors="black" if use_edge else None,
            clip_on=False,
        )

    ax.set_xlim(-0.5, 0.5)
    ax.set_ylim(-0.5, 0.5)
    ax.set_aspect("equal", adjustable="box")
    ax.axis("off")


# Save individual icons
for _, row in df.iterrows():
    node_type = row["node_type"]
    color = row["color"]
    shape = row["shape_code"]

    fig = plt.figure(figsize=(1, 1))
    ax = fig.add_axes([0, 0, 1, 1])
    draw_icon(ax, shape, color, node_type)

    # save svg
    svg_path = svg_dir / f"{node_type}.svg"
    plt.savefig(svg_path, format="svg", transparent=True)

    # 30x30 png icon
    png_path = png_dir / f"{node_type}.png"
    plt.savefig(
        png_path,
        format="png",
        dpi=30,
        transparent=True,
    )
    plt.close(fig)


def create_overview(df, results_dir, output="overview.png", cols=4):
    num = len(df)
    rows = math.ceil(num / cols)
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 2, rows * 2))
    fig.patch.set_facecolor("#F0F0F0")
    axes = axes.flatten()

    for ax in axes[num:]:
        ax.axis("off")

    for (_, row), ax in zip(df.iterrows(), axes, strict=False):
        draw_icon(ax, row["shape_code"], row["color"], row["node_type"])
        ax.add_patch(
            mpatches.Rectangle(
                (0, 0),
                1,
                1,
                transform=ax.transAxes,
                fill=False,
                edgecolor="black",
                linewidth=1,
            )
        )
        label = row["node_type"].replace("_", "\n")
        ax.set_title(label, fontsize=8)

    plt.tight_layout()
    out_path = results_dir / output
    plt.savefig(out_path, dpi=100)
    plt.close(fig)


create_overview(df, results_dir)
