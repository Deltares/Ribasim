from pydantic import BaseModel

from ribasim.input_base import ArrowInputMixin
from ribasim.types import DataFrame


class Bifurcation(BaseModel, ArrowInputMixin):
    _input_type = "Bifurcation"
    dataframe: DataFrame


class BifurcationForcing(BaseModel, ArrowInputMixin):
    _input_type = "Bifurcation / forcing"
    dataframe: DataFrame
