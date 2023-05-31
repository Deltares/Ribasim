import pandera as pa
from pandera.typing import DataFrame, Series

from ribasim.input_base import TableModel

__all__ = ("Terminal",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)


class Terminal(TableModel):
    """
    Water sink without state or properties.

    Parameters
    ----------
    static : pd.DataFrame
        Table with only node IDs of this type.
    """

    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True
