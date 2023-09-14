from typing import Optional

from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (  # type: ignore
    TabulatedRatingCurveStaticSchema,
    TabulatedRatingCurveTimeSchema,
)

__all__ = ("TabulatedRatingCurve",)


class TabulatedRatingCurve(TableModel):
    """
    Linearly interpolates discharge between a tabulation of level and discharge.

    Parameters
    ----------
    static : pd.DataFrame
        Table with constant rating curves.
    time : pandas.DataFrame, optional
        Table with time-varying rating curves.
    """

    static: Optional[DataFrame[TabulatedRatingCurveStaticSchema]] = None
    time: Optional[DataFrame[TabulatedRatingCurveTimeSchema]] = None

    def sort(self):
        if self.static is not None:
            self.static.sort_values(
                ["node_id", "level"], ignore_index=True, inplace=True
            )
        if self.time is not None:
            self.time.sort_values(
                ["time", "node_id", "level"], ignore_index=True, inplace=True
            )
