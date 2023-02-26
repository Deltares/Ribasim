from typing import Optional

import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("FractionalFlow",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    fraction: Series[float]


class ForcingSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    time: Series[pa.dtypes.DateTime]
    fraction: Series[float]


class FractionalFlow(InputMixin, BaseModel):
    _input_type = "FractionalFlow"
    static: DataFrame[StaticSchema]
    forcing: Optional[DataFrame[ForcingSchema]] = None
