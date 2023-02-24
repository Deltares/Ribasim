from typing import Optional
from pathlib import Path

from pydantic import BaseModel
import tomli_w

from ribasim import (
    Node,
    Edge,
    Bifurcation,
    BasinLookup,
    BasinState,
    OutflowTable,
)


class Model(BaseModel):
    node: Node
    edge: Edge
    basin_state: Optional[BasinState] = None
    basin_lookup: Optional[BasinLookup] = None
    bifurcation: Optional[Bifurcation] = None
    outflow_table: Optional[OutflowTable] = None

    def __iter__(self):
        return iter(self.__root__)

    def items(self):
        return self.__root__.items()

    def values(self):
        return self.__root__.values()

    def _write_toml(self, directory: Path, modelname: str):
        content = {}
        with open(directory / f"{modelname}.toml", "w") as f:
            tomli_w.dump(content, f)
        return

    def _write_tables(self, directory: Path, modelname: str) -> None:
        """
        Write the input to GeoPackage and Arrow tables.
        """
        for input_table in self.values():
            input_table.write(directory, modelname)
        return

    def write(self, directory, modelname: str) -> None:
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)

        self._write_toml(directory, modelname)
        self._write_tables(directory, modelname)
        return
