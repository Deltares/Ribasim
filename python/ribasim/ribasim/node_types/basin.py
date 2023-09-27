from typing import Optional

from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (  # type: ignore
    BasinProfileSchema,
    BasinStateSchema,
    BasinStaticSchema,
    BasinTimeSchema,
)

__all__ = ("Basin",)


class Basin(TableModel):
    """
    Input for a (sub-)basin: an area of land where all flowing surface water converges to a single point.

    Parameters
    ----------
    profile : pandas.DataFrame
        Table describing the geometry.
    static : pandas.DataFrame, optional
        Table describing the constant fluxes.
    time : pandas.DataFrame, optional
        Table describing the time-varying fluxes.
    state : pandas.DataFrame, optional
        Table describing the initial condition.
    """

    profile: DataFrame[BasinProfileSchema]
    static: Optional[DataFrame[BasinStaticSchema]] = None
    time: Optional[DataFrame[BasinTimeSchema]] = None
    state: Optional[DataFrame[BasinStateSchema]] = None

    def sort(self):
        self.profile.sort_values(["node_id", "level"], ignore_index=True, inplace=True)
        if self.static is not None:
            self.static.sort_values("node_id", ignore_index=True, inplace=True)
        if self.time is not None:
            self.time.sort_values(["time", "node_id"], ignore_index=True, inplace=True)
        if self.state is not None:
            self.state.sort_values("node_id", ignore_index=True, inplace=True)
