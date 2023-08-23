from typing import Optional

import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("PidControl",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.PidControlStatic)


class TimeSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.PidControlTime)


class PidControl(TableModel):
    """
    Controller based on PID (Proportional, integral, derivative) which
    controls the level of a single basin with a pump.

    Parameters
    ----------
    static: pandas.DataFrame
        Table with data for this node type.
    time : pandas.DataFrame, optional
        Table with time-varying data for this node type.
    """

    static: Optional[DataFrame[StaticSchema]] = None
    time: Optional[DataFrame[TimeSchema]] = None

    class Config:
        validate_assignment = True
