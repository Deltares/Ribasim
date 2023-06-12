import pandas as pd
import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("LevelBoundary",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.LevelBoundaryStatic)


class LevelBoundary(TableModel):
    """
    Stores water at a given level unaffected by flow, like an infinitely large basin.

    Parameters
    ----------
    static : pandas.DataFrame
        Table with the constant water levels.
    """

    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(static=static)
