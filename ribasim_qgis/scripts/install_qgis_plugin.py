import os
import shutil
import subprocess
import sys
from pathlib import Path


def install_qgis_plugin(plugin_name: str, profile_path: str) -> None:
    plugin_path = Path(profile_path) / "python/plugins"
    plugin_path.mkdir(parents=True, exist_ok=True)

    try:
        subprocess.check_call(["qgis-plugin-manager", "init"], cwd=plugin_path)
        subprocess.check_call(["qgis-plugin-manager", "update"], cwd=plugin_path)
        subprocess.check_call(
            ["qgis-plugin-manager", "install", plugin_name], cwd=plugin_path
        )
    finally:
        # remove the qgis-manager-plugin cache, because QGIS tries to load it as a plugin
        os.remove(plugin_path / "sources.list")
        shutil.rmtree(plugin_path / ".cache_qgis_plugin_manager")


if __name__ == "__main__":
    print(f"Installing QGIS plugin {sys.argv[1]} to profile {sys.argv[2]}")
    install_qgis_plugin(sys.argv[1], sys.argv[2])
