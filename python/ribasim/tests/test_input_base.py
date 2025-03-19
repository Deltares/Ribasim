from ribasim import geometry, nodes
from ribasim.input_base import TableModel
from ribasim.schemas import BasinSubgridSchema


def test_tablemodel_schema():
    schema = TableModel[BasinSubgridSchema].tableschema()
    assert schema == BasinSubgridSchema


def test_tablename():
    cls = nodes.tabulated_rating_curve.Static
    assert cls.tablename() == "TabulatedRatingCurve / static"

    cls = nodes.basin.ConcentrationExternal
    assert cls.tablename() == "Basin / concentration_external"

    cls = geometry.link.LinkTable
    assert cls.tablename() == "Link"
