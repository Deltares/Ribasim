from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    ContinuousControlLogicSchema,
    ContinuousControlRelationshipSchema,
    ContinuousControlVariableSchema,
)

__all__ = ["Variable", "Relationship", "Logic"]


class Variable(TableModel[ContinuousControlVariableSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Relationship(TableModel[ContinuousControlRelationshipSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Logic(TableModel[ContinuousControlLogicSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
