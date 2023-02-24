import abc
from pathlib import Path
from typing import Dict, Tuple

import geopandas as gpd
import pandas as pd


class InputMixin(abc.ABC):
    @classmethod
    def fields(cls):
        return cls.__fields__.keys()

    def values(self):
        return self._dict().values()

    def _write_geopackage(self, directory: Path, modelname: str) -> None:
        self.dataframe.to_file(
            directory / f"{modelname}.gpkg", layer=f"{self.input_type}"
        )
        return

    def _write_arrow(self, directory: Path) -> None:
        path = directory / f"{self._input_type}.arrow"
        self.dataframe.write_feather(path)
        return

    def write(self, directory, modelname):
        directory = Path(directory)
        for key, dataframe in self.dict().values():
            name = self._input_type
            if key != "static":
                name = f"{name} / {key}"
            dataframe.to_file(directory / f"{modelname}.gpkg", layer=name)
        return

    @classmethod
    def _kwargs_from_geopackage(cls, path):
        kwargs = {}
        for key in cls.keys():
            if key == "static":
                df = gpd.read_file(path, layer=cls._input_type)
            else:
                df = gpd.read_file(path, layer=f"{cls._input_type} / {key}")
            kwargs[key] = df
        return kwargs

    @classmethod
    def _kwargs_from_toml(cls, config):
        return {key: pd.read_feather(path) for key, path in config.items()}

    @classmethod
    def from_geopackage(cls, path):
        kwargs = cls._kwargs_from_geopackage(path)
        return cls(**kwargs)

    @classmethod
    def from_config(cls, config):
        geopackage = config["geopackage"]
        kwargs = cls._kwargs_from_geopackage(geopackage)
        input_content = config.get(cls._input_type, None)
        if input_content:
            kwargs.update(**cls._kwargs_from_toml(config))
        return cls(**kwargs)
