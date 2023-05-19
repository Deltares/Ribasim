import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("FlowBoundary",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    flow_rate: Series[float]


class FlowBoundary(InputMixin, BaseModel):
    """
    Sets a precribed flow like a one-sided pump.

    Parameters
    ----------
    static : pandas.DataFrame
        Table with the constant flows.
    """

    _input_type = "FlowBoundary"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True
