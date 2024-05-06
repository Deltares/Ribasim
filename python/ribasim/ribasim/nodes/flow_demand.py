from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    FlowDemandStaticSchema,
    FlowDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[FlowDemandStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[FlowDemandTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
