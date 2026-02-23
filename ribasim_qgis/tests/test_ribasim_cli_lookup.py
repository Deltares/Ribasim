from pathlib import Path

from ribasim_qgis.widgets.dataset_widget import DatasetWidget


class MessageBarSpy:
    def __init__(self):
        self.messages = []

    def pushMessage(self, title, text, **kwargs):
        self.messages.append((title, text, kwargs))


def test_ribasim_home_setting_roundtrip(monkeypatch):
    store: dict[str, str] = {}

    class FakeQgsSettings:
        def value(self, key):
            return store.get(key)

        def setValue(self, key, value):
            store[key] = value

        def remove(self, key):
            store.pop(key, None)

    monkeypatch.setattr(
        "ribasim_qgis.widgets.dataset_widget.QgsSettings", FakeQgsSettings
    )

    assert DatasetWidget.get_ribasim_home_setting() is None

    expected = Path("C:/ribasim-home")
    DatasetWidget.set_ribasim_home_setting(expected)

    assert DatasetWidget.get_ribasim_home_setting() == expected

    DatasetWidget.clear_ribasim_home_setting()

    assert DatasetWidget.get_ribasim_home_setting() is None


def test_find_ribasim_cli_uses_setting_first(monkeypatch):
    message_bar = MessageBarSpy()

    monkeypatch.setattr(
        DatasetWidget, "get_ribasim_home_setting", lambda: Path("C:/cfg")
    )
    monkeypatch.setattr(
        DatasetWidget,
        "get_ribasim_cli_from_home",
        lambda ribasim_home: Path("C:/cfg/bin/ribasim.exe"),
    )

    def should_not_be_called(*args, **kwargs):
        raise AssertionError("PATH lookup should not be used when setting is valid")

    monkeypatch.setattr(
        "ribasim_qgis.widgets.dataset_widget.shutil.which", should_not_be_called
    )

    cli = DatasetWidget._find_ribasim_cli(message_bar)

    assert cli == Path("C:/cfg/bin/ribasim.exe")


def test_find_ribasim_cli_uses_ribasim_home_env(monkeypatch):
    message_bar = MessageBarSpy()

    monkeypatch.setattr(DatasetWidget, "get_ribasim_home_setting", lambda: None)
    monkeypatch.setattr(
        "ribasim_qgis.widgets.dataset_widget.os.environ",
        {"RIBASIM_HOME": "C:/env"},
    )
    monkeypatch.setattr(
        DatasetWidget,
        "get_ribasim_cli_from_home",
        lambda ribasim_home: Path("C:/env/bin/ribasim.exe"),
    )

    cli = DatasetWidget._find_ribasim_cli(message_bar)

    assert cli == Path("C:/env/bin/ribasim.exe")


def test_find_ribasim_cli_uses_windows_apps_fallback(monkeypatch):
    message_bar = MessageBarSpy()

    monkeypatch.setattr(DatasetWidget, "get_ribasim_home_setting", lambda: None)
    monkeypatch.setattr("ribasim_qgis.widgets.dataset_widget.os.environ", {})
    monkeypatch.setattr(
        "ribasim_qgis.widgets.dataset_widget.shutil.which", lambda *args, **kwargs: None
    )
    monkeypatch.setattr(
        DatasetWidget,
        "get_windows_apps_cli",
        lambda: Path("C:/Users/user/AppData/Local/Microsoft/WindowsApps/ribasim.exe"),
    )

    cli = DatasetWidget._find_ribasim_cli(message_bar)

    assert cli == Path("C:/Users/user/AppData/Local/Microsoft/WindowsApps/ribasim.exe")


def test_find_ribasim_cli_invalid_setting_shows_error(monkeypatch):
    message_bar = MessageBarSpy()

    monkeypatch.setattr(
        DatasetWidget, "get_ribasim_home_setting", lambda: Path("C:/bad")
    )
    monkeypatch.setattr(
        DatasetWidget, "get_ribasim_cli_from_home", lambda ribasim_home: None
    )

    cli = DatasetWidget._find_ribasim_cli(message_bar)

    assert cli is None
    assert len(message_bar.messages) == 1
    title, text, _kwargs = message_bar.messages[0]
    assert title == "Error"
    assert "configured ribasim home" in text.lower()
    assert "Set Ribasim home" in text


def test_find_ribasim_cli_not_found_shows_error(monkeypatch):
    message_bar = MessageBarSpy()

    monkeypatch.setattr(DatasetWidget, "get_ribasim_home_setting", lambda: None)
    monkeypatch.setattr("ribasim_qgis.widgets.dataset_widget.os.environ", {})
    monkeypatch.setattr(
        "ribasim_qgis.widgets.dataset_widget.shutil.which", lambda *args, **kwargs: None
    )
    monkeypatch.setattr(DatasetWidget, "get_windows_apps_cli", lambda: None)

    cli = DatasetWidget._find_ribasim_cli(message_bar)

    assert cli is None
    assert len(message_bar.messages) == 1
    title, text, _kwargs = message_bar.messages[0]
    assert title == "Error"
    assert "configure Ribasim home in the plugin" in text
