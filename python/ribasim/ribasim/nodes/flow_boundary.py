from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    FlowBoundaryConcentrationSchema,
    FlowBoundaryStaticSchema,
    FlowBoundaryTimeSchema,
)

__all__ = ["Static", "Time", "Concentration"]


class Static(TableModel[FlowBoundaryStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[FlowBoundaryTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Concentration(TableModel[FlowBoundaryConcentrationSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
