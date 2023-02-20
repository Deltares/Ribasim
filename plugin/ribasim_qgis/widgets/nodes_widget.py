from functools import partial

from PyQt5.QtWidgets import QGridLayout, QPushButton, QVBoxLayout, QWidget
from ribasim_qgis.core.nodes import NODES


class NodesWidget(QWidget):
    def __init__(self, parent):
        super().__init__(parent)
        self.parent = parent

        self.node_buttons = {}
        for node in NODES:
            if node in ("node", "edge"):
                continue
            button = QPushButton(node)
            button.clicked.connect(partial(self.new_node_layer, node_type=node))
            self.node_buttons[node] = button
        self.toggle_node_buttons(False)  # no dataset loaded yet

        node_layout = QVBoxLayout()
        node_grid = QGridLayout()
        n_row = -(len(self.node_buttons) // -2)  # Ceiling division
        for i, button in enumerate(self.node_buttons.values()):
            if i < n_row:
                node_grid.addWidget(button, i, 0)
            else:
                node_grid.addWidget(button, i % n_row, 1)
        node_layout.addLayout(node_grid)
        node_layout.addStretch()
        self.setLayout(node_layout)

    def toggle_node_buttons(self, state: bool) -> None:
        """
        Enables or disables the node buttons.

        Parameters
        ----------
        state: bool
            True to enable, False to disable
        """
        for button in self.node_buttons.values():
            button.setEnabled(state)

    def new_node_layer(self, node_type: str) -> None:
        """
        Create a new Ribasim node input layer.

        Parameters
        ----------
        node_type: str
            Name of the element type.
        """
        klass = NODES[node_type]
        names = self.parent.selection_names()
        node = klass.create(self.parent.path, self.parent.crs, names)
        # Write to geopackage
        node.write()
        # Add to QGIS
        self.parent.add_layer(
            node.layer, "Ribasim Input", node.renderer, labels=node.labels
        )
        # Add to dataset tree
        self.parent.add_node_layer(node)
