from typing import Optional

import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("TabulatedRatingCurve",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.TabulatedRatingCurveStatic)
        coerce = True  # this is required, otherwise a SchemaInitError is raised


class TimeSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.TabulatedRatingCurveTime)
        coerce = True  # this is required, otherwise a SchemaInitError is raised


class TabulatedRatingCurve(TableModel):
    """
    Linearly interpolates discharge between a tabulation of level and discharge.

    Parameters
    ----------
    static : pd.DataFrame
        Table with constant rating curves.
    time : pandas.DataFrame, optional
        Table with time-varying rating curves.
    """

    static: DataFrame[StaticSchema]
    time: Optional[DataFrame[TimeSchema]] = None

    class Config:
        validate_assignment = True

    def sort(self):
        self.static = self.static.sort_values(["node_id", "level"], ignore_index=True)
        if self.time is not None:
            self.time = self.time.sort_values(
                ["time", "node_id", "level"], ignore_index=True
            )
