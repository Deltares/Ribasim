from pydantic import BaseModel

from ribasim.input_base import ArrowInputMixin
from ribasim.types import DataFrame


class Bifurcation(BaseModel, ArrowInputMixin):
    _input_type = "static_Bifurcation"
    dataframe: DataFrame
