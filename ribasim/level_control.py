import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("LevelControl",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    target_level: Series[float]


class LevelControl(InputMixin, BaseModel):
    _input_type = "LevelControl"
    static: DataFrame[StaticSchema]
