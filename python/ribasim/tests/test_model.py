import pytest
from shapely import Point


def test_repr(basic):
    representation = repr(basic).split("\n")
    assert representation[0] == "<ribasim.Model>"


def test_validation(basic):
    model = basic.copy()

    node_static_old = model.node.static.copy()

    # Add entry with invalid node type
    model.node.static = model.node.static._append(
        {"type": "InvalidNodeType", "geometry": Point(0, 0)}, ignore_index=True
    )

    with pytest.raises(AssertionError) as exec_info:
        model.validate_model()

    assert exec_info.value.args[0].startswith(
        "InvalidNodeType is not a valid node type, choose from:"
    )

    # Revert to proper data
    model.node.static = node_static_old

    # Add entry with invalid node ID
    model.pump.static = model.pump.static._append(
        {"flow_rate": 1, "node_id": -1, "remarks": ""}, ignore_index=True
    )

    with pytest.raises(AssertionError) as exec_info:
        model.validate_model()

    assert (
        exec_info.value.args[0]
        == "Invalid number of unique node IDs in node type fields"
    )
