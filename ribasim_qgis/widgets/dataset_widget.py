"""
A widget that displays the available input layers in the GeoPackage.

It also allows enabling or disabling individual elements for a computation.
"""

import contextlib
import os
import re
import shutil
from contextvars import ContextVar
from datetime import datetime
from functools import partial
from pathlib import Path
from typing import Any, cast

import numpy as np
from qgis.core import (
    Qgis,
    QgsApplication,
    QgsDateTimeRange,
    QgsEditorWidgetSetup,
    QgsExpressionContextUtils,
    QgsFeatureRequest,
    QgsField,
    QgsInterval,
    QgsLayerTreeGroup,
    QgsMapLayer,
    QgsProject,
    QgsRelation,
    QgsSettings,
    QgsTemporalNavigationObject,
    QgsVectorLayer,
    QgsVectorLayerTemporalProperties,
)
from qgis.PyQt.QtCore import QDateTime, QMetaType
from qgis.PyQt.QtWidgets import (
    QDialog,
    QFileDialog,
    QMenu,
    QPlainTextEdit,
    QVBoxLayout,
    QWidget,
)

from ribasim_qgis.core.model import (
    get_database_path_from_model_file,
    get_directory_path_from_model_file,
    get_toml_dict,
)
from ribasim_qgis.core.netcdf import (
    TIME_FORMAT,
    NetCDFResult,
    read_basin_nc,
    read_concentration_nc,
    read_flow_nc,
)
from ribasim_qgis.core.nodes import (
    STYLE_DIR,
    load_nodes_from_geopackage,
)
from ribasim_qgis.core.observations import Observations, read_observations
from ribasim_qgis.widgets.plot_widget import PlotData, PlotWidget, Trace, VariableTraces
from ribasim_qgis.widgets.task import RibasimTask

group_position_var: ContextVar[int] = ContextVar("group_position", default=0)

# Mapping from result file name to its id column.
_ID_COLUMNS: dict[str, str] = {
    "basin": "node_id",
    "flow": "link_id",
    "concentration": "node_id",
}

# Mapping from result file name to the entity type used as legend prefix.
_ENTITY_BY_FILE: dict[str, str] = {
    "basin": "Basin",
    "flow": "Link",
    "concentration": "Basin",
}

# Default variables to select per file when no previous selection exists.
_DEFAULT_VARIABLES: dict[str, list[str]] = {
    "basin": ["level", "inflow_rate", "outflow_rate"],
    "flow": ["flow_rate"],
}

# Non-Basin node types whose flow_rate is taken from their outgoing flow link.
# These nodes are conservative (inflow == outflow), so the outgoing link
# flow_rate represents the node's flow_rate.
_FLOW_RATE_FROM_OUTGOING_LINK: frozenset[str] = frozenset(
    {
        "TabulatedRatingCurve",
        "LinearResistance",
        "ManningResistance",
        "Pump",
        "Outlet",
        "FlowBoundary",
    }
)

# Non-conservative node types: inflow and outflow can differ, so we plot both
# the incoming and outgoing flow links as separate traces.
_FLOW_RATE_FROM_INCOMING_AND_OUTGOING_LINKS: frozenset[str] = frozenset({"UserDemand"})

# Node types with potentially multiple incoming flow links whose summed
# inflow we plot. ``Terminal`` only has incoming flow; ``Junction`` is
# conservative so the inflow sum equals the outflow sum.
_FLOW_RATE_FROM_INCOMING_LINKS_SUM: frozenset[str] = frozenset({"Terminal", "Junction"})

# Node types with potentially multiple incoming and outgoing flow links
# where inflow and outflow may differ. We plot the sum of incoming and the
# sum of outgoing links as separate traces.
_FLOW_RATE_FROM_INCOMING_AND_OUTGOING_LINKS_SUM: frozenset[str] = frozenset(
    {"LevelBoundary"}
)

# Observation flow variables and the link direction they sum over.
# ``inflow_rate`` sums incoming flow links; ``outflow_rate`` sums outgoing.
_OBSERVATION_FLOW_DIRECTION: dict[str, str] = {
    "inflow_rate": "to",
    "outflow_rate": "from",
}

RIBASIM_HOME_SETTING = "ribasim/home"
RIBASIM_LAST_MODEL_PATH_SETTING = "ribasim/last_model_path"

_ANSI_ESCAPE_RE = re.compile(r"\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1B\\))")


def _strip_ansi_escape_codes(text: str) -> str:
    """Remove ANSI terminal escape codes from CLI output for plaintext display.

    Ribasim writes terminal styling sequences (colors, bold, etc.).
    Because ``QPlainTextEdit`` only supports plain text, we strip these
    sequences to avoid showing raw control characters in the output dialog.
    """
    return _ANSI_ESCAPE_RE.sub("", text)


class DatasetWidget:
    def __init__(self, parent: QWidget):
        from ribasim_qgis.widgets.ribasim_widget import RibasimWidget

        self.ribasim_widget = cast(RibasimWidget, parent)
        self.link_layer: QgsVectorLayer | None = None
        self.node_layer: QgsVectorLayer | None = None
        self.path: Path = Path()

        # Results
        self.flow_layer: QgsVectorLayer | None = None
        self.basin_layer: QgsVectorLayer | None = None
        self.concentration_layer: QgsVectorLayer | None = None
        self.results: dict[str, NetCDFResult] = {}

        # Observation input data (read from the GeoPackage, not the results).
        self.observations: Observations | None = None

        # Plot widget for timeseries
        self.plot_widget = PlotWidget(
            iface=self.ribasim_widget.iface,
            node_layer_getter=lambda: self.node_layer,
            link_layer_getter=lambda: self.link_layer,
            concentration_for_node_getter=self._get_concentration_for_node,
            flow_for_link_getter=self._get_flow_for_link,
        )

        # Track running simulations by model path
        self.running_tasks: dict[str, RibasimTask] = {}

        # Remove our references to layers when they are about to be deleted
        instance = QgsProject.instance()
        if instance is not None:
            instance.layersWillBeRemoved.connect(self.remove_results)

    def remove_results(self, layer_ids: list[str]) -> None:
        """Remove Python references to layers that will be deleted."""
        for attr, layer in self._layers():
            if layer is not None and layer.id() in layer_ids:
                setattr(self, attr, None)

    def _layers(self) -> list[tuple[str, QgsVectorLayer | None]]:
        """Return a list of tuples with layer names and their references."""
        return [
            ("link_layer", self.link_layer),
            ("node_layer", self.node_layer),
            ("flow_layer", self.flow_layer),
            ("basin_layer", self.basin_layer),
            ("concentration_layer", self.concentration_layer),
        ]

    def add_layer(
        self,
        layer: Any,
        destination: Any,
        on_top: bool = False,
        labels: Any = None,
    ) -> QgsMapLayer | None:
        self.ribasim_widget.add_layer(
            layer,
            destination,
            on_top,
            labels,
        )
        layer.setCustomProperty("ribasim_path", self.path.as_posix())
        return layer

    def add_item_to_qgis(self, item) -> None:
        layer, labels = item.from_geopackage()
        self.add_layer(layer, "Input", labels=labels)

    @staticmethod
    def add_relationship(from_layer, to_layer_id, name, fk="node_id") -> None:
        rel = QgsRelation()
        rel.setReferencingLayer(from_layer.id())
        rel.setReferencedLayer(to_layer_id)
        rel.setName(name)
        rel.setStrength(
            # pyrefly: ignore[missing-attribute]
            rel.RelationStrength.Composition
        )
        # Both layers use the same field name for their primary key.
        rel.addFieldPair(fk, fk)
        rel.generateId()
        instance = QgsProject.instance()
        assert instance is not None
        rel_manager = instance.relationManager()
        assert rel_manager is not None
        rel_manager.addRelation(rel)

        # Also use the relationship as an editor widget
        field_index = from_layer.fields().indexFromName(fk)
        setup = QgsEditorWidgetSetup(
            "RelationReference",
            {
                "Relation": rel.id(),
                "MapIdentification": True,
            },
        )
        from_layer.setEditorWidgetSetup(field_index, setup)

    def load_geopackage(self) -> None:
        """Load the layers of a GeoPackage into the Layers Panel."""
        geo_path = get_database_path_from_model_file(self.path)
        nodes = load_nodes_from_geopackage(geo_path)

        name = self.path.stem
        parent = self.path.parent.stem
        self.ribasim_widget.create_groups(f"{parent}/{name}")

        # Make sure "Node", "Link", "Basin / area" are the top three layers
        node = nodes.pop("Node")
        self.add_item_to_qgis(node)
        # Make sure node_id shows up in relationships
        node.layer.setDisplayExpression("node_id")

        link = nodes.pop("Link")
        self.add_item_to_qgis(link)

        # Add the remaining layers
        for table_name, node_layer in nodes.items():
            self.add_item_to_qgis(node_layer)
            self.add_relationship(node_layer.layer, node.layer.id(), table_name)

        # Connect node and link layer to derive connectivities.
        self.node_layer = node.layer
        assert self.node_layer is not None
        self.link_layer = link.layer

        def filterbyrel(relationships, feature_ids):
            """Filter all related tables by the selected features in the node table."""
            ids = []
            rel_for_selection = None
            selection = QgsFeatureRequest().setFilterFids(feature_ids)
            for rel in relationships:
                if rel.isValid() and rel.referencedLayer():
                    for feature in rel.referencedLayer().getFeatures(selection):
                        ids.extend(f.id() for f in rel.getRelatedFeatures(feature))
                if rel.isValid() and rel.referencingLayer() is not None:
                    rel_for_selection = rel

            if rel_for_selection is not None and rel_for_selection.referencingLayer():
                rel_for_selection.referencingLayer().selectByIds(ids)

        # When the Node selection changes, filter all related tables
        link_rels = []
        instance = QgsProject.instance()
        assert instance is not None
        rel_manager = instance.relationManager()
        assert rel_manager is not None
        for rel in rel_manager.relations().values():
            # Link relations are special, they have two references to the Node table
            referencing = rel.referencingLayer()
            referenced = rel.referencedLayer()
            assert referencing is not None
            assert referenced is not None

            if referencing.name() == "Link":
                link_rels.append(rel)
            else:
                referenced.selectionChanged.connect(partial(filterbyrel, [rel]))

        self.node_layer.selectionChanged.connect(partial(filterbyrel, link_rels))
        return

    def open_model(self, path=None) -> None:
        """Open a Ribasim model file."""
        if not path:
            last_path = self.get_last_model_path_setting()
            start_dir = last_path.parent if last_path is not None else None
            path, _ = QFileDialog.getOpenFileName(
                self.ribasim_widget,
                "Select file",
                str(start_dir) if start_dir is not None else "",
                "*.toml",
            )
        self._open_model(path)

    def _open_model(self, path: str) -> None:
        if path != "":  # Empty string in case of cancel button press
            self.path = Path(path)
            self.set_last_model_path_setting(self.path)
            self.set_current_time_extent()
            self.load_geopackage()
            self.add_topology_context()
            self.refresh_results()

    @staticmethod
    def activeGroup(iface):
        ltv = iface.layerTreeView()

        i = ltv.selectionModel().currentIndex()
        if not i.isValid():
            return
        group = ltv.index2node(i)
        if isinstance(group, QgsLayerTreeGroup):
            return group

    @staticmethod
    def is_layer_visible(layer: QgsMapLayer):
        instance = QgsProject.instance()
        assert instance is not None
        layer_tree_root = instance.layerTreeRoot()
        assert layer_tree_root is not None
        layer_tree_layer = layer_tree_root.findLayer(layer)
        if layer_tree_layer is None:
            return False
        return layer_tree_layer.isVisible()

    @staticmethod
    def set_layer_visible(layer: QgsMapLayer, visible: bool = True):
        instance = QgsProject.instance()
        assert instance is not None
        layer_tree_root = instance.layerTreeRoot()
        assert layer_tree_root is not None
        layer_tree_layer = layer_tree_root.findLayer(layer)
        if layer_tree_layer is None:
            return False
        return layer_tree_layer.setItemVisibilityChecked(visible)

    def reload_action(self, path, group) -> None:
        """Remove group, and (re)load the model in the same position."""
        parent = group.parent()
        position = parent.children().index(group)
        parent.removeChildNode(group)
        token = group_position_var.set(position)
        self._open_model(path)
        group_position_var.reset(token)

    def run_action(self, path: str, group) -> None:
        """Run Ribasim model using QgsTask with progress bar and output dialog."""
        message_bar = self.ribasim_widget.iface.messageBar()
        assert message_bar is not None

        model_path = Path(path)
        # "path/to/basic/ribasim.toml" -> "basic/ribasim"
        model_name = f"{model_path.parent.stem}/{model_path.stem}"

        # Check if simulation is already running for this model
        if path in self.running_tasks:
            message_bar.pushMessage(
                "Warning",
                f"Simulation already running for {model_name}",
                level=cast(Qgis.MessageLevel, Qgis.MessageLevel.Warning),
                duration=5,
            )
            return

        # Find ribasim CLI
        cli = self._find_ribasim_cli(message_bar)
        # If CLI is not found, an error message has already been displayed, so just return
        if cli is None:
            return

        # Create output dialog
        dialog = QDialog(self.ribasim_widget.iface.mainWindow())
        dialog.setWindowTitle(f"Ribasim simulation - {model_name}")
        dialog.resize(700, 400)
        layout = QVBoxLayout(dialog)

        # Text area for output
        text_edit = QPlainTextEdit()
        text_edit.setReadOnly(True)
        text_edit.setLineWrapMode(
            cast(QPlainTextEdit.LineWrapMode, QPlainTextEdit.LineWrapMode.NoWrap)
        )
        # Use monospace font for proper progress bar display
        font = text_edit.font()
        font.setFamily("Consolas, Monaco, monospace")
        text_edit.setFont(font)
        layout.addWidget(text_edit)

        # Create and configure the task
        task = RibasimTask(str(cli), path)

        def on_output(line: str, replace: bool):
            """Handle output from the task (called on main thread via signal)."""
            line = _strip_ansi_escape_codes(line)
            if replace:
                # Update last line instead of appending for progress updates
                cursor = text_edit.textCursor()
                cursor.movePosition(
                    cast(cursor.MoveOperation, cursor.MoveOperation.End)
                )
                cursor.select(
                    cast(cursor.SelectionType, cursor.SelectionType.LineUnderCursor)
                )
                cursor.removeSelectedText()
                cursor.insertText(line)
            else:
                text_edit.appendPlainText(line)
            # Auto-scroll to bottom
            scrollbar = text_edit.verticalScrollBar()
            assert scrollbar is not None
            scrollbar.setValue(scrollbar.maximum())

        def on_finished(success: bool):
            """Handle task completion."""
            self.running_tasks.pop(path, None)
            if success:
                text_edit.appendPlainText("\nLoading results.")
                self.reload_action(path, group)
                text_edit.appendPlainText("Finished loading results.")
            elif task.was_canceled:
                text_edit.appendPlainText("\nThe Ribasim simulation was canceled.")

        # Connect signals
        task.output_received.connect(on_output)
        task.task_completed.connect(on_finished)

        # Track and start the task
        self.running_tasks[path] = task
        task_manager = QgsApplication.taskManager()
        assert task_manager is not None
        task_manager.addTask(task)
        text_edit.appendPlainText("Launching Ribasim.\n")
        dialog.show()

    @staticmethod
    def get_ribasim_home_setting() -> Path | None:
        settings = QgsSettings()
        value = settings.value(RIBASIM_HOME_SETTING, "", type=str)
        return Path(value) if value else None

    @staticmethod
    def set_ribasim_home_setting(path: Path) -> None:
        settings = QgsSettings()
        settings.setValue(RIBASIM_HOME_SETTING, str(path))

    @staticmethod
    def clear_ribasim_home_setting() -> None:
        settings = QgsSettings()
        settings.remove(RIBASIM_HOME_SETTING)

    @staticmethod
    def get_last_model_path_setting() -> Path | None:
        settings = QgsSettings()
        value = settings.value(RIBASIM_LAST_MODEL_PATH_SETTING, "", type=str)
        return Path(value) if value else None

    @staticmethod
    def set_last_model_path_setting(path: Path) -> None:
        settings = QgsSettings()
        settings.setValue(RIBASIM_LAST_MODEL_PATH_SETTING, str(path))

    @staticmethod
    def get_ribasim_cli_from_home(ribasim_home: Path) -> Path | None:
        ribasim_exe = ribasim_home / "bin" / "ribasim"
        cli = shutil.which(ribasim_exe.name, path=str(ribasim_exe.parent))
        if cli is None:
            return None
        return Path(cli)

    @staticmethod
    def get_windows_apps_cli() -> Path | None:
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data is None:
            return None
        windows_apps = Path(local_app_data) / "Microsoft" / "WindowsApps"
        cli = shutil.which("ribasim", path=str(windows_apps))
        if cli is None:
            return None
        return Path(cli)

    @classmethod
    def _find_ribasim_cli(cls, message_bar) -> Path | None:
        """Find the Ribasim CLI executable.

        Checks the following locations in order:

        1. The Ribasim home directory configured in QGIS settings.
        2. The RIBASIM_HOME environment variable.
        3. The system PATH.
        4. `%LOCALAPPDATA%/Microsoft/WindowsApps` on Windows.

        This is useful when QGIS does not inherit the user's PATH environment
        variable, which happens in the default Windows installation.

        Parameters
        ----------
        message_bar
            QGIS message bar to display errors.

        Returns
        -------
        Path | None
            Path to the Ribasim CLI executable, or None if not found.
        """
        # Check plugin setting first
        if (ribasim_home_setting := cls.get_ribasim_home_setting()) is not None:
            cli = cls.get_ribasim_cli_from_home(ribasim_home_setting)
            if cli is None:
                message_bar.pushMessage(
                    "Error",
                    "Ribasim not found at configured Ribasim home. "
                    "Please update it via Plugins > Ribasim > Set Ribasim home.",
                    level=Qgis.MessageLevel.Critical,
                )
                return None
            return cli

        # Check RIBASIM_HOME environment variable
        if (ribasim_home_env := os.environ.get("RIBASIM_HOME")) is not None:
            ribasim_home = Path(ribasim_home_env)
            cli = cls.get_ribasim_cli_from_home(ribasim_home)
            if cli is None:
                message_bar.pushMessage(
                    "Error",
                    f"Ribasim not found at RIBASIM_HOME='{ribasim_home.resolve()}'. "
                    "Please ensure the path is correct.",
                    level=Qgis.MessageLevel.Critical,
                )
                return None
            return cli

        # Fall back to searching the PATH
        cli_str = shutil.which("ribasim")
        if cli_str is not None:
            return Path(cli_str)

        # Additional fallback for Windows MSIX installs
        if (windows_apps_cli := cls.get_windows_apps_cli()) is not None:
            return windows_apps_cli

        message_bar.pushMessage(
            "Error",
            "Ribasim not found. "
            "Please ensure Ribasim is installed and available on your PATH, "
            "configure Ribasim home in the plugin, "
            "or set the RIBASIM_HOME environment variable.",
            level=Qgis.MessageLevel.Critical,
        )
        return None

    def add_topology_context(self) -> None:
        """Connect to the layer context (right-click) menu opening."""
        ltv = self.ribasim_widget.iface.layerTreeView()
        if ltv is not None:
            ltv.contextMenuAboutToShow.connect(self.generate_topology_action)

    def generate_topology_action(self, menu: QMenu) -> None:
        """Generate checkable show topology action in the context menu."""
        for action in menu.actions():
            if action.text() == "Show topology":
                return

        layer = self.ribasim_widget.iface.activeLayer()
        if (
            not layer
            or layer.type() != Qgis.LayerType.Vector
            or ("Link" not in layer.name() and "Flow" not in layer.name())
        ):
            return

        # We store the state as a variable in the layer context (properties->variables)
        # This variable can be used by the layers style to show the topology.
        scope = QgsExpressionContextUtils.layerScope(layer)
        checked = scope is not None and scope.variable("layer_topology") == "True"

        # Always add action, as it lives only during this context menu
        menu.addSeparator()
        action = menu.addAction("Show topology")
        action.setCheckable(True)
        action.setChecked(checked)
        action.triggered.connect(self.show_topology)

    def show_topology(self, checked: bool) -> None:
        """Set the topology switch variable and redraw the layer."""
        layer = self.ribasim_widget.iface.activeLayer()
        if layer is None:
            return

        value = "True" if checked else "False"
        QgsExpressionContextUtils.setLayerVariable(
            layer,
            "layer_topology",
            value,
        )
        layer.triggerRepaint()

    def refresh_results(self) -> None:
        self._load_netcdf_results()
        self._load_observations()
        self._preload_plot_variables()
        self._set_node_results()
        self._set_link_results()
        canvas = self.ribasim_widget.iface.mapCanvas()
        assert canvas is not None
        temporalController = canvas.temporalController()
        assert temporalController is not None
        temporalController.updateTemporalRange.connect(self._update_result_layers)

        # Connect node/link selection to plot updates
        if self.node_layer is not None:
            self.node_layer.selectionChanged.connect(self._update_plot_from_selection)
        if self.link_layer is not None:
            self.link_layer.selectionChanged.connect(self._update_plot_from_selection)

    def get_current_time(self) -> datetime:
        """Retrieve the current (frame) time from the temporal controller."""
        canvas = self.ribasim_widget.iface.mapCanvas()
        assert canvas is not None
        temporalController = canvas.temporalController()
        assert temporalController is not None
        temporalController = cast(QgsTemporalNavigationObject, temporalController)
        f = temporalController.currentFrameNumber()
        currentDateTimeRange = temporalController.dateTimeRangeForFrameNumber(f)
        return currentDateTimeRange.begin().toPyDateTime()

    def set_current_time_extent(self) -> None:
        """Set the current time extent and interval of the temporal controller."""
        toml = get_toml_dict(self.path)

        canvas = self.ribasim_widget.iface.mapCanvas()
        assert canvas is not None
        temporalController = canvas.temporalController()
        assert temporalController is not None
        temporalController = cast(QgsTemporalNavigationObject, temporalController)

        trange = QgsDateTimeRange(
            QDateTime(toml["starttime"]), QDateTime(toml["endtime"])
        )
        canvas.setTemporalRange(trange)
        temporalController.setTemporalExtents(trange)
        temporalController.setFrameDuration(
            QgsInterval(toml.get("solver", {}).get("timestep", 86400))
        )
        canvas.setTemporalController(temporalController)

    def _results_dir(self) -> Path:
        return get_directory_path_from_model_file(
            self.ribasim_widget.path, property="results_dir"
        )

    def _load_netcdf_results(self) -> None:
        """Load all NetCDF result files into self.results."""
        results_dir = self._results_dir()
        readers = {
            "basin": read_basin_nc,
            "flow": read_flow_nc,
            "concentration": read_concentration_nc,
        }
        for name, reader in readers.items():
            result = reader(results_dir / f"{name}.nc")
            if result is not None:
                self.results[name] = result

    def _load_observations(self) -> None:
        """Load Observation input data from the GeoPackage into self.observations."""
        self.observations = read_observations(
            get_database_path_from_model_file(self.ribasim_widget.path)
        )

    def _observation_units(self) -> dict[str, str]:
        """Map each observation variable to a unit borrowed from the results.

        Observed and simulated series share a variable name, so reusing the
        result unit guarantees they land on the same unit-grouped subplot.
        """
        if self.observations is None:
            return {}
        units: dict[str, str] = {}
        for variable in self.observations.variables:
            for result in self.results.values():
                if variable in result.units:
                    units[variable] = result.units[variable]
                    break
        return units

    def _preload_plot_variables(self) -> None:
        """Pre-populate the plot widget dropdowns from loaded results."""
        available: dict[str, list[str]] = {}
        units: dict[str, dict[str, str]] = {}
        defaults = dict(_DEFAULT_VARIABLES)
        for name, result in self.results.items():
            available[name] = list(result.variables.keys())
            units[name] = result.units
        if self.observations is not None and self.observations.variables:
            available["observation"] = sorted(self.observations.variables)
            units["observation"] = self._observation_units()
            # Default observation variables on, so their root group is checked
            # even without results (when it is the group's only constituent).
            defaults["observation"] = available["observation"]
        self.plot_widget.preload_variables(available, units, defaults)
        self._set_plot_simulated_period()

    def _set_plot_simulated_period(self) -> None:
        """Tell the plot widget the simulated period to use as default x-range.

        Use the model's ``starttime``/``endtime`` from the TOML so plots open on
        the simulation window even when an observed series extends beyond it.
        """
        toml = get_toml_dict(self.path)
        self.plot_widget.set_simulated_period(
            toml["starttime"].strftime(TIME_FORMAT),
            toml["endtime"].strftime(TIME_FORMAT),
        )

    def _get_concentration_for_node(self, node_id: int) -> dict[str, Trace] | None:
        """Return concentration traces for a single *node_id*."""
        result = self.results.get("concentration")
        if result is None:
            return None
        id_to_idx = {int(v): i for i, v in enumerate(result.ids)}
        idx = id_to_idx.get(node_id)
        if idx is None:
            return None
        time_strings = result.time_strings
        return {
            sub: (time_strings, arr[:, idx]) for sub, arr in result.variables.items()
        }

    def _get_flow_for_link(self, link_id: int) -> Trace | None:
        """Return the flow_rate trace for a single *link_id*."""
        result = self.results.get("flow")
        if result is None:
            return None
        flow_arr = result.variables.get("flow_rate")
        if flow_arr is None:
            return None
        id_to_idx = {int(v): i for i, v in enumerate(result.ids)}
        idx = id_to_idx.get(link_id)
        if idx is None:
            return None
        time_strings = result.time_strings
        return (time_strings, flow_arr[:, idx])

    def _set_node_results(self) -> None:
        node_layer = self.ribasim_widget.node_layer
        assert node_layer is not None

        result = self.results.get("basin")
        if result is not None:
            self.basin_layer = self._duplicate_layer(
                node_layer, "Basin", "node_id", "node_type", "Basin"
            )
            assert self.basin_layer is not None
            self._edit_result_layer(result, self.basin_layer)
            self.add_relationship(
                self.basin_layer, node_layer.id(), "BasinResult", fk="node_id"
            )
            self._sync_selection_to_result(node_layer, self.basin_layer, "node_id")

        result = self.results.get("concentration")
        if result is not None:
            self.concentration_layer = self._duplicate_layer(
                node_layer, "Concentration", "node_id", "node_type", "Basin"
            )
            assert self.concentration_layer is not None
            self._edit_result_layer(result, self.concentration_layer)
            self.add_relationship(
                self.concentration_layer,
                node_layer.id(),
                "ConcentrationResult",
                fk="node_id",
            )
            self._sync_selection_to_result(
                node_layer, self.concentration_layer, "node_id"
            )

    def _set_link_results(self) -> None:
        link_layer = self.ribasim_widget.link_layer
        assert link_layer is not None

        result = self.results.get("flow")
        if result is not None:
            self.flow_layer = self._duplicate_layer(
                link_layer, "Flow", "link_id", "link_type", "flow"
            )
            assert self.flow_layer is not None
            self.set_layer_visible(self.flow_layer, True)
            self._edit_result_layer(result, self.flow_layer)
            self.add_relationship(
                self.flow_layer, link_layer.id(), "FlowResult", fk="link_id"
            )
            self._sync_selection_to_result(link_layer, self.flow_layer, "link_id")

    @staticmethod
    def _sync_selection_to_result(
        source_layer: QgsVectorLayer,
        result_layer: QgsVectorLayer,
        fk: str,
    ) -> None:
        """Mirror the selection in *source_layer* to *result_layer*.

        Selecting Node/Link features in the (possibly hidden) input layer
        highlights the corresponding Basin/Flow features in the spatial
        results, so users can see which ones are selected via the standard
        QGIS yellow highlight.
        """

        def on_selection_changed(_selected_fids: list[int]) -> None:
            try:
                fk_values = {int(feat[fk]) for feat in source_layer.selectedFeatures()}
            except RuntimeError:
                # source_layer was deleted underneath us.
                return
            if not fk_values:
                with contextlib.suppress(RuntimeError):
                    result_layer.removeSelection()
                return
            expr = f'"{fk}" IN ({",".join(str(v) for v in fk_values)})'
            request = QgsFeatureRequest().setFilterExpression(expr)
            try:
                target_fids = [feat.id() for feat in result_layer.getFeatures(request)]  # pyrefly: ignore[not-iterable]
                result_layer.selectByIds(target_fids)
            except RuntimeError:
                return

        source_layer.selectionChanged.connect(on_selection_changed)

    def _duplicate_layer(
        self,
        layer,
        name,
        fid_column,
        filterkey: str | int = 1,
        filtervalue: str | int = 1,
        fids=None,
    ):
        """Duplicate a layer for use with output data."""
        if fids is None:
            duplicate = layer.materialize(
                QgsFeatureRequest().setFilterExpression(
                    f"{filterkey} = '{filtervalue}'"
                )
            )
        else:
            duplicate = layer.materialize(QgsFeatureRequest().setFilterFids(fids))

        duplicate.setName(name)
        fn = STYLE_DIR / f"{name}Style.qml"
        if fn.exists():
            duplicate.loadNamedStyle(str(fn))

        # The fids of a duplicated layer in memory are not the same
        # as our node/link_ids anymore, and can't be set as such.
        # To update the layer with result data we need to guarantee
        # both types of ids are sorted, so we can use the new fids.
        fids = []
        rids = []
        for feature in duplicate.getFeatures():
            fids.append(feature.id())
            rids.append(feature[fid_column])
        if sorted(fids) != fids or sorted(rids) != rids:
            message_bar = self.ribasim_widget.iface.messageBar()
            if message_bar is not None:
                message_bar.pushMessage(
                    "Ribasim",
                    "Cannot duplicate layer, fids are not sorted",
                    level=cast(Qgis.MessageLevel, Qgis.MessageLevel.Critical),
                    duration=3,
                )
            return

        maplayer = self.add_layer(duplicate, "Results", False, labels=None)
        if maplayer is None:
            return
        self.set_layer_visible(duplicate, False)

        toml = get_toml_dict(self.path)
        trange = QgsDateTimeRange(
            QDateTime(toml["starttime"]), QDateTime(toml["endtime"])
        )
        tprop = cast(QgsVectorLayerTemporalProperties, maplayer.temporalProperties())
        tprop.setMode(
            QgsVectorLayerTemporalProperties.TemporalMode.ModeFixedTemporalRange  # pyrefly: ignore[missing-attribute]
        )
        tprop.setFixedTemporalRange(trange)
        tprop.setIsActive(True)

        return duplicate

    def _edit_result_layer(
        self,
        result: NetCDFResult,
        layer: QgsVectorLayer,
    ) -> None:
        """Add result data columns to the layer and populate with initial time slice."""
        layer.startEditing()
        for column in result.variables:
            dataprovider = layer.dataProvider()
            if dataprovider is not None and dataprovider.fieldNameIndex(column) == -1:
                dataprovider.addAttributes(
                    [QgsField(column, cast(QMetaType.Type, QMetaType.Type.Double))]
                )
            layer.updateFields()
        layer.commitChanges()

        self._update_result_layer(layer, result, self.get_current_time(), force=True)

    def _update_result_layer(
        self,
        layer: QgsVectorLayer | None,
        result: NetCDFResult | None,
        time: datetime,
        force: bool = False,
    ) -> None:
        """Update the layer with the current time slice from results."""
        if (
            layer is None
            or result is None
            or (not force and not self.is_layer_visible(layer))
        ):
            return

        # Find nearest time index via searchsorted
        time_idx = int(result.time.searchsorted(time))
        if time_idx >= len(result.time):
            if force:
                time_idx = len(result.time) - 1
            else:
                print(f"Skipping update, out of bounds for {time}")
                return

        layer.startEditing()
        layer.beginEditCommand("Group all undos for performance.")

        fids = sorted(layer.allFeatureIds())
        n_ids = len(result.ids)
        if len(fids) != n_ids:
            print(f"Can't join data at {time}, shapes of layer and result differ.")
            layer.endEditCommand()
            layer.commitChanges()
            return

        dataprovider = layer.dataProvider()
        assert dataprovider is not None

        # Build column-id mapping once
        col_ids: dict[str, int] = {}
        for col_name in result.variables:
            col_id = dataprovider.fieldNameIndex(col_name)
            if col_id >= 0:
                col_ids[col_name] = col_id

        # Build data dict: {feature_id: {field_id: value}}
        data: dict[int, dict[int, float]] = {}
        for j, fid in enumerate(fids):
            attrs: dict[int, float] = {}
            for col_name, col_id in col_ids.items():
                attrs[col_id] = float(result.variables[col_name][time_idx, j])
            data[fid] = attrs

        dataprovider.changeAttributeValues(data)

        layer.endEditCommand()
        layer.commitChanges()

    def _update_result_layers(self, timerange: QgsDateTimeRange) -> None:
        """Update the result layers with the current time slice."""
        if timerange.isEmpty() or timerange.isInfinite():
            return

        time = timerange.begin().toPyDateTime()
        self._update_result_layer(self.basin_layer, self.results.get("basin"), time)
        self._update_result_layer(self.flow_layer, self.results.get("flow"), time)
        self._update_result_layer(
            self.concentration_layer,
            self.results.get("concentration"),
            time,
        )

    def _update_plot_from_selection(self, selected_ids: list[int]) -> None:
        """Update the plot widget when nodes or links are selected on the map.

        Produces data grouped by result file, then by variable, then by trace.
        Structure: {file: {variable: {trace_name: (x, y)}}}
        """
        plot_data: PlotData = {}

        node_layer = self.ribasim_widget.node_layer
        link_layer = self.ribasim_widget.link_layer

        # Gather selected nodes as (node_id, node_type) tuples.
        selected_nodes: list[tuple[int, str]] = []
        if node_layer is not None:
            for fid in node_layer.selectedFeatureIds():
                feat = node_layer.getFeature(fid)
                selected_nodes.append((int(feat["node_id"]), str(feat["node_type"])))

        selected_node_ids = [node_id for node_id, _ in selected_nodes]

        # Gather selected link IDs
        selected_link_ids: list[int] = []
        if link_layer is not None:
            for fid in link_layer.selectedFeatureIds():
                feat = link_layer.getFeature(fid)
                selected_link_ids.append(feat["link_id"])

        selected_ids_by_column = {
            "node_id": selected_node_ids,
            "link_id": selected_link_ids,
        }
        for name, result in self.results.items():
            id_col = _ID_COLUMNS.get(name, "node_id")
            ids = selected_ids_by_column.get(id_col, [])
            if not ids:
                continue

            entity = _ENTITY_BY_FILE.get(name, "")
            # Build id -> column-index mapping (O(1) lookup)
            id_to_idx = {int(v): i for i, v in enumerate(result.ids)}
            time_strings = result.time_strings

            vars_data: dict[str, VariableTraces] = {}
            for var_name, arr in result.variables.items():
                traces: VariableTraces = {}
                for sel_id in ids:
                    idx = id_to_idx.get(sel_id)
                    if idx is not None:
                        trace_key = f"{entity} #{sel_id}" if entity else f"#{sel_id}"
                        traces[trace_key] = (time_strings, arr[:, idx])
                if traces:
                    vars_data[var_name] = traces

            if vars_data:
                plot_data[name] = vars_data

        # Inject flow_rate traces derived from outgoing links for selected
        # non-Basin conservative nodes (e.g. TabulatedRatingCurve).
        self._inject_node_flow_rate_traces(plot_data, selected_nodes, link_layer)

        # Inject observed (input) and matching simulated traces for selected
        # Observation nodes.
        self._inject_observation_traces(plot_data, selected_nodes, link_layer)

        # Collect units from results
        units: dict[str, dict[str, str]] = {
            name: result.units for name, result in self.results.items()
        }
        if self.observations is not None and self.observations.variables:
            units["observation"] = self._observation_units()
        if plot_data:
            self.plot_widget.set_data(plot_data, units)
        else:
            self.plot_widget.clear()

    def _inject_node_flow_rate_traces(
        self,
        plot_data: PlotData,
        selected_nodes: list[tuple[int, str]],
        link_layer: Any,
    ) -> None:
        """Add flow.nc flow_rate traces for selected non-Basin nodes.

        Four cases:

        * Conservative single-link nodes (e.g. ``TabulatedRatingCurve``):
          show the outgoing flow link as the node's flow_rate.
        * Non-conservative single-link nodes (e.g. ``UserDemand``): show
          the incoming and outgoing flow links separately.
        * Multi-link inflow-only nodes (``Terminal``, ``Junction``): show
          the sum of all incoming flow links.
        * Multi-link non-conservative nodes (``LevelBoundary``): show the
          sum of incoming and the sum of outgoing flow links separately.
        """
        flow_result = self.results.get("flow")
        if flow_result is None or link_layer is None:
            return
        flow_arr = flow_result.variables.get("flow_rate")
        if flow_arr is None:
            return

        link_id_to_idx = {int(v): i for i, v in enumerate(flow_result.ids)}
        time_strings = flow_result.time_strings

        new_traces: VariableTraces = {}
        for node_id, node_type in selected_nodes:
            if node_type in _FLOW_RATE_FROM_OUTGOING_LINK:
                outgoing = self._connected_flow_columns(
                    link_layer, node_id, "from", link_id_to_idx, flow_arr
                )
                if outgoing:
                    new_traces[f"{node_type} #{node_id} flow_rate"] = (
                        time_strings,
                        outgoing[0],
                    )
            elif node_type in _FLOW_RATE_FROM_INCOMING_AND_OUTGOING_LINKS:
                incoming = self._connected_flow_columns(
                    link_layer, node_id, "to", link_id_to_idx, flow_arr
                )
                outgoing = self._connected_flow_columns(
                    link_layer, node_id, "from", link_id_to_idx, flow_arr
                )
                if incoming:
                    new_traces[f"{node_type} #{node_id} inflow_rate"] = (
                        time_strings,
                        incoming[0],
                    )
                if outgoing:
                    new_traces[f"{node_type} #{node_id} outflow_rate"] = (
                        time_strings,
                        outgoing[0],
                    )
            elif node_type in _FLOW_RATE_FROM_INCOMING_LINKS_SUM:
                incoming = self._connected_flow_columns(
                    link_layer, node_id, "to", link_id_to_idx, flow_arr
                )
                if incoming:
                    new_traces[f"{node_type} #{node_id} inflow_rate"] = (
                        time_strings,
                        np.sum(incoming, axis=0),
                    )
            elif node_type in _FLOW_RATE_FROM_INCOMING_AND_OUTGOING_LINKS_SUM:
                incoming = self._connected_flow_columns(
                    link_layer, node_id, "to", link_id_to_idx, flow_arr
                )
                outgoing = self._connected_flow_columns(
                    link_layer, node_id, "from", link_id_to_idx, flow_arr
                )
                if incoming:
                    new_traces[f"{node_type} #{node_id} inflow_rate"] = (
                        time_strings,
                        np.sum(incoming, axis=0),
                    )
                if outgoing:
                    new_traces[f"{node_type} #{node_id} outflow_rate"] = (
                        time_strings,
                        np.sum(outgoing, axis=0),
                    )

        if not new_traces:
            return
        flow_vars = plot_data.setdefault("flow", {})
        flow_rate_traces = flow_vars.setdefault("flow_rate", {})
        flow_rate_traces.update(new_traces)

    @staticmethod
    def _connected_flow_columns(
        link_layer: Any,
        node_id: int,
        direction: str,
        link_id_to_idx: dict[int, int],
        flow_arr: np.ndarray,
    ) -> list[np.ndarray]:
        """Return flow_rate columns for flow links connected to *node_id*.

        *direction* is ``"from"`` for outgoing links (``from_node_id``) and
        ``"to"`` for incoming links (``to_node_id``).
        """
        column = "from_node_id" if direction == "from" else "to_node_id"
        request = QgsFeatureRequest().setFilterExpression(
            f'"{column}" = {node_id} AND "link_type" = \'flow\''
        )
        columns: list[np.ndarray] = []
        for feat in link_layer.getFeatures(request):
            idx = link_id_to_idx.get(int(feat["link_id"]))
            if idx is not None:
                columns.append(flow_arr[:, idx])
        return columns

    def _inject_observation_traces(
        self,
        plot_data: PlotData,
        selected_nodes: list[tuple[int, str]],
        link_layer: Any,
    ) -> None:
        """Add observed (input) and simulated traces for selected Observation nodes.

        For each selected Observation node we plot, per observed variable, the
        observed series read from the GeoPackage together with the matching
        simulated series from the results of the observed target node. Observed
        and simulated traces share the same ``("observation", variable)`` key so
        a single dropdown entry toggles both. When no matching simulated series
        is available (e.g. results not loaded), only the observed series is
        shown.
        """
        if self.observations is None:
            return

        node_layer = self.ribasim_widget.node_layer
        for node_id, node_type in selected_nodes:
            if node_type != "Observation":
                continue
            node_data = self.observations.data.get(node_id)
            if not node_data:
                continue

            target_id = self._observation_target_node_id(link_layer, node_id)
            target_type = (
                self._node_type_of(node_layer, target_id)
                if target_id is not None
                else None
            )

            for variable, (times, values) in node_data.items():
                var_traces = plot_data.setdefault("observation", {}).setdefault(
                    variable, {}
                )
                var_traces[f"Observation #{node_id} observed {variable}"] = (
                    times,
                    values,
                )
                simulated: Trace | None = None
                if target_id is not None:
                    simulated = self._simulated_observation_trace(
                        target_id, target_type, variable, link_layer
                    )
                if simulated is not None:
                    var_traces[f"Observation #{node_id} simulated {variable}"] = (
                        simulated
                    )

    def _simulated_observation_trace(
        self,
        target_id: int,
        target_type: str | None,
        variable: str,
        link_layer: Any,
    ) -> Trace | None:
        """Return the simulated series of *variable* for the observed target node.

        Node-indexed results (e.g. Basin ``level``, ``inflow_rate``) are looked
        up directly by node_id. Flow variables on connector nodes are derived
        from the connected flow links of ``flow.nc``.
        """
        # Node-indexed results: direct lookup by node_id.
        basin_result = self.results.get("basin")
        if basin_result is not None and variable in basin_result.variables:
            id_to_idx = {int(v): i for i, v in enumerate(basin_result.ids)}
            idx = id_to_idx.get(target_id)
            if idx is not None:
                return (
                    basin_result.time_strings,
                    basin_result.variables[variable][:, idx],
                )

        # Flow variables: derive from connected flow links.
        flow_result = self.results.get("flow")
        if (
            flow_result is not None
            and link_layer is not None
            and target_type is not None
        ):
            flow_arr = flow_result.variables.get("flow_rate")
            if flow_arr is not None:
                link_id_to_idx = {int(v): i for i, v in enumerate(flow_result.ids)}
                column = self._observation_flow_column(
                    link_layer,
                    target_id,
                    target_type,
                    variable,
                    link_id_to_idx,
                    flow_arr,
                )
                if column is not None:
                    return (flow_result.time_strings, column)

        return None

    def _observation_flow_column(
        self,
        link_layer: Any,
        target_id: int,
        target_type: str,
        variable: str,
        link_id_to_idx: dict[int, int],
        flow_arr: np.ndarray,
    ) -> np.ndarray | None:
        """Return the summed flow_rate column for a flow observation variable.

        ``inflow_rate`` and ``outflow_rate`` sum incoming resp. outgoing flow
        links. Plain ``flow_rate`` is only meaningful for conservative nodes and
        is taken from the relevant single link direction.
        """
        direction = _OBSERVATION_FLOW_DIRECTION.get(variable)
        if direction is not None:
            columns = self._connected_flow_columns(
                link_layer, target_id, direction, link_id_to_idx, flow_arr
            )
            return np.sum(columns, axis=0) if columns else None

        if variable == "flow_rate":
            # A conservative node's flow_rate equals its single connected flow
            # link: outgoing for source-style nodes, incoming for sink-style.
            if target_type in _FLOW_RATE_FROM_OUTGOING_LINK:
                columns = self._connected_flow_columns(
                    link_layer, target_id, "from", link_id_to_idx, flow_arr
                )
            elif target_type in _FLOW_RATE_FROM_INCOMING_LINKS_SUM:
                columns = self._connected_flow_columns(
                    link_layer, target_id, "to", link_id_to_idx, flow_arr
                )
            else:
                return None
            return np.sum(columns, axis=0) if columns else None

        return None

    @staticmethod
    def _observation_target_node_id(link_layer: Any, node_id: int) -> int | None:
        """Return the node_id observed by Observation *node_id*, if any.

        An Observation node connects to at most one other node via an
        ``observation`` link (from the Observation node to the target).
        """
        if link_layer is None:
            return None
        request = QgsFeatureRequest().setFilterExpression(
            f'"from_node_id" = {node_id} AND "link_type" = \'observation\''
        )
        for feat in link_layer.getFeatures(request):
            return int(feat["to_node_id"])
        return None

    @staticmethod
    def _node_type_of(node_layer: Any, node_id: int) -> str | None:
        """Return the node_type of *node_id* from the node layer, if found."""
        if node_layer is None:
            return None
        request = QgsFeatureRequest().setFilterExpression(f'"node_id" = {node_id}')
        for feat in node_layer.getFeatures(request):
            return str(feat["node_type"])
        return None
