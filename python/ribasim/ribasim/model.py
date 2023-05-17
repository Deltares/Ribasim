import datetime
from pathlib import Path
from typing import Any, List, Optional, Type, cast

import matplotlib.pyplot as plt
import tomli
import tomli_w
from pydantic import BaseModel

from ribasim.basin import Basin
from ribasim.edge import Edge
from ribasim.fractional_flow import FractionalFlow

# Do not import from ribasim namespace: will create import errors.
# E.g. not: from ribasim import Basin
from ribasim.input_base import InputMixin
from ribasim.level_boundary import LevelBoundary
from ribasim.level_control import LevelControl
from ribasim.linear_resistance import LinearResistance
from ribasim.manning_resistance import ManningResistance
from ribasim.node import Node
from ribasim.pump import Pump
from ribasim.tabulated_rating_curve import TabulatedRatingCurve
from ribasim.terminal import Terminal
from ribasim.types import FilePath


class Solver(BaseModel):
    algorithm: Optional[str]
    autodiff: Optional[bool]
    saveat: Optional[List[float]]
    dt: Optional[float]
    abstol: Optional[float]
    reltol: Optional[float]
    maxiters: Optional[int]


class Model(BaseModel):
    """
    A full Ribasim model schematisation with all input.

    Ribasim model containing the location of the nodes, the edges between the
    nodes, and the node parametrization.

    Parameters
    ----------
    modelname : str
        Model name, used in TOML and GeoPackage file name.
    node : Node
        The ID, type and geometry of each node.
    edge : Edge
        How the nodes are connected.
    basin : Basin
        The waterbodies.
    fractional_flow : Optional[FractionalFlow]
        Split flows into fractions.
    level_control : Optional[LevelControl]
        Control the water level with a resistance.
    level_boundary : Optional[LevelBoundary]
        Boundary condition specifying the water level.
    linear_resistance: Optional[LinearResistance]
        Linear flow resistance.
    manning_resistance : Optional[ManningResistance]
        Flow resistance based on the Manning formula.
    tabulated_rating_curve : Optional[TabulatedRatingCurve]
        Tabulated rating curve describing flow based on the upstream water level.
    pump : Optional[Pump]
        Prescribed flow rate from one basin to the other.
    terminal : Optional[Terminal]
        Water sink without state or properties.
    starttime : Union[str, datetime.datetime]
        Starting time of the simulation.
    endtime : Union[str, datetime.datetime]
        End time of the simulation.
    solver : Optional[Solver]
        Solver settings.
    """

    modelname: str
    node: Node
    edge: Edge
    basin: Basin
    fractional_flow: Optional[FractionalFlow]
    level_control: Optional[LevelControl]
    level_boundary: Optional[LevelBoundary]
    linear_resistance: Optional[LinearResistance]
    manning_resistance: Optional[ManningResistance]
    tabulated_rating_curve: Optional[TabulatedRatingCurve]
    pump: Optional[Pump]
    terminal: Optional[Terminal]
    starttime: datetime.datetime
    endtime: datetime.datetime
    solver: Optional[Solver]

    class Config:
        validate_assignment = True

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
        directory = Path(directory)
        content = {
            "starttime": self.starttime,
            "endtime": self.endtime,
            "geopackage": f"{self.modelname}.gpkg",
        }
        if self.solver is not None:
            section = {k: v for k, v in self.solver.dict().items() if v is not None}
            content["solver"] = section

        with open(directory / f"{self.modelname}.toml", "wb") as f:
            tomli_w.dump(content, f)
        return

    def _write_tables(self, directory: FilePath) -> None:
        """
        Write the input to GeoPackage and Arrow tables.
        """
        # avoid adding tables to existing model
        directory = Path(directory)
        gpkg_path = directory / f"{self.modelname}.gpkg"
        gpkg_path.unlink(missing_ok=True)

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
        path : FilePath
            Path to the configuration TOML file.

        Returns
        -------
        model : Model
        """
        NODES = (
            (Node, "node"),
            (Edge, "edge"),
            (Basin, "basin"),
            (FractionalFlow, "fractional_flow"),
            (LevelControl, "level_control"),
            (LevelBoundary, "level_boundary"),
            (LinearResistance, "linear_resistance"),
            (ManningResistance, "manning_resistance"),
            (TabulatedRatingCurve, "tabulated_rating_curve"),
            (Pump, "pump"),
        )

        path = Path(path)
        with open(path, "rb") as f:
            config = tomli.load(f)

        kwargs: dict[str, Any] = {"modelname": path.stem}
        config["geopackage"] = path.parent / config["geopackage"]
        for cls, kwarg_name in NODES:
            cls_casted = cast(Type[InputMixin], cls)
            kwargs[kwarg_name] = cls_casted.from_config(config)

        kwargs["starttime"] = config["starttime"]
        kwargs["endtime"] = config["endtime"]
        kwargs["solver"] = config.get("solver")

        return Model(**kwargs)

    def plot(self, ax=None, legend=False) -> Any:
        """
        Plot the nodes and edges of the model.

        Parameters
        ----------
        ax : matplotlib.pyplot.Artist, optional
            Axes on which to draw the plot.

        legend: bool, optional
            Whether a node legend will be shown

        Returns
        -------
        ax : matplotlib.pyplot.Artist
        """
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")
        self.edge.plot(ax=ax, zorder=2)
        self.node.plot(ax=ax, zorder=3, legend=legend)
        return ax

    def sort(self):
        """
        Sort all input tables as required.
        Tables are sorted by "node_id", unless otherwise specified.
        Sorting is done automatically before writing the table.
        """
        for name in self.fields():
            input_entry = getattr(self, name)
            if isinstance(input_entry, InputMixin):
                input_entry.sort()
