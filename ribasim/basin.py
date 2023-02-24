from typing import Optional

import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(unique=True)
    drainage: Series[float]
    potential_evaporation: Series[float]
    infiltration: Series[float]
    precipitation: Series[float]
    urban_runoff: Series[float]


class ForcingSchema(pa.SchemaModel):
    node_id: Series[int]
    time: Series[pa.dtypes.DateTime]
    drainage: Series[float]
    potential_evaporation: Series[float]
    infiltration: Series[float]
    precipitation: Series[float]
    urban_runoff: Series[float]


class ProfileSchema(pa.SchemaModel):
    node_id: Series[int]
    storage: Series[float]
    area: Series[float]
    level: Series[float]


class StateSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(unique=True)
    storage: Series[float]
    concentration: Series[float]


class Basin(BaseModel, InputMixin):
    _input_type = "Basin"
    profile: DataFrame[ProfileSchema]
    static: Optional[DataFrame[StaticSchema]] = None
    forcing: Optional[DataFrame[ForcingSchema]] = None
    state: Optional[DataFrame[StateSchema]] = None
