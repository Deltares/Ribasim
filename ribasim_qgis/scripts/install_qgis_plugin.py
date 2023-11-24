import os
import shutil
import subprocess
from pathlib import Path


def install_qgis_plugin(plugin_name: str):
    plugin_path = Path(".pixi/env/Library/python/plugins")

    subprocess.call("qgis-plugin-manager init", cwd=plugin_path)
    subprocess.call("qgis-plugin-manager update", cwd=plugin_path)
    subprocess.check_call(
        f'qgis-plugin-manager install "{plugin_name}"', cwd=plugin_path
    )

    # remove the qgis-manager-plugin cache, because QGIS tries to load it as a plugin
    os.remove(plugin_path / "sources.list")
    shutil.rmtree(plugin_path / ".cache_qgis_plugin_manager")
