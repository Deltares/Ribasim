import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("Terminal",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.TerminalStatic)


class Terminal(TableModel):
    """
    Water sink without state or properties.

    Parameters
    ----------
    static : pd.DataFrame
        Table with only node IDs of this type.
    """

    static: DataFrame[StaticSchema]
