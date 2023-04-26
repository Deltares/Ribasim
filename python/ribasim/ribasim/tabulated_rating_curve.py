from typing import Optional

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


class TimeSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    time: Series[pa.dtypes.DateTime]
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

    time: pandas.DataFrame, optional

        Time varying rating curves with columns:

        * node_id
        * time
        * level
        * discharge
    """

    _input_type = "TabulatedRatingCurve"
    static: DataFrame[StaticSchema]
    time: Optional[DataFrame[StaticSchema]] = None

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame, time: Optional[pd.DataFrame] = None):
        super().__init__(**locals())

    def sort(self):
        self.static = self.static.sort_values(["node_id", "level"], ignore_index=True)
        if self.time is not None:
            self.time = self.time.sort_values(
                ["time", "node_id", "level"], ignore_index=True
            )
