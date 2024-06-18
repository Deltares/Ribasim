import datetime
from collections.abc import Generator
from os import PathLike
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import tomli
import tomli_w
from matplotlib import pyplot as plt
from pandera.typing.geopandas import GeoDataFrame
from pydantic import (
    DirectoryPath,
    Field,
    field_serializer,
    model_validator,
)

import ribasim
from ribasim.config import (
    Allocation,
    Basin,
    DiscreteControl,
    FlowBoundary,
    FlowDemand,
    FractionalFlow,
    LevelBoundary,
    LevelDemand,
    LinearResistance,
    Logging,
    ManningResistance,
    MultiNodeModel,
    Outlet,
    PidControl,
    Pump,
    Results,
    Solver,
    TabulatedRatingCurve,
    Terminal,
    UserDemand,
)
from ribasim.geometry.edge import EdgeSchema, EdgeTable
from ribasim.geometry.node import NodeTable
from ribasim.input_base import (
    ChildModel,
    FileModel,
    SpatialTableModel,
    context_file_loading,
)
from ribasim.utils import (
    MissingOptionalModule,
    _edge_lookup,
    _node_lookup,
    _time_in_ns,
)

try:
    import xugrid
except ImportError:
    xugrid = MissingOptionalModule("xugrid")


class Model(FileModel):
    """A model of inland water resources systems."""

    starttime: datetime.datetime
    endtime: datetime.datetime
    crs: str

    input_dir: Path = Field(default=Path("."))
    results_dir: Path = Field(default=Path("results"))

    logging: Logging = Field(default_factory=Logging)
    solver: Solver = Field(default_factory=Solver)
    results: Results = Field(default_factory=Results)

    allocation: Allocation = Field(default_factory=Allocation)

    basin: Basin = Field(default_factory=Basin)
    discrete_control: DiscreteControl = Field(default_factory=DiscreteControl)
    flow_boundary: FlowBoundary = Field(default_factory=FlowBoundary)
    flow_demand: FlowDemand = Field(default_factory=FlowDemand)
    fractional_flow: FractionalFlow = Field(default_factory=FractionalFlow)
    level_boundary: LevelBoundary = Field(default_factory=LevelBoundary)
    level_demand: LevelDemand = Field(default_factory=LevelDemand)
    linear_resistance: LinearResistance = Field(default_factory=LinearResistance)
    manning_resistance: ManningResistance = Field(default_factory=ManningResistance)
    outlet: Outlet = Field(default_factory=Outlet)
    pid_control: PidControl = Field(default_factory=PidControl)
    pump: Pump = Field(default_factory=Pump)
    tabulated_rating_curve: TabulatedRatingCurve = Field(
        default_factory=TabulatedRatingCurve
    )
    terminal: Terminal = Field(default_factory=Terminal)
    user_demand: UserDemand = Field(default_factory=UserDemand)

    edge: EdgeTable = Field(default_factory=EdgeTable)

    @model_validator(mode="after")
    def set_node_parent(self) -> "Model":
        for (
            k,
            v,
        ) in self._children().items():
            setattr(v, "_parent", self)
            setattr(v, "_parent_field", k)
        return self

    @model_validator(mode="after")
    def ensure_edge_table_is_present(self) -> "Model":
        if self.edge.df is None:
            self.edge.df = GeoDataFrame[EdgeSchema]()
        self.edge.df.set_geometry("geometry", inplace=True, crs=self.crs)
        return self

    @field_serializer("input_dir", "results_dir")
    def serialize_path(self, path: Path) -> str:
        return str(path)

    def model_post_init(self, __context: Any) -> None:
        # When serializing we exclude fields that are set to their default values
        # However, we always want to write `input_dir` and `results_dir`
        # By overriding `BaseModel.model_post_init` we can set them explicitly,
        # and enforce that they are always written.
        self.model_fields_set.update({"input_dir", "results_dir"})

    def __repr__(self) -> str:
        """Generate a succinct overview of the Model content.

        Skip "empty" NodeModel instances: when all dataframes are None.
        """
        content = ["ribasim.Model("]
        INDENT = "    "
        for field in self.fields():
            attr = getattr(self, field)
            if isinstance(attr, EdgeTable):
                content.append(f"{INDENT}{field}=Edge(...),")
            else:
                if isinstance(attr, MultiNodeModel) and attr.node.df is None:
                    # Skip unused node types
                    continue
                content.append(f"{INDENT}{field}={repr(attr)},")

        content.append(")")
        return "\n".join(content)

    def _write_toml(self, fn: Path) -> Path:
        """
        Write the model data to a TOML file.

        Parameters
        ----------
        fn : FilePath
            The file path where the TOML file will be written.

        Returns
        -------
        Path
            The file path of the written TOML file.
        """
        content = self.model_dump(exclude_unset=True, exclude_none=True, by_alias=True)
        # Filter empty dicts (default Nodes)
        content = dict(filter(lambda x: x[1], content.items()))
        content["ribasim_version"] = ribasim.__version__
        with open(fn, "wb") as f:
            tomli_w.dump(content, f)
        return fn

    def _save(self, directory: DirectoryPath, input_dir: DirectoryPath):
        # Set CRS of the tables to the CRS stored in the Model object
        self.set_crs(self.crs)
        db_path = directory / input_dir / "database.gpkg"
        db_path.parent.mkdir(parents=True, exist_ok=True)
        db_path.unlink(missing_ok=True)
        context_file_loading.get()["database"] = db_path
        self.edge._save(directory, input_dir)
        node = self.node_table()
        node._save(directory, input_dir)

        for sub in self._nodes():
            sub._save(directory, input_dir)

    def set_crs(self, crs: str) -> None:
        self._apply_crs_function("set_crs", crs)

    def to_crs(self, crs: str) -> None:
        # Set CRS of the tables to the CRS stored in the Model object
        self.set_crs(self.crs)
        self._apply_crs_function("to_crs", crs)

    def _apply_crs_function(self, function_name: str, crs: str) -> None:
        """Apply `function_name`, with `crs` as the first and only argument to all spatial tables."""
        self.edge.df = getattr(self.edge.df, function_name)(crs)
        for sub in self._nodes():
            if sub.node.df is not None:
                sub.node.df = getattr(sub.node.df, function_name)(crs)
            for table in sub._tables():
                if isinstance(table, SpatialTableModel) and table.df is not None:
                    table.df = getattr(table.df, function_name)(crs)
        self.crs = crs

    def node_table(self) -> NodeTable:
        """Compute the full sorted NodeTable from all node types."""
        df_chunks = [node.node.df.set_crs(self.crs) for node in self._nodes()]  # type:ignore
        df = pd.concat(df_chunks, ignore_index=True)
        node_table = NodeTable(df=df)
        node_table.sort()
        assert node_table.df is not None
        node_table.df.index.name = "fid"
        return node_table

    def _nodes(self) -> Generator[MultiNodeModel, Any, None]:
        """Return all non-empty MultiNodeModel instances."""
        for key in self.model_fields.keys():
            attr = getattr(self, key)
            if (
                isinstance(attr, MultiNodeModel)
                and attr.node.df is not None
                # TODO: Model.read creates empty node tables (#1278)
                and not attr.node.df.empty
            ):
                yield attr

    def _children(self):
        return {
            k: getattr(self, k)
            for k in self.model_fields.keys()
            if isinstance(getattr(self, k), ChildModel)
        }

    @classmethod
    def read(cls, filepath: str | PathLike[str]) -> "Model":
        """Read model from TOML file."""
        return cls(filepath=filepath)  # type: ignore

    def write(self, filepath: str | PathLike[str]) -> Path:
        """
        Write the contents of the model to disk and save it as a TOML configuration file.

        If ``filepath.parent`` does not exist, it is created before writing.

        Parameters
        ----------
        filepath: str | PathLike[str] A file path with .toml extension
        """
        # TODO
        # self.validate_model()
        filepath = Path(filepath)
        self.filepath = filepath
        if not filepath.suffix == ".toml":
            raise ValueError(f"Filepath '{filepath}' is not a .toml file.")
        context_file_loading.set({})
        directory = filepath.parent
        directory.mkdir(parents=True, exist_ok=True)
        self._save(directory, self.input_dir)
        fn = self._write_toml(filepath)

        context_file_loading.set({})
        return fn

    @classmethod
    def _load(cls, filepath: Path | None) -> dict[str, Any]:
        context_file_loading.set({})

        if filepath is not None and filepath.is_file():
            with open(filepath, "rb") as f:
                config = tomli.load(f)

            directory = filepath.parent / config.get("input_dir", ".")
            context_file_loading.get()["directory"] = directory
            context_file_loading.get()["database"] = directory / "database.gpkg"

            return config
        else:
            return {}

    @model_validator(mode="after")
    def reset_contextvar(self) -> "Model":
        # Drop database info
        context_file_loading.set({})
        return self

    def plot_control_listen(self, ax):
        df_listen_edge = pd.DataFrame(
            data={
                "control_node_id": pd.Series([], dtype=np.int32),
                "control_node_type": pd.Series([], dtype=str),
                "listen_node_id": pd.Series([], dtype=np.int32),
                "listen_node_type": pd.Series([], dtype=str),
            }
        )

        # Listen edges from PidControl
        for table in (self.pid_control.static.df, self.pid_control.time.df):
            if table is None:
                continue

            to_add = table[
                ["node_id", "listen_node_id", "listen_node_type"]
            ].drop_duplicates()
            to_add.columns = ["control_node_id", "listen_node_id", "listen_node_type"]
            to_add["control_node_type"] = "PidControl"
            df_listen_edge = pd.concat([df_listen_edge, to_add])

        # Listen edges from DiscreteControl
        df_variable = self.discrete_control.variable.df
        if df_variable is not None:
            to_add = df_variable[
                ["node_id", "listen_node_id", "listen_node_type"]
            ].drop_duplicates()
            to_add.columns = ["control_node_id", "listen_node_id", "listen_node_type"]
            to_add["control_node_type"] = "DiscreteControl"
            df_listen_edge = pd.concat([df_listen_edge, to_add])

        # Collect geometry data
        node = self.node_table().df
        control_nodes_geometry = df_listen_edge.merge(
            node,
            left_on=["control_node_id", "control_node_type"],
            right_on=["node_id", "node_type"],
            how="left",
        )["geometry"]

        listen_nodes_geometry = df_listen_edge.merge(
            node,
            left_on=["listen_node_id", "listen_node_type"],
            right_on=["node_id", "node_type"],
            how="left",
        )["geometry"]

        # Plot listen edges
        for i, (point_listen, point_control) in enumerate(
            zip(listen_nodes_geometry, control_nodes_geometry)
        ):
            ax.plot(
                [point_listen.x, point_control.x],
                [point_listen.y, point_control.y],
                color="gray",
                ls="--",
                label="Listen edge" if i == 0 else None,
            )
        return

    def plot(self, ax=None, indicate_subnetworks: bool = True) -> Any:
        """
        Plot the nodes, edges and allocation networks of the model.

        Parameters
        ----------
        ax : matplotlib.pyplot.Artist, optional
            Axes on which to draw the plot.

        Returns
        -------
        ax : matplotlib.pyplot.Artist
        """
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")

        node = self.node_table()
        self.edge.plot(ax=ax, zorder=2)
        self.plot_control_listen(ax)
        node.plot(ax=ax, zorder=3)

        handles, labels = ax.get_legend_handles_labels()

        if indicate_subnetworks:
            (
                handles_subnetworks,
                labels_subnetworks,
            ) = node.plot_allocation_networks(ax=ax, zorder=1)
            handles += handles_subnetworks
            labels += labels_subnetworks

        ax.legend(handles, labels, loc="lower left", bbox_to_anchor=(1, 0.5))

        return ax

    def to_xugrid(self, add_flow: bool = False, add_allocation: bool = False):
        """
        Convert the network to a `xugrid.UgridDataset`.
        To add flow results, set `add_flow=True`.
        To add allocation results, set `add_allocation=True`.
        Both cannot be added to the same dataset.
        This method will throw `ImportError`,
        if the optional dependency `xugrid` isn't installed.
        """

        if add_flow and add_allocation:
            raise ValueError("Cannot add both allocation and flow results.")

        node_df = self.node_table().df
        assert node_df is not None

        assert self.edge.df is not None
        edge_df = self.edge.df.copy()
        # We assume only the flow network is of interest.
        edge_df = edge_df[edge_df.edge_type == "flow"]

        node_id = node_df.node_id.to_numpy()
        edge_id = edge_df.index.to_numpy()
        from_node_id = edge_df.from_node_id.to_numpy()
        to_node_id = edge_df.to_node_id.to_numpy()
        node_lookup = _node_lookup(node_df)
        from_node_index = pd.MultiIndex.from_frame(
            edge_df[["from_node_type", "from_node_id"]]
        )
        to_node_index = pd.MultiIndex.from_frame(
            edge_df[["to_node_type", "to_node_id"]]
        )

        grid = xugrid.Ugrid1d(
            node_x=node_df.geometry.x,
            node_y=node_df.geometry.y,
            fill_value=-1,
            edge_node_connectivity=np.column_stack(
                (
                    node_lookup.loc[from_node_index],
                    node_lookup.loc[to_node_index],
                )
            ),
            name="ribasim",
            projected=node_df.crs.is_projected,
            crs=node_df.crs,
        )

        edge_dim = grid.edge_dimension
        node_dim = grid.node_dimension

        uds = xugrid.UgridDataset(None, grid)
        uds = uds.assign_coords(node_id=(node_dim, node_id))
        uds = uds.assign_coords(edge_id=(edge_dim, edge_id))
        uds = uds.assign_coords(from_node_id=(edge_dim, from_node_id))
        uds = uds.assign_coords(to_node_id=(edge_dim, to_node_id))

        if add_flow:
            uds = self._add_flow(uds, node_lookup)
        elif add_allocation:
            uds = self._add_allocation(uds)

        return uds

    def _checked_toml_path(self) -> Path:
        toml_path = self.filepath
        if toml_path is None:
            raise FileNotFoundError("Model must be written to disk to add results.")
        return toml_path

    def _add_flow(self, uds, node_lookup):
        toml_path = self._checked_toml_path()

        results_path = toml_path.parent / self.results_dir
        basin_path = results_path / "basin.arrow"
        flow_path = results_path / "flow.arrow"

        if not basin_path.is_file() or not flow_path.is_file():
            raise FileNotFoundError(
                f"Cannot find results in '{results_path}', "
                "perhaps the model needs to be run first."
            )

        basin_df = pd.read_feather(basin_path)
        flow_df = pd.read_feather(flow_path)
        _time_in_ns(basin_df)
        _time_in_ns(flow_df)

        # add the xugrid dimension indices to the dataframes
        edge_dim = uds.grid.edge_dimension
        node_dim = uds.grid.node_dimension
        edge_lookup = _edge_lookup(uds)
        flow_df[edge_dim] = edge_lookup[flow_df["edge_id"]].to_numpy()
        # Use a MultiIndex to ensure the lookup results is the same length as basin_df
        basin_df["node_type"] = "Basin"
        multi_index = pd.MultiIndex.from_frame(basin_df[["node_type", "node_id"]])
        basin_df[node_dim] = node_lookup.loc[multi_index].to_numpy()

        # add flow results to the UgridDataset
        flow_da = flow_df.set_index(["time", edge_dim])["flow_rate"].to_xarray()
        uds[flow_da.name] = flow_da

        # add basin results to the UgridDataset
        basin_df.drop(columns=["node_type", "node_id"], inplace=True)
        basin_ds = basin_df.set_index(["time", node_dim]).to_xarray()

        for var_name, da in basin_ds.data_vars.items():
            uds[var_name] = da

        return uds

    def _add_allocation(self, uds):
        toml_path = self._checked_toml_path()

        results_path = toml_path.parent / self.results_dir
        alloc_flow_path = results_path / "allocation_flow.arrow"

        if not alloc_flow_path.is_file():
            raise FileNotFoundError(
                f"Cannot find '{alloc_flow_path}', "
                "perhaps the model needs to be run first, or allocation is not used."
            )

        alloc_flow_df = pd.read_feather(
            alloc_flow_path,
            columns=["time", "edge_id", "flow_rate", "optimization_type", "priority"],
        )
        _time_in_ns(alloc_flow_df)

        # add the xugrid edge dimension index to the dataframe
        edge_dim = uds.grid.edge_dimension
        edge_lookup = _edge_lookup(uds)
        alloc_flow_df[edge_dim] = edge_lookup[alloc_flow_df["edge_id"]].to_numpy()

        # "flow_rate_allocated" is the sum of all allocated flow rates over the priorities
        allocate_df = alloc_flow_df.loc[
            alloc_flow_df["optimization_type"] == "allocate"
        ]
        uds["flow_rate_allocated"] = (
            allocate_df.groupby(["time", edge_dim])["flow_rate"].sum().to_xarray()
        )

        # also add the individual priorities and optimization types
        # added as separate variables to ensure QGIS / MDAL compatibility
        for (optimization_type, priority), group in alloc_flow_df.groupby(
            ["optimization_type", "priority"]
        ):
            varname = f"{optimization_type}_priority_{priority}"
            da = group.set_index(["time", edge_dim])["flow_rate"].to_xarray()
            uds[varname] = da

        return uds
