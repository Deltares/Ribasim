from typing import Optional

import pandas as pd
import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim import models
from ribasim.input_base import InputMixin

__all__ = ("FractionalFlow",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.FractionalFlowStatic)
        coerce = True  # this is required, otherwise a SchemaInitError is raised


class ForcingSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    time: Series[pa.dtypes.DateTime]
    fraction: Series[float]


class FractionalFlow(InputMixin, BaseModel):
    """
    Receives a fraction of the flow. The fractions must sum to 1.0 for a
    furcation.

    Parameters
    ----------
    static: pandas.DataFrame

        With columns:

        * node_id
        * fraction

    forcing: pandas.DataFrame, optional

        With columns:

        * node_id
        * time
        * fraction

    """

    _input_type = "FractionalFlow"
    static: DataFrame[StaticSchema]
    forcing: Optional[DataFrame[ForcingSchema]] = None

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame, forcing: Optional[pd.DataFrame] = None):
        super().__init__(**locals())
