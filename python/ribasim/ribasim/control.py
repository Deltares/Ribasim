import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("Control",)


class ConditionSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.ControlCondition)


class Control(TableModel):
    """
    Defines the control logic.

    Parameters
    ----------
    condition : pandas.DataFrame
        Table with the information of control conditions.
    """

    condition: DataFrame[ConditionSchema]

    class Config:
        validate_assignment = True
