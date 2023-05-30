import pytest
from shapely import Point


def test_repr(basic):
    representation = repr(basic).split("\n")
    assert representation[0] == "<ribasim.Model>"


def test_invalid_node_type(basic):
    model = basic.copy()

    # Add entry with invalid node type
    model.node.static = model.node.static._append(
        {"type": "InvalidNodeType", "geometry": Point(0, 0)}, ignore_index=True
    )

    with pytest.raises(TypeError) as exec_info:
        model.validate_model()

    assert exec_info.value.args[0].startswith(
        "InvalidNodeType is not a valid node type, choose from:"
    )


def test_invalid_node_id(basic):
    model = basic.copy()

    # Add entry with invalid node ID
    model.pump.static = model.pump.static._append(
        {"flow_rate": 1, "node_id": -1, "remarks": ""}, ignore_index=True
    )

    with pytest.raises(ValueError) as exec_info:
        model.validate_model()

    assert exec_info.value.args[0] == "Node IDs must be positive integers, got [-1]."


def test_node_id_duplicate(basic):
    model = basic.copy()

    # Add duplicate node ID
    model.pump.static = model.pump.static._append(
        {"flow_rate": 1, "node_id": 1, "remarks": ""}, ignore_index=True
    )

    with pytest.raises(ValueError) as exec_info:
        model.validate_model()

    assert (
        exec_info.value.args[0]
        == "These node ID(s) were assigned to multiple node types: [1]."
    )


def test_missing_node_id(basic):
    model = basic.copy()

    # Add entry in node but not in pump
    model.node.static = model.node.static._append(
        {"type": "Pump", "geometry": Point(0, 0)}, ignore_index=True
    )

    with pytest.raises(ValueError) as exec_info:
        model.validate_model()
    assert (
        exec_info.value.args[0]
        == "Expected node IDs from 1 to 18 (the number of rows in self.node.static), but these node IDs are missing: {18}."
    )
