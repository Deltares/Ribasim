import pandas as pd
import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame
from pydantic import BaseModel

from ribasim import models
from ribasim.input_base import InputMixin

__all__ = ("LevelControl",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.LevelControlStatic)
        coerce = True  # this is required, otherwise a SchemaInitError is raised


class LevelControl(InputMixin, BaseModel):
    """
    Controls the level in a basin.

    Parameters
    ----------
    static: pandas.DataFrame

        With columns:

        * node_id
        * target_level
        * conductance

    """

    _input_type = "LevelControl"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True
