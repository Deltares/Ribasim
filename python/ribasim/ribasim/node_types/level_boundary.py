from typing import Optional

from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (  # type: ignore
    LevelBoundaryStaticSchema,
    LevelBoundaryTimeSchema,
)

__all__ = ("LevelBoundary",)


class LevelBoundary(TableModel):
    """
    Stores water at a given level unaffected by flow, like an infinitely large basin.

    Parameters
    ----------
    static : pandas.DataFrame
        Table with the constant water levels.
    """

    static: Optional[DataFrame[LevelBoundaryStaticSchema]] = None
    time: Optional[DataFrame[LevelBoundaryTimeSchema]] = None

    def sort(self):
        if self.static is not None:
            self.static.sort_values("node_id", ignore_index=True, inplace=True)
        if self.time is not None:
            self.time.sort_values(["time", "node_id"], ignore_index=True, inplace=True)
