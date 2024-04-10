from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    DiscreteControlCompoundVariableSchema,
    DiscreteControlConditionSchema,
    DiscreteControlLogicSchema,
)

__all__ = ["Condition", "Logic", "CompoundVariable"]


class CompoundVariable(TableModel[DiscreteControlCompoundVariableSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Condition(TableModel[DiscreteControlConditionSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Logic(TableModel[DiscreteControlLogicSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
