import configparser

import platformdirs


def enable_plugin(plugin_name: str) -> None:
    config_file = (
        platformdirs.user_state_path(roaming=True)
        / "QGIS"
        / "QGIS3"
        / "profiles"
        / "default"
        / "QGIS"
        / "QGIS3.ini"
    )

    config_file.touch()

    config = configparser.ConfigParser()
    config.read(config_file)

    plugins_section = "PythonPlugins"
    if not config.has_section(plugins_section):
        config.add_section(plugins_section)

    config[plugins_section][plugin_name] = "true"

    with config_file.open("w") as f:
        config.write(f)
