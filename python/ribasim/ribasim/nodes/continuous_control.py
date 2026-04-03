from ribasim.input_base import TableModel
from ribasim.schemas import (
    ContinuousControlFunctionSchema,
    ContinuousControlVariableSchema,
)

__all__ = ["Function", "Variable"]


class Variable(TableModel[ContinuousControlVariableSchema]):
    pass


class Function(TableModel[ContinuousControlFunctionSchema]):
    pass
