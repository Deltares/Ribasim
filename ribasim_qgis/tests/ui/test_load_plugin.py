from qgis.testing import unittest
from qgis.utils import iface, plugins


class TestPlugin(unittest.TestCase):
    def test_plugin_is_loaded(self):
        """Test plugin is properly loaded and appears in QGIS plugins."""
        plugin = plugins.get("ribasim_qgis")
        self.assertTrue(plugin, "Ribasim plugin not loaded")

    def test_plugin(self):
        """Triggers Ribasim button and checks that Dock is added."""
        # This checks the *actual* QGIS interface, not just a stub
        self.assertTrue(iface is not None, "QGIS interface not available")

        toolbars = [
            c for c in iface.mainWindow().children() if c.objectName() == "Ribasim"
        ]
        self.assertTrue(len(toolbars) == 1, "No (single) Ribasim toolbar")
        actions = toolbars[0].actions()
        self.assertTrue(
            len(actions) == 1, "No (single) Ribasim action button in toolbar"
        )

        docks = [
            c for c in iface.mainWindow().children() if c.objectName() == "RibasimDock"
        ]
        self.assertTrue(len(docks) == 0, "Ribasim dock already activated")

        actions[0].trigger()

        docks = [
            c for c in iface.mainWindow().children() if c.objectName() == "RibasimDock"
        ]
        self.assertTrue(len(docks) == 1, "Ribasim dock not activated")
