from PyQt5.QtWidgets import QFileDialog, QPushButton, QVBoxLayout, QWidget


class ResultsWidget(QWidget):
    def __init__(self, parent):
        super().__init__(parent)
        self.parent = parent
        self.node_results_button = QPushButton("Associate Node Results")
        self.edge_results_button = QPushButton("Associate Edge Results")
        self.node_results_button.clicked.connect(self.set_node_results)
        self.edge_results_button.clicked.connect(self.set_edge_results)
        layout = QVBoxLayout()
        layout.addWidget(self.node_results_button)
        layout.addWidget(self.edge_results_button)
        layout.addStretch()
        self.setLayout(layout)

    def _set_results(self, layer, column: str):
        path, _ = QFileDialog.getOpenFileName(self, "Select file", "", "*.arrow")
        if path == "":
            return
        if layer is not None:
            layer.setCustomProperty("arrow_type", "timeseries")
            layer.setCustomProperty("arrow_path", path)
            layer.setCustomProperty("arrow_fid_column", column)
        return

    def set_node_results(self):
        node_layer = self.parent.dataset_widget.node_layer
        self._set_results(node_layer, "node_id")
        return

    def set_edge_results(self):
        edge_layer = self.parent.dataset_widget.edge_layer
        self._set_results(edge_layer, "edge_id")
        return
