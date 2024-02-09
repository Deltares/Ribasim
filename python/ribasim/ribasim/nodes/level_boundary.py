from pandera.typing import DataFrame

from ribasim.schemas import (
    LevelBoundaryStaticSchema,
    LevelBoundaryTimeSchema,
)


class Static(DataFrame[LevelBoundaryStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class Time(DataFrame[LevelBoundaryTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
