from typing import Optional

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


class ForcingSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.BasinForcing)


class ProfileSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.BasinProfile)


class StateSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.BasinState)


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

    def sort(self):
        self.profile = self.profile.sort_values(
            ["node_id", "storage"], ignore_index=True
        )
        if self.static is not None:
            self.static = self.static.sort_values("node_id", ignore_index=True)
        if self.forcing is not None:
            self.forcing = self.forcing.sort_values(
                ["time", "node_id"], ignore_index=True
            )
        if self.state is not None:
            self.state = self.state.sort_values("node_id", ignore_index=True)
