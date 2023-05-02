import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("LinearLevelConnection",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    conductance: Series[float]


class LinearLevelConnection(InputMixin, BaseModel):
    """
    Flow through this connection linearly depends on the level difference
    between the two connected basins.

    Parameters
    ----------
    static: pd.DataFrame

        With columns:

        * node_id
        * conductance

    """

    _input_type = "LinearLevelConnection"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())
