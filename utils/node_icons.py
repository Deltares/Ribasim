import math
from pathlib import Path

import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.patches import PathPatch
from matplotlib.path import Path as MplPath
from PIL import Image

# dir where this script is located
script_dir = Path(__file__).resolve().parent

results_dir = script_dir / "node_icons"
results_dir.mkdir(parents=True, exist_ok=True)

small_icon_dir = results_dir / "small_png"
small_icon_dir.mkdir(parents=True, exist_ok=True)


# %% Database icons

# fmt: off
data = [
    ("basin",                  "#0072B2", "trapezium",      "Trapezium"),
    ("manning_resistance",     "#F0E442", "v",              "Down triangle"),
    ("linear_resistance",      "#009E73", "^",              "Up triangle"),
    ("flow_boundary",          "#FF7F00", "o",              ""),
    ("level_boundary",         "#FFFFFF", "o",              "Empty circle"),
    ("tabulated_rating_curve", "#CC79A7", "D",              "Diamond"),
    ("pump",                   "#999999", "H",              "Hexagon (flat top)"),
    ("outlet",                 "#D55E00", "pointed_circle", "Pointed circle"),
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


# %%
def create_star(num_points, inner_radius=0.1, outer_radius=0.25):
    verts = []
    codes = [MplPath.MOVETO]
    angle = 2 * np.pi / (num_points * 2)

    for i in range(num_points * 2):
        r = outer_radius if i % 2 == 0 else inner_radius
        x = 0.5 + r * np.cos(i * angle - np.pi / 2)
        y = 0.5 + r * np.sin(i * angle - np.pi / 2)
        verts.append((x, y))
        codes.append(MplPath.LINETO)

    verts.append(verts[0])  # clse path
    codes[-1] = MplPath.CLOSEPOLY
    return PathPatch(
        MplPath(verts, codes), facecolor=None, edgecolor="black", linewidth=1
    )


# %%

figsize = (1, 1)
marker_size = 1000

# Custom shape-based marker sizes
shape_scaling = {
    "D": 600,
    "^": 900,
    "v": 900,
    "s": 850,
    "o": 900,
    "H": 950,
    "pointed_circle": 1.0,  # scale outer/inner manually
    "star5": (0.12, 0.28),
    "star6": (0.14, 0.3),
    "star4": (0.15, 0.32),
    "trapezium": 1.0,
    "rectangle": 1.0,
    "half_square_t": 1.0,
    "half_square_b": 1.0,
}


for _, row in df.iterrows():
    node_type = row["node_type"]
    color = row["color"]
    shape = row["shape_code"]
    label = row.get("label", "")

    fig = plt.figure(figsize=figsize)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_aspect("equal", adjustable="box")

    if shape == "rectangle":
        # custom rectangle
        rect = mpatches.Rectangle(
            (0.5 - 0.2, 0.5 - 0.1), 0.4, 0.2, facecolor=color, edgecolor="black"
        )
        ax.add_patch(rect)

    elif shape == "trapezium":
        top_width = 0.6
        bottom_width = 0.3
        height = 0.5

        top_y = 0.5 + height / 2
        bottom_y = 0.5 - height / 2

        verts = [
            (0.5 - top_width / 2, top_y),  # top-left
            (0.5 + top_width / 2, top_y),  # top-right
            (0.5 + bottom_width / 2, bottom_y),  # bottom-right
            (0.5 - bottom_width / 2, bottom_y),  # bottom-left
        ]

        trapezium = mpatches.Polygon(
            verts, closed=True, facecolor=color, edgecolor="black", linewidth=1
        )
        ax.add_patch(trapezium)

    elif shape == "pointed_circle":
        # outlet should have outer circle + inner dot
        outer = mpatches.Circle(
            (0.5, 0.5), 0.25, facecolor="none", edgecolor="black", linewidth=2
        )
        inner = mpatches.Circle((0.5, 0.5), 0.1, facecolor=color, edgecolor="none")
        ax.add_patch(outer)
        ax.add_patch(inner)

    elif shape == "star5":
        star = create_star(num_points=5, inner_radius=0.12, outer_radius=0.25)
        star.set_facecolor(color)
        ax.add_patch(star)

    elif shape == "star6":
        star = create_star(num_points=6, inner_radius=0.12, outer_radius=0.25)
        star.set_facecolor(color)
        ax.add_patch(star)

    elif shape == "star4":
        star = create_star(num_points=4, inner_radius=0.14, outer_radius=0.25)
        star.set_facecolor(color)
        ax.add_patch(star)

    elif shape == "half_square_t":
        # outer square border
        square = mpatches.Rectangle(
            (0.5 - 0.25, 0.5 - 0.25),
            0.5,
            0.5,
            facecolor="white",
            edgecolor="black",
            linewidth=1,
        )
        # top half filled
        fill = mpatches.Rectangle(
            (0.5 - 0.25, 0.5), 0.5, 0.25, facecolor=color, edgecolor="black"
        )
        ax.add_patch(square)
        ax.add_patch(fill)

    elif shape == "half_square_b":
        # outer square border
        square = mpatches.Rectangle(
            (0.5 - 0.25, 0.5 - 0.25),
            0.5,
            0.5,
            facecolor="white",
            edgecolor="black",
            linewidth=1,
        )
        # bottom half filled
        fill = mpatches.Rectangle(
            (0.5 - 0.25, 0.5 - 0.25), 0.5, 0.25, facecolor=color, edgecolor="black"
        )
        ax.add_patch(square)
        ax.add_patch(fill)

    else:
        # normal scatter marker
        safe_edgecolor_shapes = {"^", "v", "s", "D", "o", "H"}
        use_edge = shape in safe_edgecolor_shapes
        this_size = shape_scaling.get(shape, marker_size)

        current_marker_size = 500 if node_type == "junction" else this_size
        ax.scatter(
            0.5,
            0.5,
            marker=shape,
            color=color,
            s=current_marker_size,
            edgecolors="black" if use_edge else None,
        )

    # avoid too much padding
    ax.set_xlim(0.1, 0.9)
    ax.set_ylim(0.1, 0.9)
    ax.axis("off")

    # save svg
    filename = results_dir / f"{node_type}.svg"
    plt.savefig(filename, format="svg", bbox_inches="tight", transparent=True)

    # PNG needed for overview
    png_filename = results_dir / f"{node_type}.png"
    plt.savefig(
        png_filename, format="png", dpi=300, bbox_inches="tight", transparent=True
    )

    # 36x36 png icon
    small_png_filename = small_icon_dir / f"{node_type}.png"
    plt.savefig(
        small_png_filename,
        format="png",
        dpi=30,
        transparent=True,
    )
    plt.close(fig)

print("saved to 'results' folder")


# %% overview


def create_overview(results_dir, output="overview.png", cols=4):
    files = sorted(
        f for f in results_dir.iterdir() if f.suffix == ".png" and f.name != output
    )
    num = len(files)
    rows = math.ceil(num / cols)
    _, axes = plt.subplots(rows, cols, figsize=(cols * 2, rows * 2))
    axes = axes.flatten()

    for ax in axes[num:]:
        ax.axis("off")

    for _i, (file_path, ax) in enumerate(zip(files, axes, strict=False)):
        img = Image.open(file_path)
        ax.imshow(img)
        ax.axis("off")
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
        label = file_path.stem.replace("_", "\n")
        ax.set_title(label, fontsize=8)

    plt.tight_layout()
    out_path = results_dir / output
    plt.savefig(out_path, dpi=300)


create_overview(results_dir)

print(f" png icons saved to: {small_icon_dir}")
