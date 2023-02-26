import datetime
from pathlib import Path
from typing import Optional

import tomli
import tomli_w
from pydantic import BaseModel

from ribasim.basin import Basin
from ribasim.edge import Edge
from ribasim.fractional_flow import FractionalFlow

# Do not import from ribasim namespace: will create import errors.
# E.g. not: from ribasim import Basin
from ribasim.input_base import InputMixin
from ribasim.level_control import LevelControl
from ribasim.linear_level_connection import LinearLevelConnection
from ribasim.node import Node
from ribasim.tabulated_rating_curve import TabulatedRatingCurve
from ribasim.types import FilePath

_NODES = (
    (Node, "node"),
    (Edge, "edge"),
    (Basin, "basin"),
    (FractionalFlow, "fractional_flow"),
    (LevelControl, "level_control"),
    (LinearLevelConnection, "linear_level_connection"),
    (TabulatedRatingCurve, "tabulated_rating_curve"),
)


class Model(BaseModel):
    modelname: str
    node: Node
    edge: Edge
    basin: Basin
    fractional_flow: Optional[FractionalFlow]
    level_control: Optional[LevelControl]
    linear_level_connection: Optional[LinearLevelConnection]
    tabulated_rating_curve: Optional[TabulatedRatingCurve]
    starttime: datetime.datetime
    endtime: datetime.datetime

    @classmethod
    def fields(cls):
        """Returns the names of the fields contained in the Model."""
        return cls.__fields__.keys()

    def __repr__(self) -> str:
        first = []
        second = []
        for field in self.fields():
            attr = getattr(self, field)
            if isinstance(attr, InputMixin):
                second.append(f"{field}: {repr(attr)}")
            else:
                first.append(f"{field}={repr(attr)}")
        content = ["<ribasim.Model>"] + first + second
        return "\n".join(content)

    def _repr_html(self):
        # Default to standard repr for now
        return self.__repr__()

    def _write_toml(self, directory: FilePath):
        content = {
            "starttime": self.starttime,
            "endtime": self.endtime,
            "geopackage": f"{self.modelname}.gpkg",
        }
        with open(directory / f"{self.modelname}.toml", "wb") as f:
            tomli_w.dump(content, f)
        return

    def _write_tables(self, directory: FilePath) -> None:
        """
        Write the input to GeoPackage and Arrow tables.
        """
        for name in self.fields():
            input_entry = getattr(self, name)
            if isinstance(input_entry, InputMixin):
                input_entry.write(directory, self.modelname)
        return

    def write(self, directory: FilePath) -> None:
        """
        Write the contents of the model to a GeoPackage and a TOML
        configuration file.

        If ``directory`` does not exist, it is created before writing.
        The GeoPackage and TOML file will be called ``{modelname}.gpkg`` and
        ``{modelname}.toml`` respectively.

        Parameters
        ----------
        directory: FilePath
        """
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        self._write_toml(directory)
        self._write_tables(directory)
        return

    @staticmethod
    def from_toml(path: FilePath) -> "Model":
        """
        Initialize a model from the TOML configuration file.

        Parameters
        ----------
        path: FilePath
            Path to the configuration TOML file.

        Returns
        -------
        model: Model
        """
        path = Path(path)
        with open(path, "rb") as f:
            config = tomli.load(f)

        kwargs = {"modelname": path.stem}
        for cls, kwarg_name in _NODES:
            kwargs[kwarg_name] = cls.from_config(config)

        kwargs["starttime"] = config["starttime"]
        kwargs["endtime"] = config["endtime"]

        return Model(**kwargs)
