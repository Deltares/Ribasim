from ribasim.input_base import TableModel
from ribasim.schemas import (
    DiscreteControlConditionSchema,
    DiscreteControlLogicSchema,
    DiscreteControlVariableSchema,
)

__all__ = ["Condition", "Logic", "Variable"]


class Variable(TableModel[DiscreteControlVariableSchema]):
    pass


class Condition(TableModel[DiscreteControlConditionSchema]):
    pass


class Logic(TableModel[DiscreteControlLogicSchema]):
    pass
