from pydantic import BaseModel
import pandas as pd

from ribasim.input_base import InputMixin
from ribasim.types import DataFrame


class Node(BaseModel, InputMixin):
    _input_type = "node"
    dataframe: DataFrame
