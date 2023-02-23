from pathlib import Path
import abc


class InputMixin(abc.ABC):
    def _write_geopackage(self, directory: Path, modelname: str) -> None:
        self.dataframe.to_file(
            directory / f"{modelname}.gpkg", layer=f"ribasim_{self.input_type}"
        )
        return

    def write(self, directory, modelname, to_arrow: bool = False) -> None:
        if to_arrow:
            self._write_arrow(directory)
        else:
            self._write_geopackage(directory, modelname)
        return


class ArrowInputMixin(InputMixin, abc.ABC):
    def _write_arrow(self, directory: Path) -> None:
        path = directory / f"{self.input_type}.arrow"
        self.dataframe.write_feather(path)
        return
