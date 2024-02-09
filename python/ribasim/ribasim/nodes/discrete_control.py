from pandera.typing import DataFrame

from ribasim.schemas import DiscreteControlConditionSchema, DiscreteControlLogicSchema


class Condition(DataFrame[DiscreteControlConditionSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class Logic(DataFrame[DiscreteControlLogicSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
