from typing import Any

import matplotlib.pyplot as plt
import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pandera.typing.geopandas import GeoSeries
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("Edge",)


class StaticSchema(pa.SchemaModel):
    from_node_id: Series[int] = pa.Field(coerce=True)
    to_node_id: Series[int] = pa.Field(coerce=True)
    geometry: GeoSeries


class Edge(InputMixin, BaseModel):
    """
    Defines the connections between nodes.

    Parameters
    ----------
    static: pandas.DataFrame

        With columns:

        * from_node_id
        * to_node_id
        * geometry

    """

    _input_type = "Edge"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())

    def plot(self, **kwargs) -> Any:
        ax = kwargs.get("ax", None)
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")
            kwargs["ax"] = ax
        self.static.plot(**kwargs)
        return ax
