from pathlib import Path

import pytest
import ribasim
import ribasim_testmodels


# we can't call fixtures directly, so we keep separate versions
@pytest.fixture()
def basic() -> ribasim.Model:
    return ribasim_testmodels.basic_model()


@pytest.fixture()
def basic_transient() -> ribasim.Model:
    return ribasim_testmodels.basic_transient_model()


@pytest.fixture()
def tabulated_rating_curve() -> ribasim.Model:
    return ribasim_testmodels.tabulated_rating_curve_model()


@pytest.fixture()
def backwater() -> ribasim.Model:
    return ribasim_testmodels.backwater_model()


# write models to disk for Julia tests to use
if __name__ == "__main__":
    datadir = Path("data")

    models = [
        model_generator()
        for model_generator in map(
            ribasim_testmodels.__dict__.get, ribasim_testmodels.__all__
        )
    ]

    for model in models:
        model.write(datadir / model.modelname)
