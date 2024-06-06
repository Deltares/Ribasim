import re
from sqlite3 import connect

import numpy as np
import pandas as pd
import pytest
import xugrid
from pydantic import ValidationError
from pyproj import CRS
from ribasim import Node
from ribasim.config import Solver
from ribasim.geometry.edge import NodeData
from ribasim.input_base import esc_id
from ribasim.model import Model
from ribasim_testmodels import basic_model, trivial_model
from shapely import Point


def test_repr(basic):
    representation = repr(basic).split("\n")
    assert representation[0] == "ribasim.Model("


def test_solver():
    solver = Solver()
    assert solver.algorithm == "QNDF"  # default
    assert solver.saveat == 86400.0

    solver = Solver(saveat=3600.0)
    assert solver.saveat == 3600.0

    solver = Solver(saveat=float("inf"))
    assert solver.saveat == float("inf")

    solver = Solver(saveat=0)
    assert solver.saveat == 0

    with pytest.raises(ValidationError):
        Solver(saveat="a")


@pytest.mark.xfail(reason="Needs refactor")
def test_invalid_node_type(basic):
    # Add entry with invalid node type
    basic.node.static = basic.node.df._append(
        {"node_type": "InvalidNodeType", "geometry": Point(0, 0)}, ignore_index=True
    )

    with pytest.raises(
        TypeError,
        match=re.escape("Invalid node types detected: [InvalidNodeType].") + ".+",
    ):
        basic.validate_model_node_types()


def test_parent_relationship(basic):
    model = basic
    assert model.pump._parent == model
    assert model.pump._parent_field == "pump"


def test_exclude_unset(basic):
    model = basic
    model.solver.saveat = 86400.0
    d = model.model_dump(exclude_unset=True, exclude_none=True, by_alias=True)
    assert "solver" in d
    assert d["solver"]["saveat"] == 86400.0


def test_invalid_node_id():
    with pytest.raises(
        ValueError,
        match=r".* Input should be greater than or equal to 0 .*",
    ):
        Node(-1, Point(7.0, 7.0))


@pytest.mark.xfail(reason="Should be reimplemented by the .add() API.")
def test_node_id_duplicate(basic):
    model = basic

    # Add duplicate node ID
    df = model.pump.static.df._append(
        {"flow_rate": 1, "node_id": 1, "active": True}, ignore_index=True
    )
    # Currently can't handle mixed NaN and None in a DataFrame
    df = df.where(pd.notna(df), None)
    model.pump.static.df = df
    with pytest.raises(
        ValueError,
        match=re.escape("These node IDs were assigned to multiple node types: [1]."),
    ):
        model.validate_model_node_field_ids()


@pytest.mark.xfail(reason="Needs implementation")
def test_node_ids_misassigned(basic):
    model = basic

    # Misassign node IDs
    model.pump.static.df.loc[0, "node_id"] = 8
    model.fractional_flow.static.df.loc[1, "node_id"] = 7

    with pytest.raises(
        ValueError,
        match="For FractionalFlow, the node IDs in the data tables don't match the node IDs in the network.+",
    ):
        model.validate_model_node_ids()


@pytest.mark.xfail(reason="Needs implementation")
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
    basin.static.df["node_id"] = [1, 3, 6, 1000]

    model.validate_model_node_field_ids()


def test_tabulated_rating_curve_model(tabulated_rating_curve, tmp_path):
    model_orig = tabulated_rating_curve
    model_orig.set_crs(model_orig.crs)
    basin_area = tabulated_rating_curve.basin.area.df
    assert basin_area is not None
    assert basin_area.geometry.geom_type.iloc[0] == "Polygon"
    assert basin_area.crs == CRS.from_epsg(28992)
    model_orig.write(tmp_path / "tabulated_rating_curve/ribasim.toml")
    model_new = Model.read(tmp_path / "tabulated_rating_curve/ribasim.toml")
    pd.testing.assert_series_equal(
        model_orig.tabulated_rating_curve.time.df.time,
        model_new.tabulated_rating_curve.time.df.time,
    )


def test_plot(discrete_control_of_pid_control):
    discrete_control_of_pid_control.plot()


def test_write_adds_fid_in_tables(basic, tmp_path):
    model_orig = basic
    # for node an explicit index was provided
    nrow = len(model_orig.basin.node.df)
    assert model_orig.basin.node.df.index.name is None

    # for edge no index was provided, but it still needs to write it to file
    nrow = len(model_orig.edge.df)
    assert model_orig.edge.df.index.name == "fid"
    assert model_orig.edge.df.index.equals(pd.RangeIndex(nrow))

    model_orig.write(tmp_path / "basic/ribasim.toml")
    with connect(tmp_path / "basic/database.gpkg") as connection:
        query = f"select * from {esc_id('Basin / profile')}"
        df = pd.read_sql_query(query, connection)
        assert "fid" in df.columns

        query = "select fid from Node"
        df = pd.read_sql_query(query, connection)
        assert "fid" in df.columns

        query = "select fid from Edge"
        df = pd.read_sql_query(query, connection)
        assert "fid" in df.columns


def test_node_table(basic):
    model = basic
    node = model.node_table()
    df = node.df
    assert df.geometry.is_unique
    assert df.node_id.dtype == np.int32
    assert df.subnetwork_id.dtype == pd.Int32Dtype()
    assert df.node_type.iloc[0] == "Basin"
    assert df.node_type.iloc[-1] == "Terminal"
    assert df.crs == CRS.from_epsg(28992)


def test_edge_table(basic):
    model = basic
    df = model.edge.df
    assert df.geometry.is_unique
    assert df.from_node_id.dtype == np.int32
    assert df.subnetwork_id.dtype == pd.Int32Dtype()
    assert df.crs == CRS.from_epsg(28992)


def test_indexing(basic):
    model = basic

    result = model.basin[1]
    assert isinstance(result, NodeData)

    # Also test with a numpy type
    result = model.basin[np.int32(1)]
    assert isinstance(result, NodeData)

    with pytest.raises(TypeError, match="Basin index must be an integer, not list"):
        model.basin[[1, 3, 6]]

    result = model.basin.static[1]
    assert isinstance(result, pd.DataFrame)

    result = model.basin.static[[1, 3, 6]]
    assert isinstance(result, pd.DataFrame)

    with pytest.raises(
        IndexError, match=re.escape("Basin / static does not contain node_id: [2]")
    ):
        model.basin.static[2]

    with pytest.raises(
        ValueError,
        match=re.escape("Cannot index into Basin / time: it contains no data."),
    ):
        model.basin.time[1]


@pytest.mark.parametrize("model", [basic_model(), trivial_model()])
def test_xugrid(model, tmp_path):
    uds = model.to_xugrid(add_flow=False)
    assert isinstance(uds, xugrid.UgridDataset)
    assert uds.grid.edge_dimension == "ribasim_nEdges"
    assert uds.grid.node_dimension == "ribasim_nNodes"
    assert uds.grid.crs == CRS.from_epsg(28992)
    assert uds.node_id.dtype == np.int32
    uds.ugrid.to_netcdf(tmp_path / "ribasim.nc")
    uds = xugrid.open_dataset(tmp_path / "ribasim.nc")
    assert uds.attrs["Conventions"] == "CF-1.9 UGRID-1.0"

    with pytest.raises(FileNotFoundError, match="Model must be written to disk"):
        model.to_xugrid(add_flow=True)

    model.write(tmp_path / "ribasim.toml")
    with pytest.raises(FileNotFoundError, match="Cannot find results"):
        model.to_xugrid(add_flow=True)
    with pytest.raises(FileNotFoundError, match="or allocation is not used"):
        model.to_xugrid(add_flow=False, add_allocation=True)
    with pytest.raises(ValueError, match="Cannot add both allocation and flow results"):
        model.to_xugrid(add_flow=True, add_allocation=True)


def test_to_crs(bucket: Model):
    model = bucket

    # Reproject to World Geodetic System 1984
    model.to_crs("EPSG:4326")

    # Assert that the bucket is still at Deltares' headquarter
    assert model.basin.node.df["geometry"].iloc[0].x == pytest.approx(4.38, abs=0.1)
    assert model.basin.node.df["geometry"].iloc[0].y == pytest.approx(51.98, abs=0.1)
