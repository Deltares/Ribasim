from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    UserDemandStaticSchema,
    UserDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[UserDemandStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[UserDemandTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
