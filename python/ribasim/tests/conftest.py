import pytest
import ribasim
import ribasim_testmodels


@pytest.fixture(autouse=True, scope="session")
def _configure_matplotlib():
    """Force matplotlib to use the non-interactive 'Agg' backend for testing."""
    import matplotlib

    matplotlib.use("Agg")


# we can't call fixtures directly, so we keep separate versions
@pytest.fixture()
def basic() -> ribasim.Model:
    return ribasim_testmodels.basic_model()


@pytest.fixture()
def basic_transient() -> ribasim.Model:
    return ribasim_testmodels.basic_transient_model()


@pytest.fixture()
def bucket() -> ribasim.Model:
    return ribasim_testmodels.bucket_model()


@pytest.fixture()
def pid_control_equation() -> ribasim.Model:
    return ribasim_testmodels.pid_control_equation_model()


@pytest.fixture()
def tabulated_rating_curve() -> ribasim.Model:
    return ribasim_testmodels.tabulated_rating_curve_model()


@pytest.fixture()
def outlet() -> ribasim.Model:
    return ribasim_testmodels.outlet_model()


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


@pytest.fixture()
def tabulated_rating_curve_control() -> ribasim.Model:
    return ribasim_testmodels.tabulated_rating_curve_control_model()


@pytest.fixture()
def drought() -> ribasim.Model:
    return ribasim_testmodels.drought_model()
