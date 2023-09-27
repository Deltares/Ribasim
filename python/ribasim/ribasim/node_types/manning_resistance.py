from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import ManningResistanceStaticSchema  # type: ignore

__all__ = ("ManningResistance",)


class ManningResistance(TableModel):
    """
    Flow through this connection is estimated by conservation of energy and the
    Manning-Gauckler formula to estimate friction losses.

    Parameters
    ----------
    static : pd.DataFrame
        Table with the constant Manning parameters.
    """

    static: DataFrame[ManningResistanceStaticSchema]
