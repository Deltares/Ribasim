from typing import Optional

import pandera as pa
from pandera.dtypes import Int
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("Basin",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[Int] = pa.Field(unique=True)
    drainage: Series[float]
    potential_evaporation: Series[float]
    infiltration: Series[float]
    precipitation: Series[float]
    urban_runoff: Series[float]


class ForcingSchema(pa.SchemaModel):
    node_id: Series[Int]
    time: Series[pa.dtypes.DateTime]
    drainage: Series[float]
    potential_evaporation: Series[float]
    infiltration: Series[float]
    precipitation: Series[float]
    urban_runoff: Series[float]


class ProfileSchema(pa.SchemaModel):
    node_id: Series[Int]
    storage: Series[float]
    area: Series[float]
    level: Series[float]


class StateSchema(pa.SchemaModel):
    node_id: Series[Int] = pa.Field(unique=True)
    storage: Series[float]
    concentration: Series[float]


class Basin(InputMixin, BaseModel):
    """
    Input for a (sub-)basin: an area of land where all flowing surface water
    converges to a single point.

    A basin is defined by a tabulation of:

    * storage
    * area
    * water level

    This data is provided by the ``profile`` DataFrame.

    In Ribasim, the basin receives water balance terms such as:

    * potential evaporation
    * precipitation
    * groundwater drainage
    * groundwater infiltration
    * urban runoff

    This may be set in the ``static`` dataframe for constant data, or ``forcing``
    for time varying data.

    A basin may be initialized with an initial state for storage or
    concentration. This is set in the ``state`` dataframe.
    """

    _input_type = "Basin"
    profile: DataFrame[ProfileSchema]
    static: Optional[DataFrame[StaticSchema]] = None
    forcing: Optional[DataFrame[ForcingSchema]] = None
    state: Optional[DataFrame[StateSchema]] = None
