import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("TabulatedRatingCurve",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    level: Series[float]
    discharge: Series[float]


class TabulatedRatingCurve(InputMixin, BaseModel):
    """
    Linearly interpolates discharge between a tabulation of level and discharge.

    Parameters
    ----------
    static: pd.DataFrame

        Tabulation with columns:

        * node_id
        * level
        * discharge

    """

    _input_type = "TabulatedRatingCurve"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())
