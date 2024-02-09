from ribasim.input_base import TableModel
from ribasim.schemas import BasinSubgridSchema


def test_tablemodel_schema():
    schema = TableModel[BasinSubgridSchema].tableschema()
    assert schema == BasinSubgridSchema
