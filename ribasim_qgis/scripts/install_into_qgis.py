from pathlib import Path

target_path = Path("ribasim_qgis").absolute()
source_path = Path(".pixi/env/Library/python/plugins/ribasim_qgis")

source_path.unlink(missing_ok=True)
source_path.symlink_to(target_path, target_is_directory=True)
