from typing import Optional

import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("FlowBoundary",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.FlowBoundaryStatic)


class TimeSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.FlowBoundaryTime)
        coerce = True  # this is required, otherwise a SchemaInitError is raised


class FlowBoundary(TableModel):
    """
    Sets a precribed flow like a one-sided pump.

    Parameters
    ----------
    static : pandas.DataFrame
        Table with the constant flows.
    time : pandas.DataFrame
        Table with time-varying flow rates.
    """

    static: Optional[DataFrame[StaticSchema]] = None
    time: Optional[DataFrame[TimeSchema]] = None
