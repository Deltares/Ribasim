"""
This script initializes the plugin, making it known to QGIS.
"""


def classFactory(iface):  # pylint: disable=invalid-name
    from ribasim_qgis.ribasim_qgis import RibasimPlugin

    return RibasimPlugin(iface)
