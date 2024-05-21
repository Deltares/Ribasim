from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    LevelBoundaryConcentrationSchema,
    LevelBoundaryStaticSchema,
    LevelBoundaryTimeSchema,
)

__all__ = ["Static", "Time", "Concentration"]


class Static(TableModel[LevelBoundaryStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[LevelBoundaryTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Concentration(TableModel[LevelBoundaryConcentrationSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
