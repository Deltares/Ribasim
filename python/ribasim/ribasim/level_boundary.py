import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("LevelBoundary",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    level: Series[float]


class LevelBoundary(InputMixin, BaseModel):
    """
    Stores water at a given level unaffected by flow, like an infinitely large basin.

    Parameters
    ----------
    static : pandas.DataFrame

        With columns:

        * node_id
        * level
    """

    _input_type = "LevelBoundary"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())
