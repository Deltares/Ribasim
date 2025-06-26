import platform
import shutil
from pathlib import Path

from enable_plugin import enable_plugin

target_path = Path("ribasim_qgis").absolute()
plugins_path = Path(".pixi/qgis_env/profiles/default/python/plugins")
source_path = plugins_path / "ribasim_qgis"

styles_source_path = target_path / "core" / "styles"
styles_target_path = Path("python/ribasim/ribasim/styles").absolute()

# Handle styles directory
styles_source_path.unlink(missing_ok=True)
if styles_source_path.exists():
    shutil.rmtree(styles_source_path)

if platform.system() == "Windows":
    # On Windows, copy instead of symlink to avoid privilege issues
    shutil.copytree(styles_target_path, styles_source_path)
else:
    # On Unix-like systems, use symlink
    styles_source_path.symlink_to(styles_target_path, target_is_directory=True)

# Handle plugin directory
plugins_path.mkdir(parents=True, exist_ok=True)
source_path.unlink(missing_ok=True)
if source_path.exists():
    shutil.rmtree(source_path)

if platform.system() == "Windows":
    # On Windows, copy instead of symlink to avoid privilege issues
    shutil.copytree(target_path, source_path)
else:
    # On Unix-like systems, use symlink
    source_path.symlink_to(target_path, target_is_directory=True)

enable_plugin("ribasim_qgis")
