import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("LinearResistance",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.LinearResistanceStatic)


class LinearResistance(TableModel):
    """
    Flow through this connection linearly depends on the level difference
    between the two connected basins.

    Parameters
    ----------
    static : pd.DataFrame
        Table with the constant resistances.
    """

    static: DataFrame[StaticSchema]
