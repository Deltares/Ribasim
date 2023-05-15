import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("ManningResistance",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    length: Series[float]
    manning_n: Series[float]
    profile_width: Series[float]
    profile_slope: Series[float]


class ManningResistance(InputMixin, BaseModel):
    """
    Flow through this connection is estimated by conservation of energy and the
    Manning-Gauckler formula to estimate friction losses.

    Parameters
    ----------
    static : pd.DataFrame

        With columns:

        * node_id
        * length
        * manning_n
        * profile_width
        * profile_slope

    """

    _input_type = "ManningResistance"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())
