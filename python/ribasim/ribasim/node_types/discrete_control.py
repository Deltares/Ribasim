import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("DiscreteControl",)


class ConditionSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.DiscreteControlCondition)


class LogicSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.DiscreteControlLogic)


class DiscreteControl(TableModel):
    """
    Defines the control logic.

    Parameters
    ----------
    condition : pandas.DataFrame
        Table with the information of control conditions.
    logic : pandas.Dataframe
        Table with the information of truth state to control state mapping.
    """

    condition: DataFrame[ConditionSchema]
    logic: DataFrame[LogicSchema]
