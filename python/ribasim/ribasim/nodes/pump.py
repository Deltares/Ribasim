from pandera.typing import DataFrame

from ribasim.schemas import (
    PumpStaticSchema,
)


class Static(DataFrame[PumpStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
