from typing import Optional

import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

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


class Basin(TableModel):
    """
    Input for a (sub-)basin: an area of land where all flowing surface water
    converges to a single point.

    Parameters
    ----------
    profile : pandas.DataFrame
        Table describing the geometry.
    static : pandas.DataFrame, optional
        Table describing the constant fluxes.
    forcing : pandas.DataFrame, optional
        Table describing the time-varying fluxes.
    state : pandas.DataFrame, optional
        Table describing the initial condition.
    """

    profile: DataFrame[ProfileSchema]
    static: Optional[DataFrame[StaticSchema]] = None
    forcing: Optional[DataFrame[ForcingSchema]] = None
    state: Optional[DataFrame[StateSchema]] = None

    class Config:
        validate_assignment = True

    def sort(self):
        self.profile = self.profile.sort_values(["node_id", "level"], ignore_index=True)
        if self.static is not None:
            self.static = self.static.sort_values("node_id", ignore_index=True)
        if self.forcing is not None:
            self.forcing = self.forcing.sort_values(
                ["time", "node_id"], ignore_index=True
            )
        if self.state is not None:
            self.state = self.state.sort_values("node_id", ignore_index=True)
