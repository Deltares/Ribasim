import re

import pandas as pd
import pytest
from pydantic import ValidationError
from ribasim import Model, Solver
from shapely import Point


def test_repr(basic):
    representation = repr(basic).split("\n")
    assert representation[0] == "<ribasim.Model>"


def test_solver():
    solver = Solver()
    assert solver.algorithm == "QNDF"  # default
    assert solver.saveat == []

    solver = Solver(saveat=3600.0)
    assert solver.saveat == 3600.0

    solver = Solver(saveat=[3600.0, 7200.0])
    assert solver.saveat == [3600.0, 7200.0]

    with pytest.raises(ValidationError):
        Solver(saveat="a")


def test_invalid_node_type(basic):
    # Add entry with invalid node type
    basic.node.static = basic.node.static._append(
        {"type": "InvalidNodeType", "geometry": Point(0, 0)}, ignore_index=True
    )

    with pytest.raises(
        TypeError,
        match=re.escape("Invalid node types detected: [InvalidNodeType].") + ".+",
    ):
        basic.validate_model_node_types()


def test_invalid_node_id(basic):
    model = basic

    # Add entry with invalid node ID
    model.pump.static = model.pump.static._append(
        {"flow_rate": 1, "node_id": -1, "remarks": "", "active": True},
        ignore_index=True,
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
        {"flow_rate": 1, "node_id": 1, "remarks": "", "active": True}, ignore_index=True
    )

    with pytest.raises(
        ValueError,
        match=re.escape("These node IDs were assigned to multiple node types: [1]."),
    ):
        model.validate_model_node_field_IDs()


def test_node_ids_misassigned(basic):
    model = basic

    # Misassign node IDs
    model.pump.static.loc[0, "node_id"] = 8
    model.fractional_flow.static.loc[1, "node_id"] = 7

    with pytest.raises(ValueError, match="The node IDs in the field fractional_flow.+"):
        model.validate_model_node_IDs()


def test_node_ids_unsequential(basic):
    model = basic

    basin = model.basin

    basin.profile = pd.DataFrame(
        data={
            "node_id": [1, 1, 3, 3, 6, 6, 1000, 1000],
            "area": [0.01, 1000.0] * 4,
            "level": [0.0, 1.0] * 4,
        }
    )

    basin.static["node_id"] = [1, 3, 6, 1000]

    with pytest.raises(ValueError) as excinfo:
        model.validate_model_node_field_IDs()

    assert (
        "Expected node IDs from 1 to 17 (the number of rows in self.node.static). These node IDs are missing: {9}. These node IDs are unexpected: {1000}."
        in str(excinfo.value)
    )


def test_tabulated_rating_curve_model(tabulated_rating_curve, tmp_path):
    model_orig = tabulated_rating_curve
    model_orig.write(tmp_path / "tabulated_rating_curve")
    Model.from_toml(tmp_path / "tabulated_rating_curve/tabulated_rating_curve.toml")
