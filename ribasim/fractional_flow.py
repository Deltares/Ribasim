from typing import Optional

import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin


class StaticSchema(pa.SchemaModel):
    node_id: Series[int]
    fraction: Series[float]


class ForcingSchema(pa.SchemaModel):
    node_id: Series[int]
    time: Series[pa.dtypes.DateTime]
    fraction: Series[float]


class FractionalFlow(BaseModel, InputMixin):
    _input_type = "FractionalFlow"
    static: DataFrame[StaticSchema]
    forcing: Optional[DataFrame[ForcingSchema]] = None
