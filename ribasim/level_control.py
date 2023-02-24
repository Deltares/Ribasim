import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(unique=True)
    target_level: Series[float] = pa.Field()


class LevelControl(BaseModel, InputMixin):
    _input_type = "LevelControl"
    static: DataFrame[StaticSchema]
