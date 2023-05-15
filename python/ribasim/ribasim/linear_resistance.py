import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame
from pydantic import BaseModel

from ribasim import models
from ribasim.input_base import InputMixin

__all__ = ("LinearResistance",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.LinearResistanceStatic)


class LinearResistance(InputMixin, BaseModel):
    """
    Flow through this connection linearly depends on the level difference
    between the two connected basins.

    Parameters
    ----------
    static: pd.DataFrame

        With columns:

        * node_id
        * conductance

    """

    _input_type = "LinearResistance"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True
