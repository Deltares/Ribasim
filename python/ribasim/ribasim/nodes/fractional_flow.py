from pandera.typing import DataFrame

from ribasim.schemas import FractionalFlowStaticSchema


class Static(DataFrame[FractionalFlowStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
