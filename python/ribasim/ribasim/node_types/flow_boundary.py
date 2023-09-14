from typing import Optional

from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (  # type: ignore
    FlowBoundaryStaticSchema,
    FlowBoundaryTimeSchema,
)

__all__ = ("FlowBoundary",)


class FlowBoundary(TableModel):
    """
    Sets a precribed flow like a one-sided pump.

    Parameters
    ----------
    static : pandas.DataFrame
        Table with the constant flows.
    time : pandas.DataFrame
        Table with time-varying flow rates.
    """

    static: Optional[DataFrame[FlowBoundaryStaticSchema]] = None
    time: Optional[DataFrame[FlowBoundaryTimeSchema]] = None

    def sort(self):
        if self.static is not None:
            self.static.sort_values("node_id", ignore_index=True, inplace=True)
        if self.time is not None:
            self.time.sort_values(["time", "node_id"], ignore_index=True, inplace=True)
