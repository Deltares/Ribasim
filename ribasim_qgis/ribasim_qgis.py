"""Setup a dockwidget to hold the ribasim plugin widgets."""

import importlib
import tomllib
from pathlib import Path

from qgis.core import Qgis
from qgis.gui import QgsCustomDropHandler
from qgis.PyQt.QtCore import Qt
from qgis.PyQt.QtGui import QIcon
from qgis.PyQt.QtWidgets import (
    QAction,
    QDockWidget,
    QFileDialog,
    QMenu,
    QMessageBox,
    QToolButton,
)

from ribasim_qgis.widgets.dataset_widget import DatasetWidget

icondir = Path(__file__).parent


class RibasimDropHandler(QgsCustomDropHandler):
    def __init__(self, plugin):
        super().__init__()
        self.parent = plugin

    def handleFileDrop(self, path):
        if not path.lower().endswith(".toml"):
            return False

        with Path(path).open("rb") as f:
            data = tomllib.load(f)
            if "ribasim_version" not in data:
                return False

        self.parent.open_model(path)

        return True


class RibasimPlugin:
    def __init__(self, iface):
        # Save reference to the QGIS interface
        self.iface = iface
        self.ribasim_widget = None
        self.plot_dock = None
        self.plugin_dir = Path(__file__).parent
        self.toolbar = iface.addToolBar("Ribasim")
        self.toolbar.setObjectName("Ribasim")
        self.pluginIsActive = True
        self.drop_handler = RibasimDropHandler(self)

    def initGui(self):
        icon = QIcon(str(self.plugin_dir / "icon.png"))

        # Actions
        self.action_open = QAction("Open Ribasim model", self.iface.mainWindow())
        self.action_open.triggered.connect(self.open_model)
        self.iface.addPluginToMenu("Ribasim", self.action_open)

        self.action_run = QAction("Run Ribasim model", self.iface.mainWindow())
        self.action_run.triggered.connect(self.run_model)
        self.iface.addPluginToMenu("Ribasim", self.action_run)

        self.action_reload = QAction("Reload Ribasim model", self.iface.mainWindow())
        self.action_reload.triggered.connect(self.reload_model)
        self.iface.addPluginToMenu("Ribasim", self.action_reload)

        self.action_set_home = QAction("Set Ribasim home", self.iface.mainWindow())
        self.action_set_home.triggered.connect(self.set_ribasim_home)
        self.iface.addPluginToMenu("Ribasim", self.action_set_home)

        self.action_timeseries = QAction("Timeseries results", self.iface.mainWindow())
        self.action_timeseries.triggered.connect(self.toggle_plot_dock)
        self.iface.addPluginToMenu("Ribasim", self.action_timeseries)

        # Single tool button — always opens dropdown
        self.tool_button = QToolButton()
        self.tool_button.setIcon(icon)
        self.tool_button.setToolTip("Ribasim")
        self.tool_button.setPopupMode(QToolButton.InstantPopup)
        menu = QMenu(self.tool_button)
        menu.addAction(self.action_open)
        menu.addSeparator()
        menu.addAction(self.action_run)
        menu.addAction(self.action_reload)
        menu.addAction(self.action_set_home)
        menu.addSeparator()
        menu.addAction(self.action_timeseries)
        self.tool_button.setMenu(menu)
        self.toolbar.addWidget(self.tool_button)

        self.iface.registerCustomDropHandler(self.drop_handler)

    def toggle_plot_dock(self):
        """Show/hide the timeseries dock."""
        if self.plot_dock is None:
            return
        if (
            not self.plot_dock.isVisible()
            and importlib.util.find_spec("plotly") is None
        ):
            self.iface.messageBar().pushMessage(
                "Error: The Ribasim plugin requires the `plotly` package.",
                level=Qgis.MessageLevel.Critical,
            )
            return
        self.plot_dock.setVisible(not self.plot_dock.isVisible())

    def run_model(self):
        """Run the currently loaded Ribasim model."""
        if self.ribasim_widget is not None:
            self.ribasim_widget.run_model()

    def set_ribasim_home(self):
        """Persist Ribasim home directory in QGIS settings."""
        current_home = DatasetWidget.get_ribasim_home_setting()

        current_home_text = str(current_home) if current_home is not None else "Not set"
        dialog = QMessageBox(self.iface.mainWindow())
        dialog.setWindowTitle("Set Ribasim home")
        dialog.setText(
            "This setting controls which Ribasim version is used to run the model.\n\n"
            f"Current Ribasim home:\n{current_home_text}\n\n"
            "Choose an action."
        )
        change_button = dialog.addButton("Change...", QMessageBox.ButtonRole.AcceptRole)
        unset_button = dialog.addButton("Unset", QMessageBox.ButtonRole.DestructiveRole)
        cancel_button = dialog.addButton(QMessageBox.StandardButton.Cancel)
        dialog.exec()

        clicked = dialog.clickedButton()
        if clicked == cancel_button:
            return

        if clicked == unset_button:
            DatasetWidget.clear_ribasim_home_setting()
            self.iface.messageBar().pushMessage(
                "Success",
                "Cleared configured Ribasim home.",
                level=Qgis.MessageLevel.Success,
                duration=5,
            )
            return

        if clicked != change_button:
            return

        start_dir = str(current_home) if current_home is not None else str(Path.home())
        selected = QFileDialog.getExistingDirectory(
            self.iface.mainWindow(),
            "Select Ribasim home",
            start_dir,
        )
        if not selected:
            return

        cli = DatasetWidget.get_ribasim_cli_from_home(Path(selected))
        if cli is None:
            self.iface.messageBar().pushMessage(
                "Error",
                "Ribasim executable not found in selected directory. "
                "Expected a bin directory containing ribasim.",
                level=Qgis.MessageLevel.Critical,
            )
            return
        DatasetWidget.set_ribasim_home_setting(Path(selected))

        self.iface.messageBar().pushMessage(
            "Success",
            f"Configured Ribasim home: {selected}",
            level=Qgis.MessageLevel.Success,
            duration=5,
        )

    def reload_model(self):
        """Reload the currently loaded Ribasim model."""
        if self.ribasim_widget is not None:
            self.ribasim_widget.reload_model()

    def open_model(self, path=None):
        if self.ribasim_widget is None:
            if importlib.util.find_spec("pandas") is None:
                self.iface.messageBar().pushMessage(
                    "Error: The Ribasim plugin requires the `pandas` package.",
                    level=Qgis.MessageLevel.Critical,
                )
                return

            from ribasim_qgis.widgets.ribasim_widget import RibasimWidget

            self.ribasim_widget = RibasimWidget(self.iface)

            # Create a dockable plot panel (hidden initially)
            self.plot_dock = QDockWidget(
                "Ribasim Timeseries Results", self.iface.mainWindow()
            )
            self.plot_dock.setObjectName("RibasimPlotDock")
            self.plot_dock.setWidget(self.ribasim_widget.plot_widget)
            self.iface.addDockWidget(Qt.BottomDockWidgetArea, self.plot_dock)
            self.plot_dock.setVisible(False)

        self.ribasim_widget.open_model(path)

    def unload(self):
        if self.plot_dock:
            self.iface.removeDockWidget(self.plot_dock)
            self.plot_dock.deleteLater()
            self.plot_dock = None
        if self.toolbar:
            self.toolbar.deleteLater()
        self.iface.removePluginMenu("Ribasim", self.action_open)
        self.iface.removePluginMenu("Ribasim", self.action_run)
        self.iface.removePluginMenu("Ribasim", self.action_reload)
        self.iface.removePluginMenu("Ribasim", self.action_set_home)
        self.iface.removePluginMenu("Ribasim", self.action_timeseries)
        self.iface.unregisterCustomDropHandler(self.drop_handler)
