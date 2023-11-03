import textwrap
from abc import ABC, abstractmethod
from contextlib import closing
from contextvars import ContextVar
from pathlib import Path
from sqlite3 import Connection, connect
from typing import Any, Dict, Generic, List, Optional, Set, TypeVar

import geopandas as gpd
import pandas as pd
from pandera.typing import DataFrame
from pydantic import BaseModel as PydanticBaseModel
from pydantic import (
    ConfigDict,
    DirectoryPath,
    Field,
    ValidationInfo,
    field_validator,
    model_serializer,
    model_validator,
)

from ribasim.types import FilePath

__all__ = ("TableModel",)

delimiter = " / "

gpd.options.io_engine = "pyogrio"

context_file_loading: ContextVar[Dict[str, Any]] = ContextVar(
    "file_loading", default={}
)


def esc_id(identifier: str) -> str:
    """Escape SQLite identifiers."""
    return '"' + identifier.replace('"', '""') + '"'


def exists(connection: Connection, name: str) -> bool:
    """Check if a table exists in a SQLite database."""
    with closing(connection.cursor()) as cursor:
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,)
        )
        result = cursor.fetchone()
    return result is not None


TABLES = ["profile", "state", "static", "time", "logic", "condition"]


class BaseModel(PydanticBaseModel):
    """Overrides Pydantic BaseModel to set our own config."""

    model_config = ConfigDict(
        validate_assignment=True,
        validate_default=True,
        revalidate_instances="always",
        use_enum_values=True,
        extra="allow",
    )

    @classmethod
    def fields(cls):
        """Return the names of the fields contained in the Model."""
        return cls.__fields__.keys()


class NodeModel(BaseModel):
    """Base class to handle combining the tables for a single node type."""

    @model_validator(mode="before")
    @classmethod
    def check_node(cls, value: Any, info: ValidationInfo) -> Any:
        if isinstance(value, (Dict,)):
            for key in TABLES:
                layername = cls._layername(key)
                path = value.setdefault(key, layername)
                if path is None:
                    value[key] = path
        return value

    # you can select multiple fields, or use '*' to select all fields
    @field_validator("*")
    @classmethod
    def check_sort_keys(cls, v: Any, info: ValidationInfo) -> Any:
        """Forward check to always set default sort keys."""
        if isinstance(v, TableModel):
            default = cls.model_fields[info.field_name].default
            if default is not None and hasattr(default, "sort_keys"):
                v.sort_keys = default.sort_keys
        return v

    @classmethod
    def get_input_type(cls):
        return cls.__name__

    @classmethod
    def _layername(cls, field: str) -> str:
        return f"{cls.get_input_type()}{delimiter}{field}"

    def add(*args, **kwargs):
        pass

    def tables(self):
        for key in self.fields():
            attr = getattr(self, key)
            if isinstance(attr, TableModel):
                yield attr

    def node_ids(self):
        node_ids: Set[int] = set()
        for table in self.tables():
            node_ids.update(table.node_ids())
        return node_ids

    def _save(self, directory: DirectoryPath):
        for field in self.fields():
            getattr(self, field)._save(directory)


class FileModel(BaseModel, ABC):
    """Base class to represent models with a file representation.

    It therefore always has a `filepath` and if it is given on
    initialization, it will parse that file. The filepath can be
    relative, in which case the paths are expected to be resolved
    relative to some root model. If a path is absolute, this path
    will always be used, regardless of a root parent.

    When saving a model, if the current filepath is relative, the
    last resolved absolute path will be used. If the model has just
    been read, the

    This class extends the `validate` option of Pydantic,
    so when when a Path is given to a field with type `FileModel`,
    it doesn't error, but actually initializes the `FileModel`.

    Attributes
    ----------
        filepath (Optional[Path]):
            The path of this FileModel. This path can be either absolute or relative.
            If it is a relative path, it is assumed to be resolved from some root
            model.
    """

    filepath: Optional[Path] = Field(default=None, exclude=True)

    @model_validator(mode="before")
    @classmethod
    def check_filepath(cls, value: Any, info: ValidationInfo) -> Any:
        # Enable initialization with a Path.
        if isinstance(value, (Dict,)):
            # Pydantic Model init requires a dict
            filepath = value.get("filepath", None)
            if filepath is None:
                return value
        elif isinstance(value, (Path, str)):
            # Pydantic Model init requires a dict
            filepath = value
        else:
            return value

        data = cls._load(filepath)
        data["filepath"] = filepath
        # TODO Validation always runs, not just on init.
        # Make sure an existing model survives, without
        # its DataFrame being overwritten.
        return data

    @abstractmethod
    def _save(self) -> None:
        """Save this instance to disk.

        This method needs to be implemented by any class deriving from
        FileModel, and is used in both the _save_instance and _save_tree
        methods.

        Args:
            save_settings (ModelSaveSettings): The model save settings.
        """
        raise NotImplementedError()

    @classmethod
    @abstractmethod
    def _load(cls, filepath: Path) -> Dict[str, Any]:
        """Load the data at filepath and returns it as a dictionary.

        If a derived FileModel does not load data from disk, this should
        return an empty dictionary.

        Args
        ----
            filepath (Path): Path to the data to load.

        Returns
        -------
            Dict: The data stored at filepath
        """
        raise NotImplementedError()


TableT = TypeVar("TableT")


class TableModel(FileModel, Generic[TableT]):
    df: DataFrame[TableT] | None = None
    sort_keys: List[str] = Field(default=["node_id"], exclude=True, repr=False)

    model_config = ConfigDict(validate_assignment=True)

    @model_serializer
    def set_model(self) -> str:
        return self.filepath if self.df is not None else None

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

    def node_ids(self) -> Set[int]:
        node_ids: Set[int] = set()
        if self.df is not None and "node_id" in self.df.columns:
            node_ids.update(self.df["node_id"])

        return node_ids

    @classmethod
    def _load(cls, filepath: str | Path) -> Dict[str, Any]:
        db = context_file_loading.get().get("database")
        if filepath is not None and Path(filepath).exists():
            df = cls._from_arrow(filepath)
        elif filepath is not None and db is not None:
            df = cls._from_db(db, str(filepath))
        else:
            df = None

        return {"df": df}

    def _save(self, directory: DirectoryPath):
        # TODO directory could be used to save an arrow file
        db_path = context_file_loading.get().get("database")
        if self.df is not None and db_path is not None:
            self.sort()
            self._write_table(db_path)

    def _write_table(self, temp_path: Path) -> None:
        """
        Write the contents of the input to a database.

        Parameters
        ----------
        connection : Connection
            SQLite connection to the database.
        """
        table = str(self.filepath)
        with closing(connect(temp_path)) as connection:
            self.df.to_sql(table, connection, index=False, if_exists="replace")

            # Set geopackage attribute table
            with closing(connection.cursor()) as cursor:
                sql = "INSERT INTO gpkg_contents (table_name, data_type, identifier) VALUES (?, ?, ?)"
                cursor.execute(sql, (table, "attributes", table))
            connection.commit()

    @classmethod
    def _from_db(cls, path: FilePath, table: str) -> DataFrame | None:
        with connect(path) as connection:
            if exists(connection, table):
                query = f"select * from {esc_id(table)}"
                df = pd.read_sql_query(query, connection, parse_dates=["time"])
            else:
                df = None

            return df

    @classmethod
    def _from_arrow(cls, path: FilePath) -> DataFrame:
        return pd.read_feather(path)

    def sort(self):
        """Sort all input tables as required.

        Tables are sorted by "node_id", unless otherwise specified.
        Sorting is done automatically before writing the table.
        """
        if self.df is not None:
            self.df.sort_values(self.sort_keys, ignore_index=True, inplace=True)

    def schema(self):
        """Retrieve Pandera Schema."""
        optionalfieldtype = self.model_fields["df"].annotation
        fieldtype = optionalfieldtype.__args__[0]  # First of Union
        T = fieldtype.__args__[0]
        return T

    def record(self):
        """Retrieve Pydantic Record used in Pandera Schema."""
        T = self.schema()
        return T.Config.dtype.type

    def columns(self):
        """Retrieve column names."""
        return list(self.record().model_fields.keys())


class SpatialTableModel(TableModel[TableT], Generic[TableT]):
    @classmethod
    def _from_db(cls, path: FilePath, table: str) -> DataFrame | None:
        with connect(path) as connection:
            if exists(connection, table):
                df = gpd.read_file(path, layer=table, fid_as_index=True)
            else:
                df = None

            return df

    def _write_table(self, path: FilePath) -> None:
        """
        Write the contents of the input to a database.

        Parameters
        ----------
        path : FilePath
        """

        gdf = gpd.GeoDataFrame(data=self.df)
        gdf = gdf.set_geometry("geometry")

        gdf.to_file(path, layer=str(self.filepath), driver="GPKG")

    def sort(self):
        self.df.sort_index(inplace=True)
