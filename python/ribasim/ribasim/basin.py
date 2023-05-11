from typing import Optional

import pandas as pd
import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame
from pydantic import BaseModel

from ribasim import models
from ribasim.input_base import InputMixin

__all__ = ("Basin",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.BasinStatic)
        coerce = True  # this is required, otherwise a SchemaInitError is raised


class ForcingSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.BasinForcing)
        coerce = True  # this is required, otherwise a SchemaInitError is raised


class ProfileSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.BasinProfile)
        coerce = True  # this is required, otherwise a SchemaInitError is raised


class StateSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.BasinState)
        coerce = True  # this is required, otherwise a SchemaInitError is raised


class Basin(InputMixin, BaseModel):
    """
    Input for a (sub-)basin: an area of land where all flowing surface water
    converges to a single point.

    Parameters
    ----------
    profile: pandas.DataFrame

        A tabulation with the columns:

        * node_id
        * storage
        * area
        * water level

    static: pandas.DataFrame, optional

        Static forcing with columns:

        * node_id
        * potential evaporation
        * precipitation
        * groundwater drainage
        * groundwater infiltration
        * urban runoff

    forcing: pandas.DataFrame, optional

        Time varying forcing with columns:

        * node_id
        * time
        * potential evaporation
        * precipitation
        * groundwater drainage
        * groundwater infiltration
        * urban runoff

    state: pandas.DataFrame, optional

        Initial state with columns:

        * node_id
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
