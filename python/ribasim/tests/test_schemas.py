from ribasim.schemas import BasinProfileSchema


def test_config_inheritance():
    assert BasinProfileSchema.__config__.add_missing_columns
    assert BasinProfileSchema.__config__.coerce
