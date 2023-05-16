import abc
import textwrap
from pathlib import Path
from sqlite3 import Connection, connect
from typing import Any, Dict, Type, TypeVar

import pandas as pd

from ribasim.types import FilePath

T = TypeVar("T")

__all__ = ("InputMixin",)

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


class InputMixin(abc.ABC):
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

    def _write_geopackage(self, directory: FilePath, modelname: str) -> None:
        self.dataframe.to_file(
            directory / f"{modelname}.gpkg", layer=f"{self.input_type}"
        )
        return

    def _write_arrow(self, directory: FilePath) -> None:
        path = directory / f"{self._input_type}.arrow"
        self.dataframe.write_feather(path)
        return

    @classmethod
    def _layername(cls, field) -> str:
        return f"{cls._input_type}{delimiter}{field}"

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
        for field in self.fields():
            dataframe = getattr(self, field)
            if dataframe is None:
                continue
            name = self._layername(field)

            with connect(directory / f"{modelname}.gpkg") as connection:
                dataframe.to_sql(name, connection, if_exists="replace")

        return

    @classmethod
    def _kwargs_from_geopackage(cls: Type[T], path: FilePath) -> Dict:
        kwargs = {}
        with connect(path) as connection:
            for key in cls.fields():
                layername = cls._layername(key)

                if exists(connection, layername):
                    query = f"select * from {esc_id(layername)}"
                    df = pd.read_sql_query(
                        query, connection, index_col="index", parse_dates=["time"]
                    )
                else:
                    df = None

                kwargs[key] = df

        return kwargs

    @classmethod
    def _kwargs_from_toml(
        cls: Type[T], config: Dict[str, Any]
    ) -> Dict[str, pd.DataFrame]:
        return {key: pd.read_feather(path) for key, path in config.items()}

    @classmethod
    def from_geopackage(cls: Type[T], path: FilePath) -> T:
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
    def from_config(cls: Type[T], config: Dict[str, Any]) -> T:
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
        input_content = config.get(cls._input_type, None)
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
