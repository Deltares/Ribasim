from pandera.typing import DataFrame

from ribasim.schemas import (
    OutletStaticSchema,
)


class Static(DataFrame[OutletStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
