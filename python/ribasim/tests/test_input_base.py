from pathlib import Path

from ribasim import Model, Node
from ribasim.input_base import TableModel
from ribasim.nodes import basin
from ribasim.schemas import BasinSubgridSchema
from shapely.geometry import Point


def test_tablemodel_schema():
    schema = TableModel[BasinSubgridSchema].tableschema()
    assert schema == BasinSubgridSchema


def test_tablename():
    from ribasim import geometry, nodes

    cls = nodes.tabulated_rating_curve.Static
    assert cls.tablename() == "TabulatedRatingCurve / static"

    cls = nodes.basin.ConcentrationExternal
    assert cls.tablename() == "Basin / concentration_external"

    cls = geometry.NodeTable
    assert cls.tablename() == "Node"

    cls = geometry.LinkTable
    assert cls.tablename() == "Link"


def test_set_filepath_notifies_parents():
    """Test that setting filepath updates model_fields_set up the parent chain."""
    # Create a model with a basin
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [basin.Profile(level=[0.0, 1.0], area=[100.0, 1000.0])],
    )

    # profile is already in model_fields_set from add(), so clear it to test filepath
    model.basin.model_fields_set.discard("profile")
    model.model_fields_set.discard("basin")

    # Verify we've cleared it
    assert "profile" not in model.basin.model_fields_set

    # Set filepath using direct assignment (Pythonic way)
    model.basin.profile.filepath = Path("profile1.nc")

    # Now both the NodeModel and Model should have the fields marked as set
    assert "profile" in model.basin.model_fields_set, (
        "profile should be in basin.model_fields_set"
    )
    assert "basin" in model.model_fields_set, (
        "basin should be in model.model_fields_set"
    )

    # Verify the filepath was actually set
    assert model.basin.profile.filepath == Path("profile1.nc")


def test_filepath_appears_in_toml(tmp_path):
    """Integration test: verify filepath is written to TOML and data to external file."""
    import tomli

    # Create a model with basin profile data
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [basin.Profile(level=[0.0, 1.0, 2.0], area=[100.0, 500.0, 1000.0])],
    )

    # Set filepath using direct assignment
    model.basin.profile.filepath = Path("profile.nc")

    # Write the model
    toml_path = tmp_path / "test_model" / "ribasim.toml"
    model.write(toml_path)

    # Verify TOML contains the filepath reference
    with Path.open(toml_path, "rb") as f:
        toml_data = tomli.load(f)

    assert "basin" in toml_data, "basin section should be in TOML"
    assert toml_data["basin"]["profile"] == "profile.nc", (
        "profile filepath should be in TOML"
    )

    # Verify the NetCDF file was created
    nc_path = tmp_path / "test_model" / "input" / "profile.nc"
    assert nc_path.exists(), f"NetCDF file should exist at {nc_path}"

    # Verify the NetCDF file contains the data
    import xarray as xr

    with xr.open_dataset(nc_path) as ds:
        assert "node_id" in ds.dims, "node_id should be a dimension"
        assert "level" in ds.variables, "level should be in the dataset"
        assert "area" in ds.variables, "area should be in the dataset"
        assert len(ds["level"]) == 3, "Should have 3 profile points"
