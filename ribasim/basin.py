from typing import Optional

import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(unique=True)
    drainage: Series[float] = pa.Field()
    potential_evaporation: Series[float] = pa.Field()
    infiltration: Series[float] = pa.Field()
    precipitation: Series[float] = pa.Field()
    urban_runoff: Series[float] = pa.Field()


class ForcingSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field()
    time: Series[pa.dtypes.DateTime] = pa.Field()
    drainage: Series[float] = pa.Field()
    potential_evaporation: Series[float] = pa.Field()
    infiltration: Series[float] = pa.Field()
    precipitation: Series[float] = pa.Field()
    urban_runoff: Series[float] = pa.Field()


class ProfileSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field()
    storage: Series[float] = pa.Field()
    area: Series[float] = pa.Field()
    level: Series[float] = pa.Field()


class StateSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(unique=True)
    storage: Series[float] = pa.Field()
    concentration: Series[float] = pa.Field()


class Basin(BaseModel, InputMixin):
    _input_type = "Basin"
    profile: DataFrame[ProfileSchema]
    static: Optional[DataFrame[StaticSchema]] = None
    forcing: Optional[DataFrame[ForcingSchema]] = None
    state: Optional[DataFrame[StateSchema]] = None
