from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    LevelDemandStaticSchema,
    LevelDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[LevelDemandStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[LevelDemandTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
