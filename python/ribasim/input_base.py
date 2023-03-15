import abc
import textwrap
from pathlib import Path
from typing import Any, Dict, Type, TypeVar

import fiona
import geopandas as gpd
import pandas as pd

from ribasim.types import FilePath

T = TypeVar("T")

__all__ = ("InputMixin",)


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

    def write(self, directory: FilePath, modelname: str) -> None:
        """
        Write the contents of the input to a GeoPackage.

        The Geopackage will be written in ``directory`` and will be be named
        ``{modelname}.gpkg``.

        Parameters
        ----------
        directory: FilePath
        modelname: str
        """
        directory = Path(directory)
        for field in self.fields():
            dataframe = getattr(self, field)
            if dataframe is None:
                continue
            name = self._input_type
            if field != "static":
                name = f"{name} / {field}"

            gdf = gpd.GeoDataFrame(data=dataframe)
            if "geometry" in gdf.columns:
                gdf = gdf.set_geometry("geometry")
            else:
                gdf["geometry"] = None
            gdf.to_file(directory / f"{modelname}.gpkg", layer=name)

        return

    @classmethod
    def _kwargs_from_geopackage(cls: Type[T], path: FilePath) -> T:
        kwargs = {}
        layers = fiona.listlayers(path)
        for key in cls.fields():
            df = None
            layername = f"{cls._input_type} / {key}"
            if key == "static" and cls._input_type in layers:
                df = gpd.read_file(
                    path, layer=cls._input_type, engine="pyogrio", fid_as_index=True
                )
            elif layername in layers:
                df = gpd.read_file(
                    path, layer=layername, engine="pyogrio", fid_as_index=True
                )

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
        path: Path
            Path to the GeoPackage

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
        config: Dict[str, Any]

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
