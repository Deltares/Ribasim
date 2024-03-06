from pandera.typing import DataFrame

from ribasim.schemas import (
    OutletStaticSchema,
)

__all__ = ["Static"]


class Static(DataFrame[OutletStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
