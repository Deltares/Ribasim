import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("PIDControl",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.PidControlStatic)


class PidControl(TableModel):
    """
    Controller based on PID (Proportional, integral, derivative) which
    controls the level of a single basin with a pump.

    Parameters
    ----------
    static: pandas.DataFrame
        Table with data for this node type.

    """

    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True
