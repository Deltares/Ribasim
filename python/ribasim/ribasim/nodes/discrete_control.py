from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import (
    DiscreteControlConditionSchema,
    DiscreteControlLogicSchema,
    DiscreteControlVariableSchema,
)

__all__ = ["Condition", "Logic", "Variable"]


class Variable(TableModel[DiscreteControlVariableSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Condition(TableModel[DiscreteControlConditionSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Logic(TableModel[DiscreteControlLogicSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
