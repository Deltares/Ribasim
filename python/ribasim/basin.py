from typing import Optional

import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("Basin",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    drainage: Series[float]
    potential_evaporation: Series[float]
    infiltration: Series[float]
    precipitation: Series[float]
    urban_runoff: Series[float]


class ForcingSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    time: Series[pa.dtypes.DateTime]
    drainage: Series[float]
    potential_evaporation: Series[float]
    infiltration: Series[float]
    precipitation: Series[float]
    urban_runoff: Series[float]


class ProfileSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    storage: Series[float]
    area: Series[float]
    level: Series[float]


class StateSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    storage: Series[float]
    concentration: Series[float]


class Basin(InputMixin, BaseModel):
    """
    Input for a (sub-)basin: an area of land where all flowing surface water
    converges to a single point.

    Parameters
    ----------
    profile: pandas.DataFrame

        A tabulation with the columns:

        * storage
        * area
        * water level

    static: pandas.DataFrame, optional

        Static forcing with columns:

        * potential evaporation
        * precipitation
        * groundwater drainage
        * groundwater infiltration
        * urban runoff

    forcing: pandas.DataFrame, optional

        Time varying forcing with columns:

        * time
        * potential evaporation
        * precipitation
        * groundwater drainage
        * groundwater infiltration
        * urban runoff

    state: pandas.DataFrame, optional

        Initial state with columns:

        * storage
        * concentration

    """

    _input_type = "Basin"
    profile: DataFrame[ProfileSchema]
    static: Optional[DataFrame[StaticSchema]] = None
    forcing: Optional[DataFrame[ForcingSchema]] = None
    state: Optional[DataFrame[StateSchema]] = None

    class Config:
        validate_assignment = True

    def __init__(
        self,
        profile: pd.DataFrame,
        static: Optional[pd.DataFrame] = None,
        forcing: Optional[pd.DataFrame] = None,
        state: Optional[pd.DataFrame] = None,
    ):
        super().__init__(**locals())
