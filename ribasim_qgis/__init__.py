"""A script which initializes the plugin, making it known to QGIS."""
__version__ = "0.1.0"


def classFactory(iface):  # pylint: disable=invalid-name
    from ribasim_qgis.ribasim_qgis import RibasimPlugin

    return RibasimPlugin(iface)
