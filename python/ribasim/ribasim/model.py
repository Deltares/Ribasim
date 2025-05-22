import datetime
import logging
import shutil
import warnings
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
    FilePath,
    PrivateAttr,
    field_serializer,
    model_validator,
)

import ribasim
from ribasim.config import (
    Allocation,
    Basin,
    ContinuousControl,
    DiscreteControl,
    Experimental,
    FlowBoundary,
    FlowDemand,
    Junction,
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
from ribasim.db_utils import _set_db_schema_version
from ribasim.geometry.link import LinkSchema, LinkTable
from ribasim.geometry.node import NodeTable
from ribasim.input_base import (
    ChildModel,
    FileModel,
    SpatialTableModel,
    context_file_loading,
    context_file_writing,
)
from ribasim.utils import (
    MissingOptionalModule,
    UsedIDs,
    _add_cf_attributes,
    _concat,
    _link_lookup,
    _node_lookup,
    _node_lookup_numpy,
)
from ribasim.validation import control_link_neighbor_amount, flow_link_neighbor_amount

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

    experimental: Experimental = Field(default_factory=Experimental)

    basin: Basin = Field(default_factory=Basin)
    junction: Junction = Field(default_factory=Junction)
    continuous_control: ContinuousControl = Field(default_factory=ContinuousControl)
    discrete_control: DiscreteControl = Field(default_factory=DiscreteControl)
    flow_boundary: FlowBoundary = Field(default_factory=FlowBoundary)
    flow_demand: FlowDemand = Field(default_factory=FlowDemand)
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

    link: LinkTable = Field(default_factory=LinkTable)
    use_validation: bool = Field(default=True, exclude=True)

    _used_node_ids: UsedIDs = PrivateAttr(default_factory=UsedIDs)

    @model_validator(mode="after")
    def _set_node_parent(self) -> "Model":
        for (
            k,
            v,
        ) in self._children().items():
            setattr(v, "_parent", self)
            setattr(v, "_parent_field", k)
        return self

    @model_validator(mode="after")
    def _ensure_link_table_is_present(self) -> "Model":
        if self.link.df is None:
            self.link.df = GeoDataFrame[LinkSchema](index=pd.Index([], name="link_id"))
        self.link.df = self.link.df.set_geometry("geometry", crs=self.crs)
        return self

    @model_validator(mode="after")
    def _update_used_ids(self) -> "Model":
        # Only update the used node IDs if we read from a database
        if "database" in context_file_loading.get():
            df = self.node_table().df
            assert df is not None
            if len(df.index) > 0:
                self._used_node_ids.node_ids.update(df.index)
                self._used_node_ids.max_node_id = df.index.max()
        return self

    @field_serializer("input_dir", "results_dir")
    def _serialize_path(self, path: Path) -> str:
        return str(path)

    def model_post_init(self, __context: Any) -> None:
        # When serializing we exclude fields that are set to their default values
        # However, we always want to write `input_dir` and `results_dir`
        # By overriding `BaseModel.model_post_init` we can set them explicitly,
        # and enforce that they are always written.
        self.model_fields_set.update({"input_dir", "results_dir"})
        self.edge = self.link  # Backwards compatible alias for link

    def __repr__(self) -> str:
        """Generate a succinct overview of the Model content.

        Skip "empty" NodeModel instances: when all dataframes are None.
        """
        content = ["ribasim.Model("]
        INDENT = "    "
        for field in self._fields():
            attr = getattr(self, field)
            if isinstance(attr, LinkTable):
                content.append(f"{INDENT}{field}=Link(...),")
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
        content = self.model_dump(
            exclude_unset=True, exclude_none=True, by_alias=True, context="write"
        )
        # Filter empty dicts (default Nodes)
        content = dict(filter(lambda x: x[1], content.items()))
        content["ribasim_version"] = ribasim.__version__
        with open(fn, "wb") as f:
            tomli_w.dump(content, f)
        return fn

    def _save(self, directory: DirectoryPath, input_dir: DirectoryPath):
        # We write all tables to a temporary GeoPackage with a dot prefix,
        # and at the end move this over the target file.
        # This does not throw a PermissionError if the file is open in QGIS.
        db_path = directory / input_dir / ".database.gpkg"

        # avoid adding tables to existing model
        db_path.parent.mkdir(parents=True, exist_ok=True)
        db_path.unlink(missing_ok=True)
        context_file_writing.get()["database"] = db_path

        self.link._save(directory, input_dir)
        node = self.node_table()

        assert node.df is not None
        node._save(directory, input_dir)

        # Run after geopackage schema has been created
        _set_db_schema_version(db_path, ribasim.__schema_version__)

        for sub in self._nodes():
            sub._save(directory, input_dir)

        shutil.move(db_path, db_path.with_name("database.gpkg"))

    def set_crs(self, crs: str) -> None:
        """Set the coordinate reference system of the data in the model.

        Parameters
        ----------
        crs : str
            Coordinate reference system, like "EPSG:4326" for WGS84 latitude longitude.
        """
        self._apply_crs_function("set_crs", crs)

    def to_crs(self, crs: str) -> None:
        # Set CRS of the tables to the CRS stored in the Model object
        self.set_crs(self.crs)
        self._apply_crs_function("to_crs", crs)

    def _apply_crs_function(self, function_name: str, crs: str) -> None:
        """Apply `function_name`, with `crs` as the first and only argument to all spatial tables."""
        getattr(self.link.df, function_name)(crs, inplace=True)
        for sub in self._nodes():
            if sub.node.df is not None:
                getattr(sub.node.df, function_name)(crs, inplace=True)
            for table in sub._tables():
                if isinstance(table, SpatialTableModel) and table.df is not None:
                    getattr(table.df, function_name)(crs, inplace=True)
        self.crs = crs

    def node_table(self) -> NodeTable:
        """Compute the full sorted NodeTable from all node types."""
        df_chunks = [node.node.df for node in self._nodes()]
        df = (
            _concat(df_chunks)
            if df_chunks
            else pd.DataFrame(index=pd.Index([], name="node_id"))
        )
        node_table = NodeTable(df=df)
        node_table.sort()
        assert node_table.df is not None
        assert node_table.df.index.is_unique, "node_id must be unique"
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
        """Read a model from a TOML file.

        Parameters
        ----------
        filepath : str | PathLike[str]
            The path to the TOML file.
        """
        if not Path(filepath).is_file():
            raise FileNotFoundError(f"File '{filepath}' does not exist.")
        return cls(filepath=filepath)  # type: ignore

    def write(self, filepath: str | PathLike[str]) -> Path:
        """Write the contents of the model to disk and save it as a TOML configuration file.

        If ``filepath.parent`` does not exist, it is created before writing.

        Parameters
        ----------
        filepath : str | PathLike[str]
            A file path with .toml extension.
        """
        if self.use_validation:
            self._validate_model()

        filepath = Path(filepath)
        self.filepath = filepath
        if not filepath.suffix == ".toml":
            raise ValueError(f"Filepath '{filepath}' is not a .toml file.")
        context_file_writing.set({})
        directory = filepath.parent
        directory.mkdir(parents=True, exist_ok=True)
        self._save(directory, self.input_dir)
        fn = self._write_toml(filepath)

        context_file_writing.set({})
        return fn

    def _validate_model(self):
        df_link = self.link.df
        df_chunks = [node.node.df for node in self._nodes()]
        df_node = _concat(df_chunks)

        df_graph = df_link
        # Join df_link with df_node to get to_node_type
        df_graph = df_graph.join(
            df_node[["node_type"]], on="from_node_id", how="left", rsuffix="_from"
        )
        df_graph = df_graph.rename(columns={"node_type": "from_node_type"})

        df_graph = df_graph.join(
            df_node[["node_type"]], on="to_node_id", how="left", rsuffix="_to"
        )
        df_graph = df_graph.rename(columns={"node_type": "to_node_type"})

        if not self._has_valid_neighbor_amount(
            df_graph, flow_link_neighbor_amount, "flow", df_node["node_type"]
        ):
            raise ValueError("Minimum flow inneighbor or outneighbor unsatisfied")
        if not self._has_valid_neighbor_amount(
            df_graph, control_link_neighbor_amount, "control", df_node["node_type"]
        ):
            raise ValueError("Minimum control inneighbor or outneighbor unsatisfied")

    def _has_valid_neighbor_amount(
        self,
        df_graph: pd.DataFrame,
        link_amount: dict[str, list[int]],
        link_type: str,
        nodes,
    ) -> bool:
        """Check if the neighbor amount of the two nodes connected by the given link meet the minimum requirements."""
        is_valid = True

        # filter graph by link type
        df_graph = df_graph.loc[df_graph["link_type"] == link_type]

        # count occurrence of "from_node" which reflects the number of outneighbors
        from_node_count = (
            df_graph.groupby("from_node_id").size().reset_index(name="from_node_count")
        )

        # append from_node_count column to from_node_id and from_node_type
        from_node_info = (
            df_graph[["from_node_id", "from_node_type"]]
            .drop_duplicates()
            .merge(from_node_count, on="from_node_id", how="left")
        )
        from_node_info = from_node_info[
            ["from_node_id", "from_node_count", "from_node_type"]
        ]

        # add the node that is not the upstream of any other nodes
        from_node_info = self._add_source_sink_node(nodes, from_node_info, "from")

        # loop over all the "from_node" and check if they have enough outneighbor
        for _, row in from_node_info.iterrows():
            # from node's outneighbor
            if row["from_node_count"] < link_amount[row["from_node_type"]][2]:
                is_valid = False
                logging.error(
                    f"Node {row['from_node_id']} must have at least {link_amount[row['from_node_type']][2]} outneighbor(s) (got {row['from_node_count']})"
                )

        # count occurrence of "to_node" which reflects the number of inneighbors
        to_node_count = (
            df_graph.groupby("to_node_id").size().reset_index(name="to_node_count")
        )

        # append to_node_count column to result
        to_node_info = (
            df_graph[["to_node_id", "to_node_type"]]
            .drop_duplicates()
            .merge(to_node_count, on="to_node_id", how="left")
        )
        to_node_info = to_node_info[["to_node_id", "to_node_count", "to_node_type"]]

        # add the node that is not the downstream of any other nodes
        to_node_info = self._add_source_sink_node(nodes, to_node_info, "to")

        # loop over all the "to_node" and check if they have enough inneighbor
        for _, row in to_node_info.iterrows():
            if row["to_node_count"] < link_amount[row["to_node_type"]][0]:
                is_valid = False
                logging.error(
                    f"Node {row['to_node_id']} must have at least {link_amount[row['to_node_type']][0]} inneighbor(s) (got {row['to_node_count']})"
                )

        return is_valid

    def _add_source_sink_node(
        self, nodes, node_info: pd.DataFrame, direction: str
    ) -> pd.DataFrame:
        """Loop over node table.

        Add the nodes whose id are missing in the from_node and to_node column in the link table because they are not the upstream or downstrem of other nodes.

        Specify that their occurrence in from_node table or to_node table is 0.
        """
        # loop over nodes, add the one that is not the downstream (from) or upstream (to) of any other nodes
        for index, node in enumerate(nodes):
            if nodes.index[index] not in node_info[f"{direction}_node_id"].to_numpy():
                new_row = {
                    f"{direction}_node_id": nodes.index[index],
                    f"{direction}_node_count": 0,
                    f"{direction}_node_type": node,
                }
                node_info = _concat(
                    [node_info, pd.DataFrame([new_row])], ignore_index=True
                )

        return node_info

    @classmethod
    def _load(cls, filepath: Path | None) -> dict[str, Any]:
        context_file_loading.set({})

        if filepath is not None and filepath.is_file():
            with open(filepath, "rb") as f:
                config = tomli.load(f)

            directory = filepath.parent / config.get("input_dir", ".")
            context_file_loading.get()["directory"] = directory
            db_path = directory / "database.gpkg"

            if not db_path.is_file():
                raise FileNotFoundError(f"Database file '{db_path}' does not exist.")

            context_file_loading.get()["database"] = db_path

            return config
        else:
            return {}

    @model_validator(mode="after")
    def _reset_contextvar(self) -> "Model":
        # Drop database info
        context_file_loading.set({})
        return self

    @property
    def toml_path(self) -> FilePath:
        """
        Get the path to the TOML file if it exists.

        Raises
        ------
        FileNotFoundError
            If the model has not been written to disk.

        Returns
        -------
        FilePath
            The path to the TOML file.
        """
        if self.filepath is None:
            raise FileNotFoundError("Model must be written to disk.")
        return FilePath(self.filepath)

    @property
    def results_path(self) -> DirectoryPath:
        """
        Get the path to the results directory if it exists.

        This checks for the presence of required result files in the directory.

        Raises
        ------
        FileNotFoundError
            If any of the required result files are missing.

        Returns
        -------
        DirectoryPath
            The path to the results directory.
        """
        toml_path = self.toml_path
        results_dir = DirectoryPath(toml_path.parent / self.results_dir)
        # This only checks results that are always written.
        # Some results like allocation_flow.arrow are optional.
        filenames = ["basin_state.arrow", "basin.arrow", "flow.arrow"]
        for filename in filenames:
            if not (results_dir / filename).is_file():
                raise FileNotFoundError(
                    f"Cannot find {filename} in '{results_dir}', "
                    "perhaps the model needs to be run first."
                )
        return results_dir

    def plot_control_listen(self, ax):
        """Plot the implicit listen links of the model."""
        df_listen_link = pd.DataFrame(
            data={
                "control_node_id": pd.Series([], dtype="int32[pyarrow]"),
                "listen_node_id": pd.Series([], dtype="int32[pyarrow]"),
            }
        )

        # Listen links from PidControl
        for table in (self.pid_control.static.df, self.pid_control.time.df):
            if table is None:
                continue

            to_add = table[["node_id", "listen_node_id"]].drop_duplicates()
            to_add.columns = ["control_node_id", "listen_node_id"]
            df_listen_link = _concat([df_listen_link, to_add])

        # Listen links from ContinuousControl and DiscreteControl
        for table, name in (
            (self.continuous_control.variable.df, "ContinuousControl"),
            (self.discrete_control.variable.df, "DiscreteControl"),
        ):
            if table is None:
                continue

            to_add = table[["node_id", "listen_node_id"]].drop_duplicates()
            to_add.columns = [
                "control_node_id",
                "listen_node_id",
            ]
            df_listen_link = _concat([df_listen_link, to_add])

        # Collect geometry data
        node = self.node_table().df
        control_nodes_geometry = df_listen_link.merge(
            node,
            left_on=["control_node_id"],
            right_on=["node_id"],
            how="left",
        )["geometry"]

        listen_nodes_geometry = df_listen_link.merge(
            node,
            left_on=["listen_node_id"],
            right_on=["node_id"],
            how="left",
        )["geometry"]

        # Plot listen links
        for i, (point_listen, point_control) in enumerate(
            zip(listen_nodes_geometry, control_nodes_geometry)
        ):
            ax.plot(
                [point_listen.x, point_control.x],
                [point_listen.y, point_control.y],
                color="gray",
                ls="--",
                label="Listen link" if i == 0 else None,
            )
        return

    def plot(
        self,
        ax=None,
        indicate_subnetworks: bool = True,
        aspect_ratio_bound: float = 0.33,
    ) -> Any:
        """Plot the nodes, links and allocation networks of the model.

        Parameters
        ----------
        ax : matplotlib.pyplot.Artist
            Axes on which to draw the plot.
        indicate_subnetworks : bool
            Whether to indicate subnetworks with a convex hull backdrop.
        aspect_ratio_bound : float
            The maximal aspect ratio in (0,1). The smaller this number, the further the figure
            shape is allowed to be from a square

        Returns
        -------
        ax : matplotlib.pyplot.Artist
            Axis on which the plot is drawn.
        """
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")

        node = self.node_table()
        self.link.plot(ax=ax, zorder=2)
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

        # Enforce aspect ratio bound
        xlim = ax.get_xlim()
        ylim = ax.get_ylim()
        xsize = xlim[1] - xlim[0]
        ysize = ylim[1] - ylim[0]

        if ysize < aspect_ratio_bound * xsize:
            y_mid = (ylim[0] + ylim[1]) / 2
            ysize_new = aspect_ratio_bound * xsize
            ax.set_ylim(y_mid - ysize_new / 2, y_mid + ysize_new / 2)
        elif xsize < aspect_ratio_bound * ysize:
            x_mid = (xlim[0] + xlim[1]) / 2
            xsize_new = aspect_ratio_bound * ysize
            ax.set_xlim(x_mid - xsize_new / 2, x_mid + xsize_new / 2)

        return ax

    def to_xugrid(self, add_flow: bool = False, add_allocation: bool = False):
        """Convert the network to a `xugrid.UgridDataset`.

        Either the flow or the allocation data can be added, but not both simultaneously.
        This method will throw `ImportError` if the optional dependency `xugrid` isn't installed.

        Parameters
        ----------
        add_flow : bool
            add flow results (Optional, defaults to False)
        add_allocation : bool
            add allocation results (Optional, defaults to False)
        """
        if add_flow and add_allocation:
            raise ValueError("Cannot add both allocation and flow results.")

        node_df = self.node_table().df
        assert node_df is not None

        assert self.link.df is not None
        link_df = self.link.df.copy()
        # We assume only the flow network is of interest.
        link_df = link_df[link_df.link_type == "flow"]

        node_id = node_df.index.to_numpy()
        link_id = link_df.index.to_numpy()
        from_node_id = link_df.from_node_id.to_numpy()
        to_node_id = link_df.to_node_id.to_numpy()
        node_lookup = _node_lookup_numpy(node_id)

        grid = xugrid.Ugrid1d(
            node_x=node_df.geometry.x,
            node_y=node_df.geometry.y,
            fill_value=-1,
            edge_node_connectivity=np.column_stack(
                (
                    node_lookup.loc[from_node_id],
                    node_lookup.loc[to_node_id],
                )
            ),
            name="ribasim",
            projected=node_df.crs.is_projected,
            crs=node_df.crs,
        )

        link_dim = grid.edge_dimension
        node_dim = grid.node_dimension

        uds = xugrid.UgridDataset(None, grid)
        uds = uds.assign_coords(node_id=(node_dim, node_id))
        uds = uds.assign_coords(link_id=(link_dim, link_id))
        uds = uds.assign_coords(from_node_id=(link_dim, from_node_id))
        uds = uds.assign_coords(to_node_id=(link_dim, to_node_id))

        if add_flow:
            uds = self._add_flow(uds, node_lookup)
        elif add_allocation:
            uds = self._add_allocation(uds)

        return uds

    def _add_flow(self, uds, node_lookup):
        basin_path = self.results_path / "basin.arrow"
        flow_path = self.results_path / "flow.arrow"
        basin_df = pd.read_feather(basin_path)
        flow_df = pd.read_feather(flow_path)

        # add the xugrid dimension indices to the dataframes
        link_dim = uds.grid.edge_dimension
        node_dim = uds.grid.node_dimension
        node_lookup = _node_lookup(uds)
        link_lookup = _link_lookup(uds)
        flow_df[link_dim] = link_lookup[flow_df["link_id"]].to_numpy()
        basin_df[node_dim] = node_lookup[basin_df["node_id"]].to_numpy()

        # add flow results to the UgridDataset
        flow_da = flow_df.set_index(["time", link_dim])["flow_rate"].to_xarray()
        uds[flow_da.name] = flow_da

        # add basin results to the UgridDataset
        basin_df.drop(columns=["node_id"], inplace=True)
        basin_ds = basin_df.set_index(["time", node_dim]).to_xarray()

        for var_name, da in basin_ds.data_vars.items():
            uds[var_name] = da

        return uds

    def _add_allocation(self, uds):
        alloc_flow_path = self.results_path / "allocation_flow.arrow"

        if not alloc_flow_path.is_file():
            raise FileNotFoundError(
                f"Cannot find '{alloc_flow_path}', "
                "perhaps the model needs to be run first, or allocation is not used."
            )

        alloc_flow_df = pd.read_feather(
            alloc_flow_path,
            columns=[
                "time",
                "link_id",
                "flow_rate",
                "optimization_type",
                "demand_priority",
            ],
        )

        # add the xugrid link dimension index to the dataframe
        link_dim = uds.grid.edge_dimension
        link_lookup = _link_lookup(uds)
        alloc_flow_df[link_dim] = link_lookup[alloc_flow_df["link_id"]].to_numpy()

        # "flow_rate_allocated" is the sum of all allocated flow rates over the demand priorities
        allocate_df = alloc_flow_df.loc[
            alloc_flow_df["optimization_type"] == "allocate"
        ]
        uds["flow_rate_allocated"] = (
            allocate_df.groupby(["time", link_dim])["flow_rate"].sum().to_xarray()
        )

        # also add the individual demand priorities and optimization types
        # added as separate variables to ensure QGIS / MDAL compatibility
        for (optimization_type, demand_priority), group in alloc_flow_df.groupby(
            ["optimization_type", "demand_priority"]
        ):
            varname = f"{optimization_type}_priority_{demand_priority}"
            da = group.set_index(["time", link_dim])["flow_rate"].to_xarray()
            uds[varname] = da

        return uds

    def to_fews(
        self,
        region_home: str | PathLike[str],
        add_network: bool = True,
        add_results: bool = True,
    ) -> None:
        """
        Write the model network and results into files used by Delft-FEWS.

        ** Warning: This method is experimental and is likely to change. **

        To run this method, the model needs to be written to disk, and have results.
        The Node, Link and Basin / area tables are written to shapefiles in the REGION_HOME/Config directory.
        The results are written to NetCDF files in the REGION_HOME/Modules directory.
        The netCDF files are NetCDF4 with CF-conventions.

        Parameters
        ----------
        region_home: str | PathLike[str]
            Path to the Delft-FEWS REGION_HOME directory.
        add_network: bool, optional
            Write shapefiles representing the network, enabled by default.
        add_results: bool, optional
            Write the results to NetCDF files, enabled by default.
        """
        region_home = DirectoryPath(region_home)
        if add_network:
            self._network_to_fews(region_home)
        if add_results:
            self._results_to_fews(region_home)

    def _network_to_fews(self, region_home: DirectoryPath) -> None:
        """Write the Node and Link tables to shapefiles for use in Delft-FEWS."""
        df_link = self.link.df
        df_node = self.node_table().df
        assert df_link is not None
        assert df_node is not None

        df_basin_area = self.basin.area.df
        if df_basin_area is None:
            # Fall back to the Basin points if the area polygons are not set
            df_basin_area = df_node[df_node["node_type"] == "Basin"]

        network_dir = region_home / "Config/MapLayerFiles/{ModelId}"
        network_dir.mkdir(parents=True, exist_ok=True)
        link_path = network_dir / "{ModelId}Links.shp"
        node_path = network_dir / "{ModelId}Nodes.shp"
        basin_area_path = network_dir / "{ModelId}Areas.shp"

        with warnings.catch_warnings():
            warnings.filterwarnings(
                "ignore", "Normalized/laundered field name", RuntimeWarning
            )
            warnings.filterwarnings(
                "ignore",
                "Column names longer than 10 characters will be truncated when saved to ESRI Shapefile.",
                UserWarning,
            )
            df_link.to_file(link_path)
            df_node.to_file(node_path)
            df_basin_area.to_file(basin_area_path)

    def _results_to_fews(self, region_home: DirectoryPath) -> None:
        """Convert the model results to NetCDF with CF-conventions for importing into Delft-FEWS."""
        # Delft-FEWS doesn't support our UGRID from `model.to_xugrid` yet,
        # so we convert Arrow to regular CF-NetCDF4.

        basin_path = self.results_path / "basin.arrow"
        flow_path = self.results_path / "flow.arrow"
        concentration_path = self.results_path / "concentration.arrow"

        basin_df = pd.read_feather(basin_path)
        flow_df = pd.read_feather(flow_path)

        ds_basin = basin_df.set_index(["time", "node_id"]).to_xarray()
        _add_cf_attributes(ds_basin, timeseries_id="node_id")
        ds_basin["level"].attrs.update({"units": "m"})
        ds_basin["storage"].attrs.update({"units": "m3"})
        ds_basin["relative_error"].attrs.update({"units": "1"})

        flow_rate_variables = [
            "inflow_rate",
            "outflow_rate",
            "storage_rate",
            "precipitation",
            "evaporation",
            "drainage",
            "infiltration",
            "balance_error",
        ]
        for var in flow_rate_variables:
            ds_basin[var].attrs.update({"units": "m3 s-1"})

        ds_flow = flow_df.set_index(["time", "link_id"]).to_xarray()
        _add_cf_attributes(ds_flow, timeseries_id="link_id")
        ds_flow["flow_rate"].attrs.update({"units": "m3 s-1"})

        results_dir = region_home / "Modules/ribasim/{ModelId}/work/results"
        results_dir.mkdir(parents=True, exist_ok=True)
        ds_basin.to_netcdf(results_dir / "basin.nc")
        ds_flow.to_netcdf(results_dir / "flow.nc")

        if concentration_path.is_file():
            df = pd.read_feather(concentration_path)
            ds = df.set_index(["time", "node_id", "substance"]).to_xarray()
            _add_cf_attributes(ds, timeseries_id="node_id", realization="substance")
            ds["concentration"].attrs.update({"units": "g m-3"})
            ds.to_netcdf(results_dir / "concentration.nc")
