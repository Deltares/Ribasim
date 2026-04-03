from ribasim.input_base import TableModel
from ribasim.schemas import (
    TabulatedRatingCurveStaticSchema,
    TabulatedRatingCurveTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[TabulatedRatingCurveStaticSchema]):
    pass


class Time(TableModel[TabulatedRatingCurveTimeSchema]):
    pass
