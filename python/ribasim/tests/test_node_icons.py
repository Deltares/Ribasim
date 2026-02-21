from pathlib import Path

import lxml.etree as ET
from ribasim.geometry.node import NodeModel
from ribasim.node_icons import (
    ICON_SCALE,
    NODE_ICON_BY_PASCAL,
    NODE_ICON_DATA,
    make_icon_box,
)


def _node_style_category_values() -> set[str]:
    qml_path = (
        Path(__file__).resolve().parents[1] / "ribasim" / "styles" / "NodeStyle.qml"
    )
    parser = ET.XMLParser(
        remove_blank_text=True, resolve_entities=False, no_network=True
    )
    tree = ET.parse(str(qml_path), parser=parser)
    categories = tree.findall(
        ".//renderer-v2[@type='categorizedSymbol'][@attr='node_type']/categories/category"
    )
    return {
        value
        for category in categories
        if (value := category.get("value")) is not None and value != "NULL"
    }


def _node_model_types() -> set[str]:
    """Collect PascalCase names of all NodeModel subclasses (e.g. 'Basin')."""
    return {cls.__name__ for cls in NodeModel.__subclasses__()}


def test_every_node_model_has_icon() -> None:
    """Every NodeModel subclass must have an entry in NODE_ICON_DATA."""
    assert _node_model_types() == set(NODE_ICON_BY_PASCAL)


def test_icons_match_qml_categories() -> None:
    """NODE_ICON_DATA must stay in sync with the QGIS NodeStyle.qml categories."""
    assert {s.node_type for s in NODE_ICON_DATA} == _node_style_category_values()


def test_icon_scale_covers_all_shapes() -> None:
    assert {s.shape_code for s in NODE_ICON_DATA} <= set(ICON_SCALE)


def test_make_icon_box_all_node_types() -> None:
    for spec in NODE_ICON_DATA:
        box = make_icon_box(spec.node_type)
        assert box.get_children(), f"No patches for {spec.node_type}"
