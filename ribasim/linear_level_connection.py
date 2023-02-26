import pandera as pa
from pandera.dtypes import Int
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("LinearLevelConnection",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[Int] = pa.Field(unique=True)
    conductance: Series[float]


class LinearLevelConnection(InputMixin, BaseModel):
    _input_type = "LinearLevelConnection"
    static: DataFrame[StaticSchema]
