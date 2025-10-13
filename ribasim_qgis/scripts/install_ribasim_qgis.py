import sys
from pathlib import Path

from enable_plugin import enable_plugin

if __name__ == "__main__":
    target_path = Path("ribasim_qgis").absolute()
    plugins_path = Path(sys.argv[1]) / "python/plugins"
    source_path = plugins_path / "ribasim_qgis"

    styles_source_path = target_path / "core" / "styles"
    styles_target_path = Path("python/ribasim/ribasim/styles").absolute()

    # Symlink ribasim_qgis styles to ribasim styles
    styles_source_path.unlink(missing_ok=True)
    styles_source_path.symlink_to(styles_target_path, target_is_directory=True)

    # Symlink qgis_env to ribasim_qgis, and hence qgis_env styles to ribasim styles
    plugins_path.mkdir(parents=True, exist_ok=True)
    source_path.unlink(missing_ok=True)
    source_path.symlink_to(target_path, target_is_directory=True)
    enable_plugin("ribasim_qgis", sys.argv[1])
