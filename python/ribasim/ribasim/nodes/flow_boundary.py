from pandera.typing import DataFrame

from ribasim.schemas import (
    FlowBoundaryStaticSchema,
    FlowBoundaryTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(DataFrame[FlowBoundaryStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class Time(DataFrame[FlowBoundaryTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
