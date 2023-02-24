import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field()
    storage: Series[float] = pa.Field()
    discharge: Series[float] = pa.Field()


class TabulatedRatingCurve(BaseModel, InputMixin):
    _input_type = "TabulatedRatingCurve"
    static: DataFrame[StaticSchema]
