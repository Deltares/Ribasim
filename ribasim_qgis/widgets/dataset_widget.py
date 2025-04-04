"""
A widget that displays the available input layers in the GeoPackage.

It also allows enabling or disabling individual elements for a computation.
"""

from __future__ import annotations

from datetime import datetime
from functools import partial
from pathlib import Path
from typing import Any, cast

import pandas as pd
from osgeo import ogr
from PyQt5.QtCore import Qt, QVariant
from PyQt5.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QFileDialog,
    QHBoxLayout,
    QLineEdit,
    QMenu,
    QMessageBox,
    QPushButton,
    QSizePolicy,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)
from qgis.core import (
    Qgis,
    QgsDateTimeRange,
    QgsEditorWidgetSetup,
    QgsExpressionContextUtils,
    QgsFeatureRequest,
    QgsField,
    QgsInterval,
    QgsMapLayer,
    QgsProject,
    QgsRelation,
    QgsVectorLayer,
)

from ribasim_qgis.core.geopackage import write_schema_version
from ribasim_qgis.core.model import (
    get_database_path_from_model_file,
    get_directory_path_from_model_file,
    get_toml_dict,
)
from ribasim_qgis.core.nodes import (
    STYLE_DIR,
    Input,
    Link,
    Node,
    load_nodes_from_geopackage,
)
from ribasim_qgis.core.topology import set_link_properties


class DatasetTreeWidget(QTreeWidget):
    def __init__(self, parent: QWidget | None):
        super().__init__(parent)
        self.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.setHeaderHidden(True)
        self.setSortingEnabled(True)
        self.setSizePolicy(QSizePolicy.Minimum, QSizePolicy.Preferred)
        self.setHeaderLabels(["  Layer"])
        self.setHeaderHidden(False)
        self.setColumnCount(1)

    def items(self) -> list[QTreeWidgetItem]:
        root = self.invisibleRootItem()
        return [root.child(i) for i in range(root.childCount())]

    def add_item(self, name: str) -> QTreeWidgetItem:
        item = QTreeWidgetItem()
        self.addTopLevelItem(item)
        item.setText(0, name)
        return item

    def add_node_layer(self, element: Input) -> QTreeWidgetItem:
        # These are mandatory elements, cannot be unticked
        item = self.add_item(name=element.input_type())
        item.element = element  # type: ignore[attr-defined]
        return item

    def remove_geopackage_layers(self) -> None:
        """Remove layers from the dataset tree widget, QGIS layer panel and the GeoPackage."""
        # Collect the selected items
        selection = self.selectedItems()

        # Warn before deletion
        message = "\n".join([f"- {item.text(0)}" for item in selection])
        reply = QMessageBox.question(
            self,
            "Deleting from Geopackage",
            f"Deleting:\n{message}",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if reply == QMessageBox.No:
            return

        # Start deleting
        elements = {item.element for item in selection}  # type: ignore[attr-defined] # TODO: dynamic item.element should be in some dict.
        project = QgsProject.instance()
        assert project is not None

        for element in elements:
            layer = element.layer
            # QGIS layers
            if layer is None:
                continue
            try:
                project.removeMapLayer(layer.id())
            except (RuntimeError, AttributeError) as e:
                if e.args[0] in (
                    "wrapped C/C++ object of type QgsVectorLayer has been deleted",
                    "'NoneType' object has no attribute 'id'",
                ):
                    pass
                else:
                    raise

            # Geopackage
            element.remove_from_geopackage()

        for item in selection:
            # Dataset tree
            index = self.indexOfTopLevelItem(item)
            self.takeTopLevelItem(index)

        return


class DatasetWidget(QWidget):
    def __init__(self, parent: QWidget):
        from ribasim_qgis.widgets.ribasim_widget import RibasimWidget

        super().__init__(parent)

        self.ribasim_widget = cast(RibasimWidget, parent)
        self.dataset_tree = DatasetTreeWidget(self)
        self.dataset_tree.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Expanding)
        self.dataset_line_edit = QLineEdit()
        self.dataset_line_edit.setEnabled(False)  # Just used as a viewing port
        self.new_model_button = QPushButton("New")
        self.open_model_button = QPushButton("Open")
        self.remove_button = QPushButton("Remove from Dataset")
        self.add_button = QPushButton("Add to QGIS")
        self.new_model_button.clicked.connect(self.new_model)
        self.open_model_button.clicked.connect(self.open_model)
        self.suppress_popup_checkbox = QCheckBox("Suppress attribute form pop-up")
        self.suppress_popup_checkbox.stateChanged.connect(self.suppress_popup_changed)
        self.remove_button.clicked.connect(self.remove_geopackage_layer)
        self.add_button.clicked.connect(self.add_selection_to_qgis)
        self.link_layer: QgsVectorLayer | None = None
        self.node_layer: QgsVectorLayer | None = None
        self.flowlink_layer: QgsVectorLayer | None = None
        self.basinnode_layer: QgsVectorLayer | None = None
        self.results: dict[str, pd.DataFrame] = {}

        # Layout
        dataset_layout = QVBoxLayout()
        dataset_row = QHBoxLayout()
        layer_row = QHBoxLayout()
        dataset_row.addWidget(self.dataset_line_edit)
        dataset_row.addWidget(self.open_model_button)
        dataset_row.addWidget(self.new_model_button)
        dataset_layout.addLayout(dataset_row)
        dataset_layout.addWidget(self.dataset_tree)
        dataset_layout.addWidget(self.suppress_popup_checkbox)
        layer_row.addWidget(self.add_button)
        layer_row.addWidget(self.remove_button)
        dataset_layout.addLayout(layer_row)
        self.setLayout(dataset_layout)

    @property
    def path(self) -> Path:
        """Returns currently active path to Ribasim model (.toml)."""
        return Path(self.dataset_line_edit.text())

    def connect_nodes(self) -> None:
        node = self.node_layer
        link = self.link_layer
        assert link is not None
        assert node is not None

        if (node.featureCount() > 0) and (link.featureCount() > 0):
            set_link_properties(node, link)

        return

    def add_layer(
        self,
        layer: Any,
        destination: Any,
        suppress: bool = False,
        on_top: bool = False,
        labels: Any = None,
    ) -> QgsMapLayer | None:
        return self.ribasim_widget.add_layer(
            layer,
            destination,
            suppress,
            on_top,
            labels,
        )

    def add_item_to_qgis(self, item) -> None:
        element = item.element
        layer, labels = element.from_geopackage()
        suppress = self.suppress_popup_checkbox.isChecked()
        self.add_layer(layer, "Ribasim Input", suppress, labels=labels)
        element.set_editor_widget()
        element.set_read_only()
        return

    def add_selection_to_qgis(self) -> None:
        selection = self.dataset_tree.selectedItems()
        for item in selection:
            self.add_item_to_qgis(item)

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
        self.dataset_tree.clear()
        geo_path = get_database_path_from_model_file(self.path)
        nodes = load_nodes_from_geopackage(geo_path)

        name = self.path.stem
        self.ribasim_widget.create_groups(name)

        # Make sure "Node", "Link", "Basin / area" are the top three layers
        node = nodes.pop("Node")
        item = self.dataset_tree.add_node_layer(node)
        self.add_item_to_qgis(item)
        # Make sure node_id shows up in relationships
        node.layer.setDisplayExpression("node_id")

        link = nodes.pop("Link")
        item = self.dataset_tree.add_node_layer(link)
        self.add_item_to_qgis(item)
        self.add_relationship(
            link.layer, node.layer.id(), "LinkFromNode", "from_node_id"
        )
        self.add_relationship(link.layer, node.layer.id(), "LinkToNode", "to_node_id")

        basin_area_layer = nodes.pop("Basin / area", None)
        if basin_area_layer is not None:
            item = self.dataset_tree.add_node_layer(basin_area_layer)
            self.add_item_to_qgis(item)
            self.add_relationship(
                basin_area_layer.layer, node.layer.id(), "Basin / area"
            )

        # Add the remaining layers
        for table_name, node_layer in nodes.items():
            item = self.dataset_tree.add_node_layer(node_layer)
            self.add_item_to_qgis(item)
            self.add_relationship(node_layer.layer, node.layer.id(), table_name)

        # Connect node and link layer to derive connectivities.
        self.node_layer = node.layer
        assert self.node_layer is not None
        self.link_layer = link.layer
        self.link_layer.editingStopped.connect(self.connect_nodes)

        def filterbyrel(relationships, feature_ids):
            """Filter all related tables by the selected features in the node table."""
            ids = []
            selection = QgsFeatureRequest().setFilterFids(feature_ids)
            for rel in relationships:
                for feature in rel.referencedLayer().getFeatures(selection):
                    ids.extend(f.id() for f in rel.getRelatedFeatures(feature))

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

    def new_model(self) -> None:
        """Create a new Ribasim model file, and set it as the active dataset."""
        path, _ = QFileDialog.getSaveFileName(self, "Select file", "", "*.toml")
        self._new_model(path)

    def _new_model(self, path: str):
        if path != "":  # Empty string in case of cancel button press
            self.dataset_line_edit.setText(path)
            geo_path = self.path.with_name("database.gpkg")
            self._write_toml()

            for input_type in (Node, Link):
                instance = input_type.create(
                    geo_path,
                    self.ribasim_widget.crs,
                    names=[],
                )
                instance.write()
            write_schema_version(geo_path)
            self.load_geopackage()
            self.ribasim_widget.toggle_node_buttons(True)

    def _write_toml(self) -> None:
        with open(self.path, "w") as f:
            f.writelines(
                [
                    f"starttime = {datetime(2020, 1, 1)}\n",
                    f"endtime = {datetime(2021, 1, 1)}\n",
                    f'crs = "{self.ribasim_widget.crs.authid()}"\n',
                    'input_dir = "."\n',
                    'results_dir = "results"\n',
                    'ribasim_version = "2025.2.0"\n',
                ]
            )

    def open_model(self) -> None:
        """Open a Ribasim model file."""
        self.dataset_tree.clear()
        path, _ = QFileDialog.getOpenFileName(self, "Select file", "", "*.toml")
        self._open_model(path)

    def _open_model(self, path: str) -> None:
        if path != "":  # Empty string in case of cancel button press
            self.dataset_line_edit.setText(path)
            self.set_current_time_extent()
            self.load_geopackage()
            self.add_topology_context()
            self.ribasim_widget.toggle_node_buttons(True)
            self.refresh_results()
        self.dataset_tree.sortByColumn(0, Qt.SortOrder.AscendingOrder)

    def remove_geopackage_layer(self) -> None:
        """Remove layers from the dataset tree widget, QGIS layer panel and the GeoPackage."""
        self.dataset_tree.remove_geopackage_layers()

    def add_topology_context(self) -> None:
        """Connect to the layer context (right-click) menu opening."""
        ltv = self.ribasim_widget.iface.layerTreeView()
        ltv.contextMenuAboutToShow.connect(self.generate_topology_action)

    def generate_topology_action(self, menu: QMenu) -> None:
        """Generate checkable show topology action in the context menu."""
        for action in menu.actions():
            if action.text() == "Show topology":
                return

        layer = self.ribasim_widget.iface.activeLayer()
        if (
            not layer
            or layer.type() != QgsMapLayer.VectorLayer
            or "Link" not in layer.name()
        ):
            return

        # We store the state as a variable in the layer context (properties->variables)
        # This variable can be used by the layers style to show the topology.
        checked = (
            QgsExpressionContextUtils.layerScope(layer).variable("layer_topology")
            == "True"
        )

        # Always add action, as it's lives only during this context menu
        menu.addSeparator()
        action = menu.addAction("Show topology")
        action.setCheckable(True)
        action.setChecked(checked)
        action.triggered.connect(self.show_topology)

    def show_topology(self, checked: bool) -> None:
        """Set the topology switch variable and redraw the layer."""
        layer = self.ribasim_widget.iface.activeLayer()

        value = "True" if checked else "False"
        QgsExpressionContextUtils.setLayerVariable(
            layer,
            "layer_topology",
            value,
        )
        layer.triggerRepaint()

    def suppress_popup_changed(self):
        suppress = self.suppress_popup_checkbox.isChecked()
        for item in self.dataset_tree.items():
            layer = item.element.layer
            if layer is not None:
                config = layer.editFormConfig()
                config.setSuppress(suppress)
                layer.setEditFormConfig(config)

    def selection_names(self) -> set[str]:
        selection = self.dataset_tree.items()
        # Append associated items
        return {item.element.input_type() for item in selection}  # type: ignore # TODO: dynamic item.element should be in some dict.

    def add_node_layer(self, element: Input) -> None:
        self.dataset_tree.add_node_layer(element)

    def refresh_results(self) -> None:
        self._set_node_results()
        self._set_link_results()
        self.temporalController.updateTemporalRange.connect(self._update_arrow_layers)

    def get_current_time(self) -> datetime:
        """Retrieve the current (frame) time from the temporal controller."""
        canvas = self.ribasim_widget.iface.mapCanvas()
        temporalController = canvas.temporalController()

        f = temporalController.currentFrameNumber()
        currentDateTimeRange = temporalController.dateTimeRangeForFrameNumber(f)
        return currentDateTimeRange.begin().toPyDateTime()

    def set_current_time_extent(self) -> None:
        """Set the current time extent and interval of the temporal controller."""
        toml = get_toml_dict(self.path)

        canvas = self.ribasim_widget.iface.mapCanvas()
        self.temporalController = canvas.temporalController()

        trange = QgsDateTimeRange(toml["starttime"], toml["endtime"])
        canvas.setTemporalRange(trange)
        self.temporalController.setTemporalExtents(trange)
        self.temporalController.setFrameDuration(
            QgsInterval(toml.get("solver", {}).get("timestep", 86400))
        )
        canvas.setTemporalController(self.temporalController)

    def _set_node_results(self) -> None:
        node_layer = self.ribasim_widget.node_layer
        assert node_layer is not None
        path = self._set_results(node_layer, "node_id", "basin.arrow")
        if not path.exists():
            return

        self.basinnode_layer = self._duplicate_layer(
            node_layer, "BasinNode", "node_id", "node_type", "Basin"
        )
        self._add_arrow_layer(path, self.basinnode_layer, "node_id")

        # Add the concentration output
        path = (
            get_directory_path_from_model_file(
                self.ribasim_widget.path, property="results_dir"
            )
            / "concentration.arrow"
        )
        if not path.exists():
            return
        self._add_arrow_layer(
            path, self.basinnode_layer, "node_id", postprocess_concentration_arrow
        )

    def _set_link_results(self) -> None:
        link_layer = self.ribasim_widget.link_layer
        assert link_layer is not None
        path = self._set_results(link_layer, "link_id", "flow.arrow")
        if not path.exists():
            return
        self.flowlink_layer = self._duplicate_layer(
            link_layer, "FlowLink", "link_id", "link_type", "flow"
        )
        self._add_arrow_layer(path, self.flowlink_layer, "link_id")

    def _duplicate_layer(self, layer, name, fid_column, filterkey, filtervalue):
        """Duplicate a layer for use with output data."""
        duplicate = layer.materialize(
            QgsFeatureRequest().setFilterExpression(f"{filterkey} = '{filtervalue}'")
        )
        duplicate.setName(name)
        fn = STYLE_DIR / f"{name}Style.qml"
        if fn.exists():
            duplicate.loadNamedStyle(str(fn))

        # The fids of a duplicated layer in memory are not the same
        # as our node/link_ids anymore, and can't be set as such.
        # To update the layer with arrow data we need to guarantee
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

        self.add_layer(duplicate, "Ribasim Results", False, labels=None)
        return duplicate

    def _add_arrow_layer(
        self,
        path: Path,
        layer: QgsVectorLayer,
        fid_column: str,
        postprocess: callable = lambda df: df.set_index(pd.DatetimeIndex(df["time"])),
    ) -> None:
        """Add arrow output data to the layer and setup its update mechanism."""
        dataset = ogr.Open(path)
        dlayer = dataset.GetLayer(0)
        stream = dlayer.GetArrowStreamAsNumPy()
        data = stream.GetNextRecordBatch()

        df = pd.DataFrame(data=data)
        df = postprocess(df)
        self.results[path.stem] = df

        # Add the arrow fields to the layer if they doesn't exist
        layer.startEditing()
        for column in df.columns.tolist():
            if (
                column == fid_column or column == "time"
            ):  # skip the fid (link/node_id) column
                continue
            if layer.dataProvider().fieldNameIndex(column) == -1:
                layer.dataProvider().addAttributes([QgsField(column, QVariant.Double)])
            layer.updateFields()
        layer.commitChanges()

        self._update_arrow_layer(
            layer, df, fid_column, self.get_current_time(), force=True
        )

    def _update_arrow_layer(
        self,
        layer: QgsVectorLayer,
        df: pd.DataFrame,
        fid_column: str,
        time: datetime,
        force: bool = False,
    ) -> None:
        """Update the layer with the current arrow time slice."""
        if layer is None or df is None:
            return

        # If we're out of bounds, do nothing, assuming
        # the previous time slice is most valid, unless forced
        # to update on initial load (without a valid datetime).
        if time not in df.index:
            if force:
                time = df.index[-1]
            else:
                print(f"Skipping update, out of bounds for {time}")
                return

        timeslice = df.loc[time, :]

        layer.startEditing()
        layer.beginEditCommand("Group all undos for performance.")

        fids = sorted(layer.allFeatureIds())
        for column in df.columns.tolist():
            if (
                column == fid_column or column == "time"
            ):  # skip the fid (link/node_id) column
                continue
            column_id = layer.dataProvider().fieldNameIndex(column)
            for fid, variable in zip(fids, timeslice[column]):
                layer.changeAttributeValue(
                    fid,
                    column_id,
                    variable,
                )

        layer.endEditCommand()
        layer.commitChanges()

    def _update_arrow_layers(self, timerange: QgsDateTimeRange) -> None:
        """Update the result layers with the current arrow time slice."""
        # Handle edge case when disabling the temporal controller
        if timerange.isEmpty() or timerange.isInfinite():
            return

        time = timerange.begin().toPyDateTime()
        self._update_arrow_layer(
            self.basinnode_layer, self.results.get("basin"), "node_id", time
        )
        self._update_arrow_layer(
            self.basinnode_layer,
            self.results.get("concentration"),
            "node_id",
            time,
        )
        self._update_arrow_layer(
            self.flowlink_layer, self.results.get("flow"), "link_id", time
        )

    def _set_results(
        self,
        layer: QgsVectorLayer,
        column: str,
        output_file_name: str,
    ) -> None:
        path = (
            get_directory_path_from_model_file(
                self.ribasim_widget.path, property="results_dir"
            )
            / output_file_name
        )
        if layer is not None:
            layer.setCustomProperty("arrow_type", "timeseries")
            layer.setCustomProperty("arrow_path", str(path))
            layer.setCustomProperty("arrow_fid_column", column)
        return path


def postprocess_concentration_arrow(df: pd.DataFrame) -> pd.DataFrame:
    """Postprocess the concentration arrow data to a wide format."""
    ndf = pd.pivot_table(df, columns="substance", index=["time", "node_id"])
    ndf.columns = ndf.columns.droplevel(0).str.decode("utf-8")
    ndf.reset_index("node_id", inplace=True)
    return ndf
