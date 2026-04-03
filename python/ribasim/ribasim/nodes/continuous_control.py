from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import (
    ContinuousControlFunctionSchema,
    ContinuousControlVariableSchema,
)

__all__ = ["Function", "Variable"]


class Variable(TableModel[ContinuousControlVariableSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Function(TableModel[ContinuousControlFunctionSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
