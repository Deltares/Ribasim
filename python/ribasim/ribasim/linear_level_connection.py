import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("LinearLevelConnection",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    length: Series[float]
    manning_n: Series[float]
    profile_width: Series[float]
    profile_slope: Series[float]
    contraction_coefficient: Series[float]
    expansion_coefficient: Series[float]


class LinearLevelConnection(InputMixin, BaseModel):
    """
    Flow through this connection linearly depends on the level difference
    between the two connected basins.

    Parameters
    ----------
    static: pd.DataFrame

        With columns:

        * node_id
        * length
        * manning_n
        * profile_width
        * profile_slope
        * contraction_coefficient
        * expansion_coefficient

    """

    _input_type = "LinearLevelConnection"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())
