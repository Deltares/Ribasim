import re
from abc import ABC, abstractmethod
from contextlib import closing
from contextvars import ContextVar
from pathlib import Path
from sqlite3 import Connection, connect
from typing import (
    Any,
    Dict,
    Generator,
    Generic,
    List,
    Optional,
    Set,
    Tuple,
    TypeVar,
)

import geopandas as gpd
import pandas as pd
import pandera as pa
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

TableT = TypeVar("TableT", bound=pa.DataFrameModel)


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
        use_enum_values=True,
        extra="allow",
    )

    @classmethod
    def fields(cls) -> List[str]:
        """Return the names of the fields contained in the Model."""
        return list(cls.model_fields.keys())


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
        # data["filepath"] = filepath
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


class TableModel(FileModel, Generic[TableT]):
    df: DataFrame[TableT] | None = Field(default=None, exclude=True, repr=False)
    sort_keys: List[str] = Field(default=["node_id"], exclude=True, repr=False)

    @model_serializer
    def set_model(self) -> str | None:
        return self.tablename() if self.filepath is None else self.filepath

    def tablename(self) -> str:
        """Retrieve tablename based on attached Schema.

        NodeSchema -> Schema
        TabularRatingCurveStaticSchema -> TabularRatingCurve / Static
        """
        names: List[str] = re.sub("([A-Z]+)", r" \1", str(self.schema())).split()
        if len(names) > 2:
            return f"{''.join(names[:-2])}{delimiter}{names[-2].lower()}"
        else:
            return names[0]

    # def __repr__(self) -> str:
    #     content = [f"<ribasim.{type(self).__name__}>"]
    #     for field in self.fields():
    #         attr = getattr(self, field)
    #         if isinstance(attr, pd.DataFrame):
    #             colnames = "(" + ", ".join(attr.columns) + ")"
    #             if len(colnames) > 50:
    #                 colnames = textwrap.indent(
    #                     textwrap.fill(colnames, width=50), prefix="    "
    #                 )
    #                 entry = f"{field}: DataFrame(rows={len(attr)})\n{colnames}"
    #             else:
    #                 entry = f"{field}: DataFrame(rows={len(attr)}) {colnames}"
    #         else:
    #             entry = f"{field}: {attr}"
    #         content.append(textwrap.indent(entry, prefix="   "))
    #     return "\n".join(content)

    @model_validator(mode="before")
    @classmethod
    def check_dataframe(cls, value: Any, info: ValidationInfo) -> Any:
        # Enable initialization with a DataFrame.
        if isinstance(value, (pd.DataFrame, gpd.GeoDataFrame)):
            value = {"df": value}

        return value

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
            # TODO Store filepath?
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
        table = self.tablename()
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
    def _from_db(cls, path: FilePath, table: str):
        with connect(path) as connection:
            if exists(connection, table):
                df = gpd.read_file(path, layer=table, fid_as_index=True)
            else:
                print(f"Can't read from {path}:{table}")
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

        gdf.to_file(path, layer=self.tablename(), driver="GPKG")

    def sort(self):
        self.df.sort_index(inplace=True)


class NodeModel(BaseModel):
    """Base class to handle combining the tables for a single node type."""

    fset: Set[str] = Field(default=set[str](), exclude=True, repr=False)

    def __init__(self, *args, **kwargs):
        # Remove the defaults as provided by `check_node`
        # This prevents the fields from being defined in
        # the .toml when a model is written.
        super().__init__(*args, **kwargs)

        self.model_fields_set.clear()
        for field in self.fset:
            self.model_fields_set.add(field)

    @model_validator(mode="before")
    @classmethod
    def check_node(cls, value: Any, info: ValidationInfo) -> Any:
        """Set tablename as default input when nothing is provided."""
        if isinstance(value, (Dict,)):
            fields = set[str]()
            for key in cls.fields():
                layername = cls._layername(key)
                path = value.get(key, None)
                if path is None:
                    value[key] = layername

                # fields.add(key)
            value["fset"] = fields
        return value

    # you can select multiple fields, or use '*' to select all fields
    @field_validator("*")
    @classmethod
    def check_sort_keys(cls, v: Any, info: ValidationInfo) -> Any:
        """Forward check to always set default sort keys."""
        if isinstance(v, TableModel):
            default = cls.model_fields[info.field_name].default
            if (
                default is not None
                and hasattr(default, "sort_keys")
                and hasattr(v, "sort_keys")
            ):
                v.sort_keys = default.sort_keys
        return v

    @classmethod
    def fields(cls) -> List[str]:
        """Return the names of the fields contained in the Model."""
        # Prevent the `fset` attribute from being used in `_save`.
        fields = set(cls.model_fields.keys())
        fields.discard("fset")
        return list(fields)

    @classmethod
    def get_input_type(cls):
        return cls.__name__

    @classmethod
    def _layername(cls, field: str) -> str:
        return f"{cls.get_input_type()}{delimiter}{field}"

    def add(*args, **kwargs):
        # TODO This is the new API
        pass

    def tables(self) -> Generator[TableModel[Any], Any, None]:
        for key in self.fields():
            attr = getattr(self, key)
            if isinstance(attr, TableModel):
                yield attr

    def node_ids(self):
        node_ids: Set[int] = set()
        for table in self.tables():
            node_ids.update(table.node_ids())
        return node_ids

    def node_ids_and_types(self) -> Tuple[List[int], List[str]]:
        ids = self.node_ids()
        return list(ids), len(ids) * [self.get_input_type()]

    def _save(self, directory: DirectoryPath):
        for field in self.fields():
            if field not in self.fset:
                getattr(self, field)._save(directory)
