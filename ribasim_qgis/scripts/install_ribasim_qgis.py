from pathlib import Path

from enable_plugin import enable_plugin

target_path = Path("ribasim_qgis").absolute()
source_path = Path(".pixi/env/share/qgis/python/plugins/ribasim_qgis")

source_path.unlink(missing_ok=True)
source_path.symlink_to(target_path, target_is_directory=True)

enable_plugin("ribasim_qgis")
