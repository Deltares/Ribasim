from pathlib import Path

from enable_plugin import enable_plugin

target_path = Path("ribasim_qgis").absolute()
plugins_path = Path(".pixi/qgis_env/profiles/default/python/plugins")
source_path = plugins_path / "ribasim_qgis"

plugins_path.mkdir(parents=True, exist_ok=True)
source_path.unlink(missing_ok=True)
source_path.symlink_to(target_path, target_is_directory=True)

enable_plugin("ribasim_qgis")
