import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("ManningResistance",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.ManningResistanceStatic)


class ManningResistance(TableModel):
    """
    Flow through this connection is estimated by conservation of energy and the
    Manning-Gauckler formula to estimate friction losses.

    Parameters
    ----------
    static : pd.DataFrame
        Table with the constant Manning parameters.
    """

    static: DataFrame[StaticSchema]
