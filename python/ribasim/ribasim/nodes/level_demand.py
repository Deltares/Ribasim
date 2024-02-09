from pandera.typing import DataFrame

from ribasim.schemas import (
    LevelDemandStaticSchema,
    LevelDemandTimeSchema,
)


class Static(DataFrame[LevelDemandStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class Time(DataFrame[LevelDemandTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
