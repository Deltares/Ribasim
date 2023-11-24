from typing import cast

from PyQt5.QtWidgets import QFileDialog, QPushButton, QVBoxLayout, QWidget
from qgis.core import QgsVectorLayer

from ribasim_qgis.core.model import get_property_from_model_file


class ResultsWidget(QWidget):
    def __init__(self, parent: QWidget):
        from ribasim_qgis.widgets.ribasim_widget import RibasimWidget

        super().__init__(parent)
        self.ribasim_widget = cast(RibasimWidget, parent)
        refresh_results_button = QPushButton("Refresh Results")
        refresh_results_button.clicked.connect(self.refresh_results)

        # layout
        layout = QVBoxLayout()
        layout.addWidget(refresh_results_button)
        layout.addStretch()
        self.setLayout(layout)

    def refresh_results(self) -> None:
        self.set_node_results()
        self.set_edge_results()

    def set_node_results(self) -> None:
        node_layer = self.ribasim_widget.dataset_widget.node_layer
        assert node_layer is not None
        self._set_results(node_layer, "node_id")

    def set_edge_results(self) -> None:
        edge_layer = self.ribasim_widget.dataset_widget.edge_layer
        assert edge_layer is not None
        self._set_results(edge_layer, "edge_id")

    def _set_results(self, layer: QgsVectorLayer, column: str) -> None:
        path = (
            get_property_from_model_file(self.ribasim_widget.path, "results_dir")
            / "basin.arrow"
        )
        if path == "":
            return
        if layer is not None:
            layer.setCustomProperty("arrow_type", "timeseries")
            layer.setCustomProperty("arrow_path", path)
            layer.setCustomProperty("arrow_fid_column", column)
