import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("LevelControl",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    target_level: Series[float]


class LevelControl(InputMixin, BaseModel):
    """
    Controls the level in a basin.

    Parameters
    ----------
    static: pandas.DataFrame

        With columns:

        * node_id
        * target_level

    """

    _input_type = "LevelControl"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())
