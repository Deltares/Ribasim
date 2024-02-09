from pandera.typing import DataFrame

from ribasim.schemas import (
    BasinProfileSchema,
    BasinStateSchema,
    BasinStaticSchema,
    BasinSubgridSchema,
    BasinTimeSchema,
)


class Static(DataFrame[BasinStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class Time(DataFrame[BasinTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class State(DataFrame[BasinStateSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class Profile(DataFrame[BasinProfileSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))


class Profile(DataFrame[BasinSubgridSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
