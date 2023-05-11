from typing import Optional

import pandas as pd
import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame
from pydantic import BaseModel

from ribasim import models
from ribasim.input_base import InputMixin

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
