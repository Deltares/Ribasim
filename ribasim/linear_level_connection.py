import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("LinearLevelConnection",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    conductance: Series[float]


class LinearLevelConnection(InputMixin, BaseModel):
    _input_type = "LinearLevelConnection"
    static: DataFrame[StaticSchema]
