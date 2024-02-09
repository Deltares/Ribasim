from pandera.typing import DataFrame

from ribasim.schemas import (
    TabulatedRatingCurveStaticSchema,
    TabulatedRatingCurveTimeSchema,
)


class Static(DataFrame[TabulatedRatingCurveStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class Time(DataFrame[TabulatedRatingCurveTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
