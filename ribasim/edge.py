from pydantic import BaseModel, PrivateAttr
import pandas as pd

from ribasim.input_base import InputMixin
from ribasim.types import DataFrame


class Edge(BaseModel, InputMixin):
    _input_type = "edge"
    dataframe: DataFrame
