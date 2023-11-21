from functools import partial
from typing import Optional, cast

from PyQt5.QtWidgets import QGridLayout, QPushButton, QVBoxLayout, QWidget

from ribasim_qgis.core.nodes import NODES
from ribasim_qgis.widgets.ribasim_widget import RibasimWidget


class NodesWidget(QWidget):
    def __init__(self, parent: Optional[QWidget]):
        super().__init__(parent)

        self.node_buttons: dict[str, QPushButton] = {}
        for node in NODES:
            if node in ("Node", "Edge"):
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
        Enable or disable the node buttons.

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
        parent_widget = cast(RibasimWidget, self.parent())
        klass = NODES[node_type]
        names = parent_widget.selection_names()
        node = klass.create(parent_widget.path, parent_widget.crs, names)
        # Write to geopackage
        node.write()
        # Add to QGIS
        parent_widget.add_layer(
            node.layer, "Ribasim Input", node.renderer, labels=node.labels
        )
        # Add to dataset tree
        parent_widget.add_node_layer(node)
