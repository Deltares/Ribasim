import re

import pytest
from shapely import Point


def test_repr(basic):
    representation = repr(basic).split("\n")
    assert representation[0] == "<ribasim.Model>"


def test_invalid_node_type(basic):
    model = basic

    # Add entry with invalid node type
    model.node.static = model.node.static._append(
        {"type": "InvalidNodeType", "geometry": Point(0, 0)}, ignore_index=True
    )

    with pytest.raises(
        TypeError,
        match=re.escape("Invalid node types detected: [InvalidNodeType].") + ".+",
    ):
        model.validate_model_node_types()


def test_invalid_node_id(basic):
    model = basic

    # Add entry with invalid node ID
    model.pump.static = model.pump.static._append(
        {"flow_rate": 1, "node_id": -1, "remarks": ""}, ignore_index=True
    )

    with pytest.raises(
        ValueError,
        match=re.escape("Node IDs must be positive integers, got [-1]."),
    ):
        model.validate_model_node_field_IDs()


def test_node_id_duplicate(basic):
    model = basic

    # Add duplicate node ID
    model.pump.static = model.pump.static._append(
        {"flow_rate": 1, "node_id": 1, "remarks": ""}, ignore_index=True
    )

    with pytest.raises(
        ValueError,
        match=re.escape("These node IDs were assigned to multiple node types: [1]."),
    ):
        model.validate_model_node_field_IDs()


def test_missing_node_id(basic):
    model = basic

    # Add entry in node but not in pump
    model.node.static = model.node.static._append(
        {"type": "Pump", "geometry": Point(0, 0)}, ignore_index=True
    )

    with pytest.raises(ValueError, match="Expected node IDs from.+"):
        model.validate_model_node_field_IDs()


def test_node_ids_misassigned(basic):
    model = basic

    # Misassign node IDs
    model.pump.static.loc[0, "node_id"] = 8
    model.fractional_flow.static.loc[1, "node_id"] = 7

    with pytest.raises(ValueError, match="The node IDs in the field fractional_flow.+"):
        model.validate_model_node_IDs()
