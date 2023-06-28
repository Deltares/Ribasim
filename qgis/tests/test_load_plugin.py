from qgis.testing import unittest
from qgis.utils import iface, plugins


class TestPlugin(unittest.TestCase):
    def test_plugin_is_loaded(self):
        plugin = plugins.get("ribasim_qgis")
        self.assertTrue(plugin)

    def test_load_dock(self):
        # Check *actual* QGIS interface, not just a stub
        self.assertTrue(iface is not None)

        # Trigger Ribasim button and check that Dock is added
        toolbars = [
            c for c in iface.mainWindow().children() if c.objectName() == "Ribasim"
        ]
        self.assertTrue(len(toolbars) == 1)
        actions = toolbars[0].actions()
        self.assertTrue(len(actions) == 1)

        docks = [
            c for c in iface.mainWindow().children() if c.objectName() == "RibasimDock"
        ]
        self.assertTrue(len(docks) == 0)

        actions[0].trigger()

        docks = [
            c for c in iface.mainWindow().children() if c.objectName() == "RibasimDock"
        ]
        self.assertTrue(len(docks) == 1)
