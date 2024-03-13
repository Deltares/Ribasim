from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import PidControlStaticSchema, PidControlTimeSchema

__all__ = ["Static", "Time"]


class Static(TableModel[PidControlStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[PidControlTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
