from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    ContinuousControlFunctionSchema,
    ContinuousControlVariableSchema,
)

__all__ = ["Variable", "Function"]


class Variable(TableModel[ContinuousControlVariableSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Function(TableModel[ContinuousControlFunctionSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
