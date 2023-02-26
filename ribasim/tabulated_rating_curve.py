import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("TabulatedRatingCurve",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int]
    storage: Series[float]
    discharge: Series[float]


class TabulatedRatingCurve(InputMixin, BaseModel):
    _input_type = "TabulatedRatingCurve"
    static: DataFrame[StaticSchema]
