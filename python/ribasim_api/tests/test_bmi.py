def test_initialize(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)


def test_update(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    libribasim.update()
