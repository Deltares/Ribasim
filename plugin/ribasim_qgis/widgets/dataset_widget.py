"""
This widgets displays the available elements in the GeoPackage.

This widget also allows enabling or disabling individual elements for a
computation. It also forms the link between the geometry layers and the
associated layers for homogeneities, or for timeseries layers for ttim
elements.

Not every TimML element has a TTim equivalent (yet). This means that when a
user chooses the transient simulation mode, a number of elements must be
disabled (such as inhomogeneities).
"""
from pathlib import Path
from typing import Any, List, Set

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
from qgis.core import QgsMapLayer, QgsProject
from ribasim_qgis.core.nodes import load_nodes_from_geopackage


class DatasetTreeWidget(QTreeWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.setHeaderHidden(True)
        self.setSortingEnabled(True)
        self.setSizePolicy(QSizePolicy.Minimum, QSizePolicy.Preferred)
        self.setHeaderLabels(["", "steady", "", "transient"])
        self.setHeaderHidden(False)
        header = self.header()
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(3, QHeaderView.Stretch)
        header.setSectionsMovable(False)
        self.setColumnCount(4)
        self.setColumnWidth(0, 1)
        self.setColumnWidth(2, 1)
        self.domain = None

    def items(self) -> List[QTreeWidgetItem]:
        root = self.invisibleRootItem()
        return [root.child(i) for i in range(root.childCount())]

    def add_item(self, timml_name: str, ttim_name: str = None, enabled: bool = True):
        item = QTreeWidgetItem()
        self.addTopLevelItem(item)
        item.timml_checkbox = QCheckBox()
        item.timml_checkbox.setChecked(True)
        item.timml_checkbox.setEnabled(enabled)
        self.setItemWidget(item, 0, item.timml_checkbox)
        item.setText(1, timml_name)
        item.ttim_checkbox = QCheckBox()
        item.ttim_checkbox.setChecked(True)
        item.ttim_checkbox.setEnabled(enabled)
        if ttim_name is None:
            item.ttim_checkbox.setChecked(False)
            item.ttim_checkbox.setEnabled(False)
        self.setItemWidget(item, 2, item.ttim_checkbox)
        item.setText(3, ttim_name)
        # Disable ttim layer when timml layer is unticked
        # as timml layer is always required for ttim layer
        item.timml_checkbox.toggled.connect(
            lambda checked: not checked and item.ttim_checkbox.setChecked(False)
        )
        item.assoc_item = None
        return item

    def add_node_layer(self, element) -> None:
        # These are mandatory elements, cannot be unticked
        item = self.add_item(
            timml_name=element.timml_name, ttim_name=element.ttim_name, enabled=True
        )
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
        # Append associated items
        for item in selection:
            if item.assoc_item is not None and item.assoc_item not in selection:
                selection.append(item.assoc_item)

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
        elements = set([item.element for item in selection])
        qgs_instance = QgsProject.instance()

        for element in elements:
            for layer in [
                element.timml_layer,
                element.ttim_layer,
                element.assoc_layer,
            ]:
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
    def __init__(self, parent):
        super().__init__(parent)
        self.parent = parent
        self.dataset_tree = DatasetTreeWidget()
        self.dataset_tree.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Expanding)
        self.dataset_line_edit = QLineEdit()
        self.dataset_line_edit.setEnabled(False)  # Just used as a viewing port
        self.new_geopackage_button = QPushButton("New")
        self.open_geopackage_button = QPushButton("Open")
        self.remove_button = QPushButton("Remove from Dataset")
        self.add_button = QPushButton("Add to QGIS")
        self.new_geopackage_button.clicked.connect(self.new_geopackage)
        self.open_geopackage_button.clicked.connect(self.open_geopackage)
        self.suppress_popup_checkbox = QCheckBox("Suppress attribute form pop-up")
        self.suppress_popup_checkbox.stateChanged.connect(self.suppress_popup_changed)
        self.remove_button.clicked.connect(self.remove_geopackage_layer)
        self.add_button.clicked.connect(self.add_selection_to_qgis)
        # Layout
        dataset_layout = QVBoxLayout()
        dataset_row = QHBoxLayout()
        layer_row = QHBoxLayout()
        dataset_row.addWidget(self.dataset_line_edit)
        dataset_row.addWidget(self.open_geopackage_button)
        dataset_row.addWidget(self.new_geopackage_button)
        dataset_layout.addLayout(dataset_row)
        dataset_layout.addWidget(self.dataset_tree)
        dataset_layout.addWidget(self.suppress_popup_checkbox)
        layer_row.addWidget(self.add_button)
        layer_row.addWidget(self.remove_button)
        dataset_layout.addLayout(layer_row)
        self.setLayout(dataset_layout)

    @property
    def path(self) -> str:
        """Returns currently active path to GeoPackage"""
        return self.dataset_line_edit.text()

    def add_layer(
        self,
        layer: Any,
        destination: Any,
        renderer: Any = None,
        suppress: bool = None,
        on_top: bool = False,
    ) -> QgsMapLayer:
        return self.parent.add_layer(
            layer,
            destination,
            renderer,
            suppress,
            on_top,
        )

    def add_item_to_qgis(self, item) -> None:
        layers = item.element.from_geopackage()
        suppress = self.suppress_popup_checkbox.isChecked()
        timml_layer, renderer = layers[0]
        maplayer = self.add_layer(timml_layer, "timml", renderer, suppress)
        self.add_layer(layers[1][0], "ttim")
        self.add_layer(layers[2][0], "timml")

    def add_selection_to_qgis(self) -> None:
        selection = self.dataset_tree.selectedItems()
        for item in selection:
            self.add_item_to_qgis(item)

    def load_geopackage(self) -> None:
        """
        Load the layers of a GeoPackage into the Layers Panel
        """
        self.dataset_tree.clear()
        nodes = load_nodes_from_geopackage(self.path)
        for node_layer in nodes:
            self.dataset_tree.add_node_layer(node_layer)
        name = str(Path(self.path).stem)
        self.parent.create_groups(name)
        for item in self.dataset_tree.items():
            self.add_item_to_qgis(item)

    def new_geopackage(self) -> None:
        """
        Create a new GeoPackage file, and set it as the active dataset.
        """
        path, _ = QFileDialog.getSaveFileName(self, "Select file", "", "*.gpkg")
        if path != "":  # Empty string in case of cancel button press
            self.dataset_line_edit.setText(path)
            self.load_geopackage()
            self.parent.toggle_element_buttons(True)
        self.parent.on_transient_changed()

    def open_geopackage(self) -> None:
        """
        Open a GeoPackage file, containing qgis-tim
        """
        self.dataset_tree.clear()
        path, _ = QFileDialog.getOpenFileName(self, "Select file", "", "*.gpkg")
        if path != "":  # Empty string in case of cancel button press
            self.dataset_line_edit.setText(path)
            self.load_geopackage()
            self.parent.toggle_element_buttons(True)
        self.dataset_tree.sortByColumn(0, Qt.SortOrder.AscendingOrder)
        self.parent.on_transient_changed()

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
            layer = item.element.timml_layer
            if layer is not None:
                config = layer.editFormConfig()
                config.setSuppress(suppress)
                layer.setEditFormConfig(config)

    def active_nodes(self):
        active_nodes = {}
        for item in self.dataset_tree.items():
            active_nodes[item.text(1)] = not (item.timml_checkbox.isChecked() == 0)
            active_nodes[item.text(3)] = not (item.ttim_checkbox.isChecked() == 0)
        return active_nodes

    def selection_names(self) -> Set[str]:
        selection = self.dataset_tree.items()
        # Append associated items
        for item in selection:
            if item.assoc_item is not None and item.assoc_item not in selection:
                selection.append(item.assoc_item)
        return set([item.element.name for item in selection])

    def add_node_layer(self, element) -> None:
        self.dataset_tree.add_node_layer(element)
