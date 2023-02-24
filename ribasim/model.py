import datetime
from pathlib import Path
from typing import Optional

import tomli
import tomli_w
from pydantic import BaseModel

from ribasim import (
    Basin,
    Edge,
    FractionalFlow,
    LevelControl,
    LinearLevelConnection,
    Node,
    TabulatedRatingCurve,
)

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
        return cls.__fields__.keys()

    def _write_toml(self, directory: Path):
        content = {
            "starttime": self.starttime,
            "endtime": self.endtime,
            "geopackage": f"{self.modelname}.gpkg",
        }
        with open(directory / f"{self.modelname}.toml", "w") as f:
            tomli_w.dump(content, f)
        return

    def _write_tables(self, directory: Path) -> None:
        """
        Write the input to GeoPackage and Arrow tables.
        """
        for input_table in self.dict().values():
            input_table.write(directory, self.modelname)
        return

    def write(self, directory) -> None:
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        self._write_toml(directory)
        self._write_tables(directory)
        return

    @staticmethod
    def from_toml(path):
        with open(path, "rb") as f:
            config = tomli.load(f)

        kwargs = {}
        for cls, kwarg_name in _NODES.items():
            kwargs[kwarg_name] = cls.from_config(config)

        kwargs["start_time"] = config["start_time"]
        kwargs["end_time"] = config["end_time"]

        return Model(**kwargs)
