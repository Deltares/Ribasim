"""Generate node icon artifacts and embed them into QGIS NodeStyle.qml.

This utility renders node icons from the shared Matplotlib definitions in
`ribasim.node_icons`, writes SVG/PNG files to `utils/node_icons/`, updates
embedded SVG marker data in the QGIS node style file, and optionally uploads
the icons to the Ribasim S3 bucket under ``doc-image/node-icons/``.

Run with ``--upload`` to upload to S3 (requires MinIO credentials).
"""

import argparse
import math
from base64 import b64encode
from io import BytesIO
from pathlib import Path
from uuid import uuid4

import lxml.etree as ET
import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
from ribasim.node_icons import NODE_ICON_DATA, draw_icon

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

QGIS_MARKER_SIZE_MM = 6.6
QGIS_DOCTYPE = "<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>"


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


# Save individual icons
svg_base64_by_qgis_value: dict[str, str] = {}
for spec in NODE_ICON_DATA:
    node_type = spec.node_type
    color = spec.color
    shape = spec.shape_code

    fig, ax = plt.subplots(figsize=(1, 1))
    ax.set_position((0.0, 0.0, 1.0, 1.0))
    draw_icon(ax, shape, color)

    # save svg
    svg_bytes_buffer = BytesIO()
    fig.savefig(svg_bytes_buffer, format="svg", transparent=True)
    svg_bytes = svg_bytes_buffer.getvalue()

    svg_path = svg_dir / f"{node_type}.svg"
    svg_path.write_bytes(svg_bytes)

    # 30x30 png icon
    png_path = png_dir / f"{node_type}.png"
    fig.savefig(
        png_path,
        format="png",
        dpi=30,
        transparent=True,
    )
    plt.close(fig)

    qgis_value = node_type
    svg_base64_by_qgis_value[qgis_value] = b64encode(svg_bytes).decode("ascii")


def create_overview(output="overview.png", cols=4):
    num = len(NODE_ICON_DATA)
    rows = math.ceil(num / cols)
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 2, rows * 2))
    fig.patch.set_facecolor("#F0F0F0")
    axes = axes.flatten()

    for ax in axes[num:]:
        ax.axis("off")

    for spec, ax in zip(NODE_ICON_DATA, axes, strict=False):
        draw_icon(ax, spec.shape_code, spec.color)
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
        label = spec.node_type
        ax.set_title(label, fontsize=8)

    plt.tight_layout()
    out_path = results_dir / output
    plt.savefig(out_path, dpi=100)
    plt.close(fig)


create_overview()
generate_node_style_embed(
    source_qml=node_style_qml_path,
    svg_base64_by_qgis_value=svg_base64_by_qgis_value,
    size_mm=QGIS_MARKER_SIZE_MM,
)


# ── S3 upload ─────────────────────────────────────────────────────
S3_PREFIX = "doc-image/node-icons"


def upload_to_s3() -> None:
    """Upload all generated icons (SVG, PNG, overview) to S3."""
    from s3_upload import upload_file

    files_to_upload: list[tuple[Path, str]] = []

    for spec in NODE_ICON_DATA:
        name = spec.node_type
        svg_path = svg_dir / f"{name}.svg"
        png_path = png_dir / f"{name}.png"
        files_to_upload.append((svg_path, f"{S3_PREFIX}/svg/{svg_path.name}"))
        files_to_upload.append((png_path, f"{S3_PREFIX}/png/{png_path.name}"))

    # Overview
    overview_path = results_dir / "overview.png"
    if overview_path.exists():
        files_to_upload.append((overview_path, f"{S3_PREFIX}/overview.png"))

    for local_path, remote_key in files_to_upload:
        print(f"  {remote_key}")
        upload_file(local_path, remote_key)

    print(f"Uploaded {len(files_to_upload)} files to {S3_PREFIX}/")


if __name__ == "__main__" or not hasattr(__builtins__, "__IPYTHON__"):
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument(
        "--upload", action="store_true", help="Upload icons to S3 after generation"
    )
    args = cli.parse_args()
    if args.upload:
        upload_to_s3()
