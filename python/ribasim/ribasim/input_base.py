import re
import textwrap
from pathlib import Path
from sqlite3 import Connection, connect
from typing import Any, Dict, Set

import pandas as pd
from pydantic import BaseModel

from ribasim.types import FilePath

__all__ = ("TableModel",)

delimiter = " / "


def esc_id(identifier: str) -> str:
    """Escape SQLite identifiers."""
    return '"' + identifier.replace('"', '""') + '"'


def exists(connection: Connection, name: str) -> bool:
    """Check if a table exists in a SQLite database."""
    cursor = connection.cursor()
    cursor.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,)
    )
    result = cursor.fetchone()
    return result is not None


class TableModel(BaseModel):
    @classmethod
    def get_input_type(cls):
        return cls.__name__

    @classmethod
    def get_toml_key(cls):
        """Get the class name in snake case, e.g. FlowBoundary -> flow_boundary."""

        name_camel_case = cls.__name__

        # Insert underscore before capital letters
        name_snake_case = re.sub(r"(?<!^)(?=[A-Z])", "_", name_camel_case)

        # Convert to lowercase
        name_snake_case = name_snake_case.lower()

        return name_snake_case

    @classmethod
    def fields(cls):
        """Return the input fields."""
        return cls.__fields__.keys()

    def __repr__(self) -> str:
        content = [f"<ribasim.{type(self).__name__}>"]
        for field in self.fields():
            attr = getattr(self, field)
            if isinstance(attr, pd.DataFrame):
                colnames = "(" + ", ".join(attr.columns) + ")"
                if len(colnames) > 50:
                    colnames = textwrap.indent(
                        textwrap.fill(colnames, width=50), prefix="    "
                    )
                    entry = f"{field}: DataFrame(rows={len(attr)})\n{colnames}"
                else:
                    entry = f"{field}: DataFrame(rows={len(attr)}) {colnames}"
            else:
                entry = f"{field}: {attr}"
            content.append(textwrap.indent(entry, prefix="   "))
        return "\n".join(content)

    def get_node_IDs(self) -> set:
        node_IDs: Set[int] = set()
        for name in self.fields():
            attr = getattr(self, name)
            if isinstance(attr, pd.DataFrame):
                if "node_id" in attr:
                    node_IDs.update(attr["node_id"])

        return node_IDs

    @classmethod
    def _layername(cls, field) -> str:
        return f"{cls.get_input_type()}{delimiter}{field}"

    def write(self, directory: FilePath, modelname: str) -> None:
        """
        Write the contents of the input to a GeoPackage.

        The Geopackage will be written in ``directory`` and will be be named
        ``{modelname}.gpkg``.

        Parameters
        ----------
        directory : FilePath
            Path to the directory where to write the files.
        modelname : str
            Name of the model, used as a file name.
        """
        self.sort()
        directory = Path(directory)
        sql = "INSERT INTO gpkg_contents (table_name, data_type, identifier) VALUES (?, ?, ?)"
        for field in self.fields():
            dataframe = getattr(self, field)
            if dataframe is None:
                continue
            name = self._layername(field)

            with connect(directory / f"{modelname}.gpkg") as connection:
                dataframe.to_sql(name, connection, index=False, if_exists="replace")
                connection.execute(sql, (name, "attributes", name))

        return

    @classmethod
    def _kwargs_from_geopackage(cls, path: FilePath) -> Dict:
        kwargs = {}
        with connect(path) as connection:
            for key in cls.fields():
                layername = cls._layername(key)

                if exists(connection, layername):
                    query = f"select * from {esc_id(layername)}"
                    df = pd.read_sql_query(query, connection, parse_dates=["time"])
                else:
                    df = None

                kwargs[key] = df

        return kwargs

    @classmethod
    def _kwargs_from_toml(cls, config: Dict[str, Any]) -> Dict[str, pd.DataFrame]:
        return {key: pd.read_feather(path) for key, path in config.items()}

    @classmethod
    def from_geopackage(cls, path: FilePath):
        """
        Initialize input from a GeoPackage.

        The GeoPackage tables are searched for the relevant table names.

        Parameters
        ----------
        path : Path
            Path to the GeoPackage.

        Returns
        -------
        ribasim_input
        """
        kwargs = cls._kwargs_from_geopackage(path)
        return cls(**kwargs)

    @classmethod
    def from_config(cls, config: Dict[str, Any]):
        """
        Initialize input from a TOML configuration file.

        The GeoPackage tables are searched for the relevant table names. Arrow
        tables will also be read if specified. If a table is present in both
        the GeoPackage and as an Arrow table, the data of the Arrow table is
        used.

        Parameters
        ----------
        config : Dict[str, Any]

        Returns
        -------
        ribasim_input
        """
        geopackage = config["geopackage"]
        kwargs = cls._kwargs_from_geopackage(geopackage)
        input_content = config.get(cls.get_input_type(), None)
        if input_content:
            kwargs.update(**cls._kwargs_from_toml(config))

        if all(v is None for v in kwargs.values()):
            return None
        else:
            return cls(**kwargs)

    @classmethod
    def hasfid(cls):
        return False

    def sort(self):
        """
        Sort all input tables as required.
        Tables are sorted by "node_id", unless otherwise specified.
        Sorting is done automatically before writing the table.
        """
        for field in self.fields():
            dataframe = getattr(self, field)
            if dataframe is None:
                continue
            else:
                dataframe = dataframe.sort_values("node_id", ignore_index=True)
        return
