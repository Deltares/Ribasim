import configparser
import sys
from pathlib import Path


def enable_plugin(plugin_name: str, profile_path: str) -> None:
    config_file = Path(profile_path) / "QGIS/QGIS3.ini"
    config_file.parent.mkdir(parents=True, exist_ok=True)
    config_file.touch()

    config = configparser.ConfigParser()
    config.read(config_file)

    plugins_section = "PythonPlugins"
    if not config.has_section(plugins_section):
        config.add_section(plugins_section)

    config[plugins_section][plugin_name] = "true"

    with config_file.open("w") as f:
        config.write(f)


if __name__ == "__main__":
    print(f"Enabling QGIS plugin {sys.argv[1]} in profile {sys.argv[2]}")
    enable_plugin(sys.argv[1], sys.argv[2])
