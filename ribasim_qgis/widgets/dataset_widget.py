"""
A widget that displays the available input layers in the GeoPackage.

It also allows enabling or disabling individual elements for a computation.
"""

import os
import shutil
from contextvars import ContextVar
from datetime import datetime
from functools import partial
from pathlib import Path
from typing import Any, cast

from PyQt5.QtCore import QDateTime, QMetaType
from PyQt5.QtWidgets import (
    QDialog,
    QFileDialog,
    QMenu,
    QPlainTextEdit,
    QVBoxLayout,
    QWidget,
)
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

from ribasim_qgis.core.model import (
    get_database_path_from_model_file,
    get_directory_path_from_model_file,
    get_toml_dict,
)
from ribasim_qgis.core.netcdf import (
    NetCDFResult,
    read_basin_nc,
    read_concentration_nc,
    read_flow_nc,
)
from ribasim_qgis.core.nodes import (
    STYLE_DIR,
    load_external_input_tables,
    load_nodes_from_geopackage,
)
from ribasim_qgis.widgets.plot_widget import PlotData, PlotWidget, VariableTraces
from ribasim_qgis.widgets.task import RibasimTask

group_position_var: ContextVar[int] = ContextVar("group_position", default=0)

# Mapping from result file name to its id column.
_ID_COLUMNS: dict[str, str] = {
    "basin": "node_id",
    "flow": "link_id",
    "concentration": "node_id",
}

# Default variable to select per file when no previous selection exists.
_DEFAULT_VARIABLES: dict[str, str] = {
    "basin": "level",
    "flow": "flow_rate",
    "concentration": "Initial",
}

RIBASIM_HOME_SETTING = "ribasim/home"


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

        # Plot widget for timeseries
        self.plot_widget = PlotWidget()

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
        rel.setStrength(rel.RelationStrength.Composition)  # type: ignore
        rel.addFieldPair(fk, "node_id")
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

        # Also load external input files (NetCDF)
        external_nodes = load_external_input_tables(self.path)
        nodes.update(external_nodes)

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
        self.add_relationship(
            link.layer, node.layer.id(), "LinkFromNode", "from_node_id"
        )
        self.add_relationship(link.layer, node.layer.id(), "LinkToNode", "to_node_id")

        # Add the remaining layers (both database and external) in alphabetical order
        for table_name in sorted(nodes.keys()):
            node_layer = nodes[table_name]
            self.add_item_to_qgis(node_layer)

            # External NetCDF layers can be invalid or lack the expected foreign key;
            # only set up relationships when the layer is valid and has the "node_id" field.
            layer = node_layer.layer
            if layer is None or not layer.isValid():
                continue

            fk_field_name = "node_id"
            if layer.fields().indexOf(fk_field_name) == -1:
                continue

            self.add_relationship(layer, node.layer.id(), table_name)

        # Connect node and link layer to derive connectivities.
        self.node_layer = node.layer
        assert self.node_layer is not None
        self.link_layer = link.layer

        def filterbyrel(relationships, feature_ids):
            """Filter all related tables by the selected features in the node table."""
            ids = []
            selection = QgsFeatureRequest().setFilterFids(feature_ids)
            for rel in relationships:
                if rel.isValid() and rel.referencedLayer():
                    for feature in rel.referencedLayer().getFeatures(selection):
                        ids.extend(f.id() for f in rel.getRelatedFeatures(feature))

            if rel.isValid() and rel.referencingLayer():
                rel.referencingLayer().selectByIds(ids)

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
            path, _ = QFileDialog.getOpenFileName(
                self.ribasim_widget, "Select file", "", "*.toml"
            )
        self._open_model(path)

    def _open_model(self, path: str) -> None:
        if path != "":  # Empty string in case of cancel button press
            self.path = Path(path)
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
                level=Qgis.MessageLevel.Warning,
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
        text_edit.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        # Use monospace font for proper progress bar display
        font = text_edit.font()
        font.setFamily("Consolas, Monaco, monospace")
        text_edit.setFont(font)
        layout.addWidget(text_edit)

        # Create and configure the task
        task = RibasimTask(str(cli), path)

        def on_output(line: str, replace: bool):
            """Handle output from the task (called on main thread via signal)."""
            if replace:
                # Update last line instead of appending for progress updates
                cursor = text_edit.textCursor()
                cursor.movePosition(cursor.MoveOperation.End)
                cursor.select(cursor.SelectionType.LineUnderCursor)
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
        value = settings.value(RIBASIM_HOME_SETTING)
        if not isinstance(value, str) or not value:
            return None
        return Path(value)

    @staticmethod
    def set_ribasim_home_setting(path: Path) -> None:
        settings = QgsSettings()
        settings.setValue(RIBASIM_HOME_SETTING, str(path))

    @staticmethod
    def clear_ribasim_home_setting() -> None:
        settings = QgsSettings()
        settings.remove(RIBASIM_HOME_SETTING)

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

    def _preload_plot_variables(self) -> None:
        """Pre-populate the plot widget dropdowns from loaded results."""
        available: dict[str, list[str]] = {}
        units: dict[str, dict[str, str]] = {}
        for name, result in self.results.items():
            available[name] = list(result.variables.keys())
            units[name] = result.units
        self.plot_widget.preload_variables(available, units, _DEFAULT_VARIABLES)

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

        result = self.results.get("concentration")
        if result is not None:
            self.concentration_layer = self._duplicate_layer(
                node_layer, "Concentration", "node_id", "node_type", "Basin"
            )
            assert self.concentration_layer is not None
            self._edit_result_layer(result, self.concentration_layer)

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

    def _duplicate_layer(
        self, layer, name, fid_column, filterkey=1, filtervalue=1, fids=None
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
            self.ribasim_widget.iface.messageBar().pushMessage(
                "Ribasim",
                "Cannot duplicate layer, fids are not sorted",
                level=Qgis.Critical,
                duration=3,
            )
            return

        maplayer = self.add_layer(duplicate, "Results", False, labels=None)
        self.set_layer_visible(duplicate, False)

        toml = get_toml_dict(self.path)
        trange = QgsDateTimeRange(
            QDateTime(toml["starttime"]), QDateTime(toml["endtime"])
        )
        tprop = maplayer.temporalProperties()
        tprop.setMode(QgsVectorLayerTemporalProperties.ModeFixedTemporalRange)
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
                dataprovider.addAttributes([QgsField(column, QMetaType.Type.Double)])
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

        # Gather selected node IDs
        selected_node_ids: list[int] = []
        if node_layer is not None:
            for fid in node_layer.selectedFeatureIds():
                feat = node_layer.getFeature(fid)
                selected_node_ids.append(feat["node_id"])

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

            # Build id -> column-index mapping (O(1) lookup)
            id_to_idx = {int(v): i for i, v in enumerate(result.ids)}
            time_strings = result.time.strftime("%Y-%m-%dT%H:%M:%S").to_numpy()

            vars_data: dict[str, VariableTraces] = {}
            for var_name, arr in result.variables.items():
                traces: VariableTraces = {}
                for sel_id in ids:
                    idx = id_to_idx.get(sel_id)
                    if idx is not None:
                        traces[f"#{sel_id}"] = (time_strings, arr[:, idx])
                if traces:
                    vars_data[var_name] = traces

            if vars_data:
                plot_data[name] = vars_data

        # Collect units from results
        units: dict[str, dict[str, str]] = {
            name: result.units for name, result in self.results.items()
        }
        if plot_data:
            self.plot_widget.set_data(plot_data, units)
        else:
            self.plot_widget.clear()
