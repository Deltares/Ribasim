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
