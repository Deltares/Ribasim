"""
This widgets displays the available input layers in the GeoPackage.

This widget also allows enabling or disabling individual elements for a
computation.
"""

from __future__ import annotations

from datetime import datetime
from functools import partial
from pathlib import Path
from typing import Any, cast

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QFileDialog,
    QHBoxLayout,
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
    QgsEditorWidgetSetup,
    QgsFeatureRequest,
    QgsMapLayer,
    QgsProject,
    QgsRelation,
    QgsVectorLayer,
)

from ribasim_qgis.core.geopackage import write_schema_version
from ribasim_qgis.core.model import (
    get_database_path_from_model_file,
    get_directory_path_from_model_file,
)
from ribasim_qgis.core.nodes import Edge, Input, Node, load_nodes_from_geopackage
from ribasim_qgis.core.topology import set_edge_properties


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

    def connect_nodes(self) -> None:
        node = self.node_layer
        edge = self.edge_layer
        assert edge is not None
        assert node is not None

        if (node.featureCount() > 0) and (edge.featureCount() > 0):
            set_edge_properties(node, edge)

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
        """Load the layers of a GeoPackage into the Layers Panel"""
        self.dataset_tree.clear()
        geo_path = get_database_path_from_model_file(self.path)
        nodes = load_nodes_from_geopackage(geo_path)

        name = self.path.stem
        self.ribasim_widget.create_groups(name)

        # Make sure "Node", "Edge", "Basin / area" are the top three layers
        node = nodes.pop("Node")
        item = self.dataset_tree.add_node_layer(node)
        self.add_item_to_qgis(item)
        # Make sure node_id shows up in relationships
        node.layer.setDisplayExpression("node_id")

        edge = nodes.pop("Edge")
        item = self.dataset_tree.add_node_layer(edge)
        self.add_item_to_qgis(item)
        self.add_relationship(
            edge.layer, node.layer.id(), "EdgeFromNode", "from_node_id"
        )
        self.add_relationship(edge.layer, node.layer.id(), "EdgeToNode", "to_node_id")

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

        # Connect node and edge layer to derive connectivities.
        self.node_layer = node.layer
        assert self.node_layer is not None
        self.edge_layer = edge.layer
        self.edge_layer.editingStopped.connect(self.connect_nodes)

        def filterbyrel(relationships, feature_ids):
            """Filter all related tables by the selected features in the node table."""
            ids = []
            selection = QgsFeatureRequest().setFilterFids(feature_ids)
            for rel in relationships:
                for feature in rel.referencedLayer().getFeatures(selection):
                    ids.extend(f.id() for f in rel.getRelatedFeatures(feature))

            rel.referencingLayer().selectByIds(ids)

        # When the Node selection changes, filter all related tables
        edge_rels = []
        instance = QgsProject.instance()
        assert instance is not None
        rel_manager = instance.relationManager()
        assert rel_manager is not None
        for rel in rel_manager.relations().values():
            # Edge relations are special, they have two references to the Node table
            referencing = rel.referencingLayer()
            referenced = rel.referencedLayer()
            assert referencing is not None
            assert referenced is not None

            if referencing.name() == "Edge":
                edge_rels.append(rel)
            else:
                referenced.selectionChanged.connect(partial(filterbyrel, [rel]))

        self.node_layer.selectionChanged.connect(partial(filterbyrel, edge_rels))
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
            write_schema_version(geo_path)
            self.load_geopackage()
            self.ribasim_widget.toggle_node_buttons(True)

    def _write_new_model(self) -> None:
        with open(self.path, "w") as f:
            f.writelines(
                [
                    f"starttime = {datetime(2020, 1, 1)}\n",
                    f"endtime = {datetime(2021, 1, 1)}\n",
                    f'crs = "{self.ribasim_widget.crs.authid()}"\n',
                    'input_dir = "."\n',
                    'results_dir = "results"\n',
                    'ribasim_version = "2024.10.0"\n',
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
            self.refresh_results()
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

    def selection_names(self) -> set[str]:
        selection = self.dataset_tree.items()
        # Append associated items
        return {item.element.input_type() for item in selection}  # type: ignore # TODO: dynamic item.element should be in some dict.

    def add_node_layer(self, element: Input) -> None:
        self.dataset_tree.add_node_layer(element)

    def refresh_results(self) -> None:
        self.__set_node_results()
        self.__set_edge_results()

    def __set_node_results(self) -> None:
        node_layer = self.ribasim_widget.node_layer
        assert node_layer is not None
        self.__set_results(node_layer, "node_id", "basin.arrow")

    def __set_edge_results(self) -> None:
        edge_layer = self.ribasim_widget.edge_layer
        assert edge_layer is not None
        self.__set_results(edge_layer, "edge_id", "flow.arrow")

    def __set_results(
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
