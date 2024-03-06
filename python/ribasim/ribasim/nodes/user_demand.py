from pandera.typing import DataFrame

from ribasim.schemas import (
    UserDemandStaticSchema,
    UserDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(DataFrame[UserDemandStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class Time(DataFrame[UserDemandTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
