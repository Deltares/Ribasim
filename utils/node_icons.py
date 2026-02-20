import math
from base64 import b64encode
from io import BytesIO
from pathlib import Path
from uuid import uuid4

import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from lxml import etree as ET
from matplotlib.markers import MarkerStyle
from matplotlib.patches import PathPatch
from matplotlib.path import Path as MplPath
from matplotlib.transforms import Affine2D

# dir where this script is located
script_dir = Path(__file__).resolve().parent
repo_dir = script_dir.parent

results_dir = script_dir / "node_icons"
results_dir.mkdir(parents=True, exist_ok=True)

svg_dir = results_dir / "svg"
svg_dir.mkdir(parents=True, exist_ok=True)

png_dir = results_dir / "png"
png_dir.mkdir(parents=True, exist_ok=True)

node_style_qml_path = repo_dir / "python/ribasim/ribasim/styles/NodeStyle.qml"
node_style_qml_plugin_path = repo_dir / "ribasim_qgis/core/styles/NodeStyle.qml"

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


# Scale factor per shape, applied to:
# - patch coordinates directly
# fmt: off
ICON_SCALE = {
    "rectangle":      2.4,
    "trapezium":      1.1,
    "pentagon":       1.2,
    "star5":          1.8,
    "star6":          1.8,
    "star4":          1.8,
    "half_square_t":  1.2,
    "half_square_b":  1.2,
    "D":              1.8,
    "^":              2.1,
    "v":              2.1,
    "s":              2.35,
    "o":              2.2,
    "H":              2.4,
}
# fmt: on

QGIS_MARKER_SIZE_MM = 6.6
QGIS_DOCTYPE = "<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>"


def create_marker_patch(marker, scale, color, edgecolor="black", linewidth=1):
    marker_style = MarkerStyle(marker)
    marker_path = marker_style.get_path().transformed(marker_style.get_transform())
    transformed = marker_path.transformed(Affine2D().scale(0.25 * scale))
    return PathPatch(
        transformed,
        facecolor=color,
        edgecolor=edgecolor,
        linewidth=linewidth,
    )


def snake_to_pascal_case(name: str) -> str:
    return "".join(part.capitalize() for part in name.split("_"))


def create_svg_marker_layer(layer_id: str, svg_base64: str, size_mm: float):
    layer = ET.Element(
        "layer",
        {
            "pass": "0",
            "locked": "0",
            "id": layer_id,
            "class": "SvgMarker",
            "enabled": "1",
        },
    )

    options = ET.SubElement(layer, "Option", {"type": "Map"})

    def add_option(name: str, value: str | None = None, option_type: str = "QString"):
        attributes = {"name": name}
        if value is not None:
            attributes["value"] = value
            attributes["type"] = option_type
        ET.SubElement(options, "Option", attributes)

    add_option("name", f"base64:{svg_base64}")
    add_option("size", f"{size_mm:g}")
    add_option("size_unit", "MM")

    data_defined_properties = ET.SubElement(layer, "data_defined_properties")
    ddp_option = ET.SubElement(data_defined_properties, "Option", {"type": "Map"})
    ET.SubElement(
        ddp_option, "Option", {"name": "name", "value": "", "type": "QString"}
    )
    ET.SubElement(ddp_option, "Option", {"name": "properties"})
    ET.SubElement(
        ddp_option,
        "Option",
        {"name": "type", "value": "collection", "type": "QString"},
    )

    return layer


def generate_node_style_embed(
    source_qml: Path,
    svg_base64_by_qgis_value: dict[str, str],
    size_mm: float,
):
    parser = ET.XMLParser(
        remove_blank_text=True, resolve_entities=False, no_network=True
    )
    tree = ET.parse(str(source_qml), parser=parser)
    root = tree.getroot()
    if root is None:
        raise RuntimeError(f"No XML root found in {source_qml}")

    renderer = root.find(".//renderer-v2[@type='categorizedSymbol'][@attr='node_type']")

    if renderer is None:
        raise RuntimeError("Node categorized renderer not found in NodeStyle.qml")

    categories = renderer.find("categories")
    symbols = renderer.find("symbols")
    if categories is None or symbols is None:
        raise RuntimeError("Missing categories or symbols section in NodeStyle.qml")

    qgis_value_by_symbol_name = {
        category.get("symbol"): category.get("value")
        for category in categories.findall("category")
        if category.get("symbol") is not None
    }

    for symbol in symbols.findall("symbol"):
        symbol_name = symbol.get("name")
        qgis_value = qgis_value_by_symbol_name.get(symbol_name)
        if qgis_value is None or qgis_value not in svg_base64_by_qgis_value:
            continue

        old_layer = symbol.find("layer")
        if old_layer is None:
            continue

        layer_id = old_layer.get("id") or f"{{{uuid4()}}}"
        new_layer = create_svg_marker_layer(
            layer_id=layer_id,
            svg_base64=svg_base64_by_qgis_value[qgis_value],
            size_mm=size_mm,
        )

        layer_index = list(symbol).index(old_layer)
        symbol.remove(old_layer)
        symbol.insert(layer_index, new_layer)

    tree.write(
        str(source_qml),
        encoding="utf-8",
        pretty_print=True,
        xml_declaration=False,
        doctype=QGIS_DOCTYPE,
    )


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
        marker_patch = create_marker_patch(shape, s, color)
        ax.add_patch(marker_patch)

    ax.set_xlim(-0.5, 0.5)
    ax.set_ylim(-0.5, 0.5)
    ax.set_aspect("equal", adjustable="box")
    ax.axis("off")


# Save individual icons
svg_base64_by_qgis_value: dict[str, str] = {}
for _, row in df.iterrows():
    node_type = row["node_type"]
    color = row["color"]
    shape = row["shape_code"]

    fig, ax = plt.subplots(figsize=(1, 1))
    ax.set_position((0.0, 0.0, 1.0, 1.0))
    draw_icon(ax, shape, color, node_type)

    # save svg
    svg_bytes_buffer = BytesIO()
    fig.savefig(svg_bytes_buffer, format="svg", transparent=True)
    svg_bytes = svg_bytes_buffer.getvalue()

    svg_path = svg_dir / f"{node_type}.svg"
    svg_path.write_bytes(svg_bytes)

    # 30x30 png icon
    png_path = png_dir / f"{node_type}.png"
    plt.savefig(
        png_path,
        format="png",
        dpi=30,
        transparent=True,
    )
    plt.close(fig)

    qgis_value = snake_to_pascal_case(node_type)
    svg_base64_by_qgis_value[qgis_value] = b64encode(svg_bytes).decode("ascii")


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
generate_node_style_embed(
    source_qml=node_style_qml_path,
    svg_base64_by_qgis_value=svg_base64_by_qgis_value,
    size_mm=QGIS_MARKER_SIZE_MM,
)

if node_style_qml_plugin_path.exists() and (
    node_style_qml_plugin_path.resolve() != node_style_qml_path.resolve()
):
    generate_node_style_embed(
        source_qml=node_style_qml_plugin_path,
        svg_base64_by_qgis_value=svg_base64_by_qgis_value,
        size_mm=QGIS_MARKER_SIZE_MM,
    )
