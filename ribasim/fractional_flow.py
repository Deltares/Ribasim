from typing import Optional

import pandera as pa
from pandera.dtypes import Int
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("FractionalFlow",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[Int]
    fraction: Series[float]


class ForcingSchema(pa.SchemaModel):
    node_id: Series[Int]
    time: Series[pa.dtypes.DateTime]
    fraction: Series[float]


class FractionalFlow(InputMixin, BaseModel):
    _input_type = "FractionalFlow"
    static: DataFrame[StaticSchema]
    forcing: Optional[DataFrame[ForcingSchema]] = None
