import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(unique=True)
    conductance: Series[float]


class LinearLevelConnection(BaseModel, InputMixin):
    _input_type = "LinearLevelConnection"
    static: DataFrame[StaticSchema]
