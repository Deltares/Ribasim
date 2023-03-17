import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("Pump",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)
    flow_rate: Series[float]


class Pump(InputMixin, BaseModel):
    """
    Pump water from a source node to a destination node.
    The set flow rate will be pumped unless the intake storage is less than 10m3,
    in which case the flow rate will be linearly reduced to 0 m3/s.
    A negative flow rate means pumping against the edge direction.
    Note that the intake must always be a Basin.

    Parameters
    ----------
    static: pd.DataFrame

        With columns:

        * node_id
        * flow_rate

    """

    _input_type = "Pump"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())
