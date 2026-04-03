from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import (
    TabulatedRatingCurveStaticSchema,
    TabulatedRatingCurveTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[TabulatedRatingCurveStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[TabulatedRatingCurveTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
