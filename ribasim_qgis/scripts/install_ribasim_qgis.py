from pathlib import Path

from enable_plugin import enable_plugin

target_path = Path("ribasim_qgis").absolute()
plugins_path = Path(".pixi/qgis_env/profiles/default/python/plugins")
source_path = plugins_path / "ribasim_qgis"

styles_source_path = source_path / "core" / "styles"
styles_target_path = Path("python/ribasim/ribasim/styles").absolute()

plugins_path.mkdir(parents=True, exist_ok=True)
source_path.unlink(missing_ok=True)
source_path.symlink_to(target_path, target_is_directory=True)

styles_source_path.unlink(missing_ok=True)
styles_source_path.symlink_to(styles_target_path, target_is_directory=True)

enable_plugin("ribasim_qgis")
