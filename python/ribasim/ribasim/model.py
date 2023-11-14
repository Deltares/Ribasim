import datetime
import shutil
from pathlib import Path
from typing import Any, Dict

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import tomli
import tomli_w
from pydantic import DirectoryPath, Field, model_serializer, model_validator

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
from ribasim.geometry.node import Node, NodeSchema
from ribasim.input_base import FileModel, NodeModel, TableModel, context_file_loading
from ribasim.types import FilePath


class Database(FileModel, NodeModel):
    node: Node[NodeSchema] = Field(default_factory=Node[NodeSchema])
    edge: Edge = Field(default_factory=Edge)

    def n_nodes(self):
        if self.node.df is not None:
            n = len(self.node.df)
        else:
            n = 0

        return n

    @classmethod
    def _load(cls, filepath: Path | None) -> Dict[str, Any]:
        if filepath is not None:
            context_file_loading.get()["database"] = filepath
        return {}

    @classmethod
    def _layername(cls, field: str) -> str:
        return field.capitalize()

    def _save(self, directory):
        # We write all tables to a temporary database with a dot prefix,
        # and at the end move this over the target file.
        # This does not throw a PermissionError if the file is open in QGIS.
        directory = Path(directory)
        db_path = directory / "database.gpkg"
        db_path = db_path.resolve()
        temp_path = db_path.with_stem(".database")

        # avoid adding tables to existing model
        temp_path.unlink(missing_ok=True)
        context_file_loading.get()["database"] = temp_path

        self.node._save(directory)
        self.edge._save(directory)

        shutil.move(temp_path, db_path)
        context_file_loading.get()["database"] = db_path

    @model_serializer
    def set_modelname(self) -> str:
        return "database.gpkg"


class Model(FileModel):
    """
    A full Ribasim model schematisation with all input.

    Ribasim model containing the location of the nodes, the edges between the
    nodes, and the node parametrization.

    Parameters
    ----------
    node : Node
        The ID, type and geometry of each node.
    edge : Edge
        How the nodes are connected.
    basin : Basin
        The waterbodies.
    fractional_flow : Optional[FractionalFlow]
        Split flows into fractions.
    level_boundary : Optional[LevelBoundary]
        Boundary condition specifying the water level.
    flow_boundary : Optional[FlowBoundary]
        Boundary conditions specifying the flow.
    linear_resistance: Optional[LinearResistance]
        Linear flow resistance.
    manning_resistance : Optional[ManningResistance]
        Flow resistance based on the Manning formula.
    tabulated_rating_curve : Optional[TabulatedRatingCurve]
        Tabulated rating curve describing flow based on the upstream water level.
    pump : Optional[Pump]
        Prescribed flow rate from one basin to the other.
    outlet : Optional[Outlet]
        Prescribed flow rate from one basin to the other.
    terminal : Optional[Terminal]
        Water sink without state or properties.
    discrete_control : Optional[DiscreteControl]
        Discrete control logic.
    pid_control : Optional[PidControl]
        PID controller attempting to set the level of a basin to a desired value using a pump/outlet.
    user : Optional[User]
        User node type with demand and priority.
    starttime : Union[str, datetime.datetime]
        Starting time of the simulation.
    endtime : Union[str, datetime.datetime]
        End time of the simulation.
    solver : Optional[Solver]
        Solver settings.
    logging : Optional[logging]
        Logging settings.
    """

    starttime: datetime.datetime
    endtime: datetime.datetime

    update_timestep: float = 86400
    relative_dir: str = "."
    input_dir: str = "."
    results_dir: str = "."

    database: Database = Field(default_factory=Database)
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

    def __repr__(self) -> str:
        first = []
        second = []
        for field in self.fields():
            attr = getattr(self, field)
            if isinstance(attr, TableModel):
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

        content = self.model_dump(exclude_unset=True, exclude_none=True)
        # Filter empty dicts (default Nodes)
        content = dict(filter(lambda x: x[1], content.items()))

        fn = directory / "ribasim.toml"
        with open(fn, "wb") as f:
            tomli_w.dump(content, f)
        return fn

    def _save(self, directory: DirectoryPath):
        for sub in self.nodes().values():
            sub._save(directory)

    def nodes(self):
        return {
            k: getattr(self, k)
            for k in self.model_fields.keys()
            if isinstance(getattr(self, k), (NodeModel,))
        }

    def validate_model_node_field_ids(self):
        """Check whether the node IDs of the node_type fields are valid."""

        n_nodes = self.database.n_nodes()

        # Check node IDs of node fields
        all_node_ids = set[int]()
        for node in self.nodes().values():
            all_node_ids.update(node.node_ids())

        unique, counts = np.unique(list(all_node_ids), return_counts=True)

        node_ids_positive_integers = np.greater(unique, 0) & np.equal(
            unique.astype(int), unique
        )

        if not node_ids_positive_integers.all():
            raise ValueError(
                f"Node IDs must be positive integers, got {unique[~node_ids_positive_integers]}."
            )

        if (counts > 1).any():
            raise ValueError(
                f"These node IDs were assigned to multiple node types: {unique[(counts > 1)]}."
            )

        if not np.array_equal(unique, np.arange(n_nodes) + 1):
            node_ids_missing = set(np.arange(n_nodes) + 1) - set(unique)
            node_ids_over = set(unique) - set(np.arange(n_nodes) + 1)
            msg = [
                f"Expected node IDs from 1 to {n_nodes} (the number of rows in self.database.node.df)."
            ]
            if len(node_ids_missing) > 0:
                msg.append(f"These node IDs are missing: {node_ids_missing}.")

            if len(node_ids_over) > 0:
                msg.append(f"These node IDs are unexpected: {node_ids_over}.")

            raise ValueError(" ".join(msg))

    def validate_model_node_ids(self):
        """Check whether the node IDs in the node field correspond to the node IDs on the node type fields."""

        error_messages = []

        for node in self.nodes().values():
            node_ids_field = node.node_ids()
            node_ids_from_node_field = self.database.node.df.loc[
                self.database.node.df["type"] == node.get_input_type()
            ].index

            if not set(node_ids_from_node_field) == set(node_ids_field):
                error_messages.append(
                    f"The node IDs in the field {node} {node_ids_field} do not correspond with the node IDs in the field node {node_ids_from_node_field.tolist()}."
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

    def write(self, directory: FilePath) -> Path:
        """
        Write the contents of the model to a database and a TOML configuration file.

        If ``directory`` does not exist, it is created before writing.

        Parameters
        ----------
        directory: FilePath
        """
        self.validate_model()
        context_file_loading.set({})
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        self._save(directory)
        fn = self._write_toml(directory)

        context_file_loading.set({})
        return fn

    @classmethod
    def _load(cls, filepath: Path | None) -> Dict[str, Any]:
        context_file_loading.set({})

        if filepath is not None:
            with open(filepath, "rb") as f:
                config = tomli.load(f)

            # Convert relative path to absolute path
            config["database"] = filepath.parent / config["database"]
            return config
        else:
            return {}

    @model_validator(mode="after")
    def reset_contextvar(self) -> "Model":
        # Drop database info
        context_file_loading.set({})
        return self

    @classmethod
    def from_toml(cls, path: Path | str) -> "Model":
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
        kwargs = cls._load(Path(path))
        return cls(**kwargs)

    def plot_control_listen(self, ax):
        x_start, x_end = [], []
        y_start, y_end = [], []

        condition = self.discrete_control.condition.df
        if condition is not None:
            for node_id in condition.node_id.unique():
                data_node_id = condition[condition.node_id == node_id]

                for listen_feature_id in data_node_id.listen_feature_id:
                    point_start = self.database.node.df.iloc[node_id - 1].geometry
                    x_start.append(point_start.x)
                    y_start.append(point_start.y)

                    point_end = self.database.node.df.iloc[
                        listen_feature_id - 1
                    ].geometry
                    x_end.append(point_end.x)
                    y_end.append(point_end.y)

        if self.pid_control.static.df is not None:
            static = self.pid_control.static.df
            time = self.pid_control.time.df
            node_static = self.database.node.static.df

            for table in [static, time]:
                if table is None:
                    continue

                for node_id in table.node_id.unique():
                    for listen_node_id in table.loc[
                        table.node_id == node_id, "listen_node_id"
                    ].unique():
                        point_start = node_static.iloc[listen_node_id - 1].geometry
                        x_start.append(point_start.x)
                        y_start.append(point_start.y)

                        point_end = node_static.iloc[node_id - 1].geometry
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
        self.database.edge.plot(ax=ax, zorder=2)
        self.plot_control_listen(ax)
        self.database.node.plot(ax=ax, zorder=3)

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
                listen_node_type = self.database.node.df.loc[listen_feature_id, "type"]
                symbol = truth_dict[truth_value]
                greater_than = condition["greater_than"]
                feature_type = "edge" if var == "flow" else "node"

                out += f"\tFor {feature_type} ID {listen_feature_id} ({listen_node_type}): {var} {symbol} {greater_than}\n"

            padding = len(enumeration) * " "
            out += f'\n{padding}This yielded control state "{control_state}":\n'

            affect_node_ids = self.database.edge.df[
                self.database.edge.df.from_node_id == control_node_id
            ].to_node_id

            for affect_node_id in affect_node_ids:
                affect_node_type = self.database.node.df.loc[affect_node_id, "type"]
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
