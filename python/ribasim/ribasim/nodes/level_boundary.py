from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    LevelBoundaryStaticSchema,
    LevelBoundaryTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[LevelBoundaryStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[LevelBoundaryTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
