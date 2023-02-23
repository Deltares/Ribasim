from pydantic import BaseModel
import pandas as pd

from ribasim.input_base import ArrowInputMixin
from ribasim.types import DataFrame


class BasinLsw(BaseModel, ArrowInputMixin):
    _input_type = "forcing_LSW"
    dataframe: DataFrame
