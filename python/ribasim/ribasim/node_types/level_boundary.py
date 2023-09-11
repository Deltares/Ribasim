from typing import Optional

from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import LevelBoundaryStaticSchema, LevelBoundaryTimeSchema

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
