from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    TabulatedRatingCurveStaticSchema,
    TabulatedRatingCurveTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[TabulatedRatingCurveStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[TabulatedRatingCurveTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
