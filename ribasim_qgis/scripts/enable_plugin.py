import configparser
import re
import sys
from pathlib import Path


def validate_plugin_name(plugin_name: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", plugin_name):
        raise ValueError(f"Invalid plugin name: {plugin_name!r}")
    return plugin_name


def resolve_profile_path(profile_path: str) -> Path:
    """Resolve the QGIS profile path, which must be inside the working directory."""
    root = Path.cwd().resolve()
    resolved = (root / profile_path).resolve()
    if not resolved.is_relative_to(root):
        raise ValueError(f"Profile path must be inside {root}: {profile_path!r}")
    return resolved


def enable_plugin(plugin_name: str, profile_path: str) -> None:
    validate_plugin_name(plugin_name)
    config_file = resolve_profile_path(profile_path) / "QGIS/QGIS3.ini"
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
