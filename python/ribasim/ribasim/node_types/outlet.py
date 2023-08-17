import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("Outlet",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.OutletStatic)


class Outlet(TableModel):
    """
    Conducts water from a source node to a destination node.
    The set flow rate will be used unless the intake storage is less than 10m3,
    in which case the flow rate will be linearly reduced to 0 m3/s.
    Negative flow rates are not supported.
    Note that the intake must always be a Basin.

    Parameters
    ----------
    static : pd.DataFrame
        Table with constant flow rates.
    """

    static: DataFrame[StaticSchema]
