"""
This widgets displays the available input layers in the GeoPackage.

This widget also allows enabling or disabling individual elements for a
computation.
"""
from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime
from pathlib import Path
from typing import Any, cast

import numpy as np
from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QFileDialog,
    QHBoxLayout,
    QHeaderView,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QSizePolicy,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)
from qgis.core import (
    QgsFeature,
    QgsMapLayer,
    QgsProject,
    QgsVectorLayer,
)
from qgis.core.additions.edit import edit

from ribasim_qgis.core.model import get_database_path_from_model_file
from ribasim_qgis.core.nodes import Edge, Input, Node, load_nodes_from_geopackage
from ribasim_qgis.core.topology import derive_connectivity, explode_lines


class DatasetTreeWidget(QTreeWidget):
    def __init__(self, parent: QWidget | None):
        super().__init__(parent)
        self.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.setHeaderHidden(True)
        self.setSortingEnabled(True)
        self.setSizePolicy(QSizePolicy.Minimum, QSizePolicy.Preferred)
        self.setHeaderLabels(["", ""])
        self.setHeaderHidden(False)
        header = self.header()
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionsMovable(False)
        self.setColumnCount(2)
        self.setColumnWidth(0, 1)
        self.setColumnWidth(2, 1)

    def items(self) -> list[QTreeWidgetItem]:
        root = self.invisibleRootItem()
        return [root.child(i) for i in range(root.childCount())]

    def add_item(self, name: str, enabled: bool = True):
        item = QTreeWidgetItem()
        self.addTopLevelItem(item)
        checkbox = QCheckBox()
        checkbox.setChecked(True)
        checkbox.setEnabled(enabled)
        self.setItemWidget(item, 0, checkbox)
        item.setText(1, name)
        return item

    def add_node_layer(self, element: Input) -> None:
        # These are mandatory elements, cannot be unticked
        item = self.add_item(name=element.input_type(), enabled=True)
        item.element = element

    def remove_geopackage_layers(self) -> None:
        """
        Remove layers from:

        * The dataset tree widget
        * The QGIS layer panel
        * The geopackage
        """

        # Collect the selected items
        selection = self.selectedItems()

        # Warn before deletion
        message = "\n".join([f"- {item.text(1)}" for item in selection])
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
        qgs_instance = QgsProject.instance()
        assert qgs_instance is not None

        for element in elements:
            layer = element.layer
            # QGIS layers
            if layer is None:
                continue
            try:
                qgs_instance.removeMapLayer(layer.id())
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
        self.edge_layer: QgsVectorLayer | None = None
        self.node_layer: QgsVectorLayer | None = None

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
        """Returns currently active path to Ribasim model (.toml)"""
        return Path(self.dataset_line_edit.text())

    def explode_and_connect(self) -> None:
        node = self.node_layer
        edge = self.edge_layer
        assert edge is not None
        assert node is not None
        explode_lines(edge)

        n_node = node.featureCount()
        n_edge = edge.featureCount()
        if n_node == 0 or n_edge == 0:
            return

        node_xy = np.empty((n_node, 2), dtype=float)
        node_index = np.empty(n_node, dtype=int)
        node_iterator = cast(Iterable[QgsFeature], node.getFeatures())
        for i, feature in enumerate(node_iterator):
            point = feature.geometry().asPoint()
            node_xy[i, 0] = point.x()
            node_xy[i, 1] = point.y()
            node_index[i] = feature.attribute(0)  # Store the feature id

        edge_xy = np.empty((n_edge, 2, 2), dtype=float)
        edge_iterator = cast(Iterable[QgsFeature], edge.getFeatures())
        for i, feature in enumerate(edge_iterator):
            geometry = feature.geometry().asPolyline()
            for j, point in enumerate(geometry):
                edge_xy[i, j, 0] = point.x()
                edge_xy[i, j, 1] = point.y()
        edge_xy = edge_xy.reshape((-1, 2))
        from_id, to_id = derive_connectivity(node_index, node_xy, edge_xy)

        fields = edge.fields()
        field1 = fields.indexFromName("from_node_id")
        field2 = fields.indexFromName("to_node_id")
        try:
            # Avoid infinite recursion
            edge.blockSignals(True)
            with edit(edge):
                edge_iterator = cast(Iterable[QgsFeature], edge.getFeatures())
                for feature, id1, id2 in zip(edge_iterator, from_id, to_id):
                    fid = feature.id()
                    # Nota bene: will fail with numpy integers, has to be Python type!
                    edge.changeAttributeValue(fid, field1, int(id1))
                    edge.changeAttributeValue(fid, field2, int(id2))

        finally:
            edge.blockSignals(False)

        return

    def add_layer(
        self,
        layer: Any,
        destination: Any,
        renderer: Any = None,
        suppress: bool = False,
        on_top: bool = False,
        labels: Any = None,
    ) -> QgsMapLayer | None:
        return self.ribasim_widget.add_layer(
            layer,
            destination,
            renderer,
            suppress,
            on_top,
            labels,
        )

    def add_item_to_qgis(self, item) -> None:
        element = item.element
        layer, renderer, labels = element.from_geopackage()
        suppress = self.suppress_popup_checkbox.isChecked()
        self.add_layer(layer, "Ribasim Input", renderer, suppress, labels=labels)
        element.set_editor_widget()
        element.set_read_only()
        return

    def add_selection_to_qgis(self) -> None:
        selection = self.dataset_tree.selectedItems()
        for item in selection:
            self.add_item_to_qgis(item)

    def load_geopackage(self) -> None:
        """Load the layers of a GeoPackage into the Layers Panel"""
        self.dataset_tree.clear()
        geo_path = get_database_path_from_model_file(self.path)
        nodes = load_nodes_from_geopackage(geo_path)
        for node_layer in nodes.values():
            self.dataset_tree.add_node_layer(node_layer)
        name = self.path.stem
        self.ribasim_widget.create_groups(name)
        for item in self.dataset_tree.items():
            self.add_item_to_qgis(item)

        # Connect node and edge layer to derive connectivities.
        self.node_layer = nodes["Node"].layer
        self.edge_layer = nodes["Edge"].layer
        self.edge_layer.editingStopped.connect(self.explode_and_connect)
        return

    def new_model(self) -> None:
        """Create a new Ribasim model file, and set it as the active dataset."""
        path, _ = QFileDialog.getSaveFileName(self, "Select file", "", "*.toml")
        if path != "":  # Empty string in case of cancel button press
            self.dataset_line_edit.setText(path)
            geo_path = self.path.with_name("database.gpkg")
            self._write_new_model()

            for input_type in (Node, Edge):
                instance = input_type.create(
                    geo_path,
                    self.ribasim_widget.crs,
                    names=[],
                )
                instance.write()
            self.load_geopackage()
            self.ribasim_widget.toggle_node_buttons(True)

    def _write_new_model(self) -> None:
        with open(self.path, "w") as f:
            f.writelines(
                [
                    f"starttime = {datetime(2020, 1, 1)}\n",
                    f"endtime = {datetime(2021, 1, 1)}\n",
                    'input_dir = "."\n',
                    'results_dir = "results"\n',
                ]
            )

    def open_model(self) -> None:
        """Open a Ribasim model file."""
        self.dataset_tree.clear()
        path, _ = QFileDialog.getOpenFileName(self, "Select file", "", "*.toml")
        if path != "":  # Empty string in case of cancel button press
            self.dataset_line_edit.setText(path)
            self.load_geopackage()
            self.ribasim_widget.toggle_node_buttons(True)
        self.dataset_tree.sortByColumn(0, Qt.SortOrder.AscendingOrder)

    def remove_geopackage_layer(self) -> None:
        """
        Remove layers from:
        * The dataset tree widget
        * The QGIS layer panel
        * The geopackage
        """
        self.dataset_tree.remove_geopackage_layers()

    def suppress_popup_changed(self):
        suppress = self.suppress_popup_checkbox.isChecked()
        for item in self.dataset_tree.items():
            layer = item.element.layer
            if layer is not None:
                config = layer.editFormConfig()
                config.setSuppress(suppress)
                layer.setEditFormConfig(config)

    def active_nodes(self):
        active_nodes = {}
        for item in self.dataset_tree.items():
            active_nodes[item.text(1)] = not (item.checkbox.isChecked() == 0)
        return active_nodes

    def selection_names(self) -> set[str]:
        selection = self.dataset_tree.items()
        # Append associated items
        return {item.element.input_type() for item in selection}  # type: ignore # TODO: dynamic item.element should be in some dict.

    def add_node_layer(self, element: Input) -> None:
        self.dataset_tree.add_node_layer(element)
