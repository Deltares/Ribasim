def test_initialize(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)


def test_update(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    libribasim.update()


def test_get_var_type(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    var_type = libribasim.get_var_type("volume")
    assert var_type == "float64"
