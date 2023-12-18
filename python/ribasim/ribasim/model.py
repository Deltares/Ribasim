import datetime
import shutil
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import tomli
import tomli_w
from pydantic import (
    DirectoryPath,
    Field,
    field_serializer,
    field_validator,
    model_serializer,
    model_validator,
)

from ribasim.config import (
    Allocation,
    Basin,
    DiscreteControl,
    FlowBoundary,
    FractionalFlow,
    LevelBoundary,
    LinearResistance,
    Logging,
    ManningResistance,
    Outlet,
    PidControl,
    Pump,
    Results,
    Solver,
    TabulatedRatingCurve,
    Terminal,
    User,
)
from ribasim.geometry.edge import Edge
from ribasim.geometry.node import Node
from ribasim.input_base import ChildModel, FileModel, NodeModel, context_file_loading
from ribasim.types import FilePath


class Network(FileModel, NodeModel):
    filepath: Path | None = Field(
        default=Path("database.gpkg"), exclude=True, repr=False
    )

    node: Node = Field(default_factory=Node)
    edge: Edge = Field(default_factory=Edge)

    def n_nodes(self):
        if self.node.df is not None:
            n = len(self.node.df)
        else:
            n = 0

        return n

    @classmethod
    def _load(cls, filepath: Path | None) -> dict[str, Any]:
        directory = context_file_loading.get().get("directory", None)
        if directory is not None:
            context_file_loading.get()["database"] = directory / "database.gpkg"
        return {}

    @classmethod
    def _layername(cls, field: str) -> str:
        return field.capitalize()

    def _save(self, directory, input_dir=Path(".")):
        # We write all tables to a temporary database with a dot prefix,
        # and at the end move this over the target file.
        # This does not throw a PermissionError if the file is open in QGIS.
        directory = Path(directory)
        db_path = directory / input_dir / "database.gpkg"
        db_path = db_path.resolve()
        db_path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = db_path.with_stem(".database")

        # avoid adding tables to existing model
        temp_path.unlink(missing_ok=True)
        context_file_loading.get()["database"] = temp_path

        self.node._save(directory, input_dir)
        self.edge._save(directory, input_dir)

        shutil.move(temp_path, db_path)
        context_file_loading.get()["database"] = db_path

    @model_serializer
    def set_modelname(self) -> str:
        if self.filepath is not None:
            return str(self.filepath.name)
        else:
            return str(self.model_fields["filepath"].default)


class Model(FileModel):
    """
    A full Ribasim model schematisation with all input.

    Ribasim model containing the location of the nodes, the edges between the
    nodes, and the node parametrization.

    Parameters
    ----------
    starttime : datetime.datetime
        Starting time of the simulation.
    endtime : datetime.datetime
        End time of the simulation.

    update_timestep: datetime.timedelta = timedelta(seconds=86400)
        The output time step of the simulation in seconds (default of 1 day)
    input_dir: Path = Path(".")
        The directory of the input files.
    results_dir: Path = Path("results")
        The directory of the results files.

    network: Network
        Class containing the topology (nodes and edges) of the model.

    results: Results
        Results configuration options.
    solver: Solver
        Solver configuration options.
    logging: Logging
        Logging configuration options.

    allocation: Allocation
        The allocation configuration.
    basin : Basin
        The waterbodies.
    fractional_flow : FractionalFlow
        Split flows into fractions.
    level_boundary : LevelBoundary
        Boundary condition specifying the water level.
    flow_boundary : FlowBoundary
        Boundary conditions specifying the flow.
    linear_resistance: LinearResistance
        Linear flow resistance.
    manning_resistance : ManningResistance
        Flow resistance based on the Manning formula.
    tabulated_rating_curve : TabulatedRatingCurve
        Tabulated rating curve describing flow based on the upstream water level.
    pump : Pump
        Prescribed flow rate from one basin to the other.
    outlet : Outlet
        Prescribed flow rate from one basin to the other.
    terminal : Terminal
        Water sink without state or properties.
    discrete_control : DiscreteControl
        Discrete control logic.
    pid_control : PidControl
        PID controller attempting to set the level of a basin to a desired value using a pump/outlet.
    user : User
        User node type with demand and priority.
    """

    starttime: datetime.datetime
    endtime: datetime.datetime

    update_timestep: datetime.timedelta = datetime.timedelta(seconds=86400)
    input_dir: Path = Field(default_factory=lambda: Path("."))
    results_dir: Path = Field(default_factory=lambda: Path("results"))

    network: Network = Field(default_factory=Network, alias="database", exclude=True)
    results: Results = Results()
    solver: Solver = Solver()
    logging: Logging = Logging()

    allocation: Allocation = Field(default_factory=Allocation)
    basin: Basin = Field(default_factory=Basin)
    fractional_flow: FractionalFlow = Field(default_factory=FractionalFlow)
    level_boundary: LevelBoundary = Field(default_factory=LevelBoundary)
    flow_boundary: FlowBoundary = Field(default_factory=FlowBoundary)
    linear_resistance: LinearResistance = Field(default_factory=LinearResistance)
    manning_resistance: ManningResistance = Field(default_factory=ManningResistance)
    tabulated_rating_curve: TabulatedRatingCurve = Field(
        default_factory=TabulatedRatingCurve
    )
    pump: Pump = Field(default_factory=Pump)
    outlet: Outlet = Field(default_factory=Outlet)
    terminal: Terminal = Field(default_factory=Terminal)
    discrete_control: DiscreteControl = Field(default_factory=DiscreteControl)
    pid_control: PidControl = Field(default_factory=PidControl)
    user: User = Field(default_factory=User)

    @field_validator("update_timestep")
    @classmethod
    def timestep_in_seconds(cls, v: Any) -> datetime.timedelta:
        if not isinstance(v, datetime.timedelta):
            v = datetime.timedelta(seconds=v)
        return v

    @model_validator(mode="after")
    def set_node_parent(self) -> "Model":
        for (
            k,
            v,
        ) in self.children().items():
            setattr(v, "_parent", self)
            setattr(v, "_parent_field", k)
        return self

    @field_serializer("update_timestep")
    def serialize_dt(self, td: datetime.timedelta) -> int:
        return int(td.total_seconds())

    @field_serializer("input_dir", "results_dir")
    def serialize_path(self, path: Path) -> str:
        return str(path)

    def model_post_init(self, __context: Any) -> None:
        # Always write dir fields
        self.model_fields_set.update({"input_dir", "results_dir"})

    def __repr__(self) -> str:
        """Generate a succinct overview of the Model content.

        Skip "empty" NodeModel instances: when all dataframes are None.
        """
        content = ["ribasim.Model("]
        INDENT = "    "
        for field in self.fields():
            attr = getattr(self, field)
            if isinstance(attr, NodeModel):
                attr_content = attr._repr_content()
                typename = type(attr).__name__
                if attr_content:
                    content.append(f"{INDENT}{field}={typename}({attr_content}),")
            else:
                content.append(f"{INDENT}{field}={repr(attr)},")

        content.append(")")
        return "\n".join(content)

    def _write_toml(self, fn: FilePath):
        fn = Path(fn)

        content = self.model_dump(exclude_unset=True, exclude_none=True, by_alias=True)
        # Filter empty dicts (default Nodes)
        content = dict(filter(lambda x: x[1], content.items()))
        with open(fn, "wb") as f:
            tomli_w.dump(content, f)
        return fn

    def _save(self, directory: DirectoryPath, input_dir: DirectoryPath):
        for sub in self.nodes().values():
            sub._save(directory, input_dir)

    def nodes(self):
        return {
            k: getattr(self, k)
            for k in self.model_fields.keys()
            if isinstance(getattr(self, k), NodeModel)
        }

    def children(self):
        return {
            k: getattr(self, k)
            for k in self.model_fields.keys()
            if isinstance(getattr(self, k), ChildModel)
        }

    def validate_model_node_field_ids(self):
        """Check whether the node IDs of the node_type fields are valid."""

        # Check node IDs of node fields
        all_node_ids = set[int]()
        for node in self.nodes().values():
            all_node_ids.update(node.node_ids())

        unique, counts = np.unique(list(all_node_ids), return_counts=True)
        node_ids_negative_integers = np.less(unique, 0) | np.not_equal(
            unique.astype(np.int64), unique
        )

        if node_ids_negative_integers.any():
            raise ValueError(
                f"Node IDs must be non-negative integers, got {unique[node_ids_negative_integers]}."
            )

        if (counts > 1).any():
            raise ValueError(
                f"These node IDs were assigned to multiple node types: {unique[(counts > 1)]}."
            )

    def validate_model_node_ids(self):
        """Check whether the node IDs in the data tables correspond to the node IDs in the network."""

        error_messages = []

        for node in self.nodes().values():
            nodetype = node.get_input_type()
            if nodetype == "Network":
                # skip the reference
                continue
            node_ids_data = set(node.node_ids())
            node_ids_network = set(
                self.network.node.df.loc[self.network.node.df["type"] == nodetype].index
            )

            if not node_ids_network == node_ids_data:
                extra_in_network = node_ids_network.difference(node_ids_data)
                extra_in_data = node_ids_data.difference(node_ids_network)
                error_messages.append(
                    f"""For {nodetype}, the node IDs in the data tables don't match the node IDs in the network.
    Node IDs only in the data tables: {extra_in_data}.
    Node IDs only in the network: {extra_in_network}.
                    """
                )

        if len(error_messages) > 0:
            raise ValueError("\n".join(error_messages))

    def validate_model(self):
        """Validate the model.

        Checks:
        - Whether the node IDs of the node_type fields are valid
        - Whether the node IDs in the node field correspond to the node IDs on the node type fields
        """

        self.validate_model_node_field_ids()
        self.validate_model_node_ids()

    @classmethod
    def read(cls, filepath: FilePath) -> "Model":
        """Read model from TOML file."""
        return cls(filepath=filepath)  # type: ignore

    def write(self, filepath: Path | str) -> Path:
        """
        Write the contents of the model to disk and save it as a TOML configuration file.

        If ``filepath.parent`` does not exist, it is created before writing.

        Parameters
        ----------
        filepath: FilePath ending in .toml
        """
        self.validate_model()
        filepath = Path(filepath)
        if not filepath.suffix == ".toml":
            raise ValueError(f"Filepath '{filepath}' is not a .toml file.")
        context_file_loading.set({})
        filepath = Path(filepath)
        directory = filepath.parent
        directory.mkdir(parents=True, exist_ok=True)
        self._save(directory, self.input_dir)
        fn = self._write_toml(filepath)

        context_file_loading.set({})
        return fn

    @classmethod
    def _load(cls, filepath: Path | None) -> dict[str, Any]:
        context_file_loading.set({})

        if filepath is not None:
            with open(filepath, "rb") as f:
                config = tomli.load(f)

            context_file_loading.get()["directory"] = filepath.parent / config.get(
                "input_dir", "."
            )
            return config
        else:
            return {}

    @model_validator(mode="after")
    def reset_contextvar(self) -> "Model":
        # Drop database info
        context_file_loading.set({})
        return self

    def plot_control_listen(self, ax):
        x_start, x_end = [], []
        y_start, y_end = [], []

        condition = self.discrete_control.condition.df
        if condition is not None:
            for node_id in condition.node_id.unique():
                data_node_id = condition[condition.node_id == node_id]

                for listen_feature_id in data_node_id.listen_feature_id:
                    point_start = self.network.node.df.iloc[node_id - 1].geometry
                    x_start.append(point_start.x)
                    y_start.append(point_start.y)

                    point_end = self.network.node.df.iloc[
                        listen_feature_id - 1
                    ].geometry
                    x_end.append(point_end.x)
                    y_end.append(point_end.y)

        for table in [self.pid_control.static.df, self.pid_control.time.df]:
            if table is None:
                continue

            node = self.network.node.df

            for node_id in table.node_id.unique():
                for listen_node_id in table.loc[
                    table.node_id == node_id, "listen_node_id"
                ].unique():
                    point_start = node.iloc[listen_node_id - 1].geometry
                    x_start.append(point_start.x)
                    y_start.append(point_start.y)

                    point_end = node.iloc[node_id - 1].geometry
                    x_end.append(point_end.x)
                    y_end.append(point_end.y)

        if len(x_start) == 0:
            return

        # This part can probably be done more efficiently
        for i, (x, y, x_, y_) in enumerate(zip(x_start, y_start, x_end, y_end)):
            ax.plot(
                [x, x_],
                [y, y_],
                c="gray",
                ls="--",
                label="Listen edge" if i == 0 else None,
            )

    def plot(self, ax=None) -> Any:
        """
        Plot the nodes and edges of the model.

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
        self.network.edge.plot(ax=ax, zorder=2)
        self.plot_control_listen(ax)
        self.network.node.plot(ax=ax, zorder=3)

        ax.legend(loc="lower left", bbox_to_anchor=(1, 0.5))

        return ax

    def print_discrete_control_record(self, path: FilePath) -> None:
        path = Path(path)
        df_control = pd.read_feather(path)
        node_attrs, node_instances = zip(*self.nodes().items())
        node_clss = [node_cls.get_input_type() for node_cls in node_instances]
        truth_dict = {"T": ">", "F": "<"}

        if self.discrete_control.condition.df is None:
            raise ValueError("This model has no control input.")

        for index, row in df_control.iterrows():
            datetime = row["time"]
            control_node_id = row["control_node_id"]
            truth_state = row["truth_state"]
            control_state = row["control_state"]
            enumeration = f"{index}. "

            out = f"{enumeration}At {datetime} the control node with ID {control_node_id} reached truth state {truth_state}:\n"

            if self.discrete_control.condition.df is None:
                return

            conditions = self.discrete_control.condition.df[
                self.discrete_control.condition.df.node_id == control_node_id
            ]

            for truth_value, (index, condition) in zip(
                truth_state, conditions.iterrows()
            ):
                var = condition["variable"]
                listen_feature_id = condition["listen_feature_id"]
                listen_node_type = self.network.node.df.loc[listen_feature_id, "type"]
                symbol = truth_dict[truth_value]
                greater_than = condition["greater_than"]
                feature_type = "edge" if var == "flow" else "node"

                out += f"\tFor {feature_type} ID {listen_feature_id} ({listen_node_type}): {var} {symbol} {greater_than}\n"

            padding = len(enumeration) * " "
            out += f'\n{padding}This yielded control state "{control_state}":\n'

            affect_node_ids = self.network.edge.df[
                self.network.edge.df.from_node_id == control_node_id
            ].to_node_id

            for affect_node_id in affect_node_ids:
                affect_node_type = self.network.node.df.loc[affect_node_id, "type"]
                nodeattr = node_attrs[node_clss.index(affect_node_type)]

                out += f"\tFor node ID {affect_node_id} ({affect_node_type}): "

                static = getattr(self, nodeattr).static.df
                row = static[
                    (static.node_id == affect_node_id)
                    & (static.control_state == control_state)
                ].iloc[0]

                names_and_values = []
                for var in static.columns:
                    if var not in ["remarks", "node_id", "control_state"]:
                        value = row[var]
                        if value is not None:
                            names_and_values.append(f"{var} = {value}")

                out += ", ".join(names_and_values) + "\n"

            print(out)
