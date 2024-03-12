from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    FlowBoundaryStaticSchema,
    FlowBoundaryTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[FlowBoundaryStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[FlowBoundaryTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
