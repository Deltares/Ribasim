import pytest
import ribasim
import ribasim_testmodels


# we can't call fixtures directly, so we keep separate versions
@pytest.fixture()
def basic() -> ribasim.Model:
    return ribasim_testmodels.basic_model()


@pytest.fixture()
def basic_arrow() -> ribasim.Model:
    return ribasim_testmodels.basic_arrow_model()


@pytest.fixture()
def basic_transient() -> ribasim.Model:
    return ribasim_testmodels.basic_transient_model()


@pytest.fixture()
def bucket() -> ribasim.Model:
    return ribasim_testmodels.bucket_model()


@pytest.fixture()
def tabulated_rating_curve() -> ribasim.Model:
    return ribasim_testmodels.tabulated_rating_curve_model()


@pytest.fixture()
def backwater() -> ribasim.Model:
    return ribasim_testmodels.backwater_model()


@pytest.fixture()
def discrete_control_of_pid_control() -> ribasim.Model:
    return ribasim_testmodels.discrete_control_of_pid_control_model()


@pytest.fixture()
def level_range() -> ribasim.Model:
    return ribasim_testmodels.level_range_model()


@pytest.fixture()
def trivial() -> ribasim.Model:
    return ribasim_testmodels.trivial_model()
