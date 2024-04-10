from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    DiscreteControlCompoundvariableSchema,
    DiscreteControlConditionSchema,
    DiscreteControlLogicSchema,
)

__all__ = ["Condition", "Logic", "Compoundvariable"]


class Compoundvariable(TableModel[DiscreteControlCompoundvariableSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Condition(TableModel[DiscreteControlConditionSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Logic(TableModel[DiscreteControlLogicSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
