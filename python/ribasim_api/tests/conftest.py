import platform
from pathlib import Path

import pytest
import ribasim
from ribasim_api import RibasimApi
from ribasim_testmodels import (
    basic_model,
    basic_transient_model,
    leaky_bucket_model,
    two_basin_model,
    user_demand_model,
)


@pytest.fixture(scope="session")
def libribasim_paths() -> tuple[Path, Path]:
    repo_root = Path(__file__).parents[3].resolve()
    lib_or_bin = "bin" if platform.system() == "Windows" else "lib"
    extension = ".dll" if platform.system() == "Windows" else ".so"
    lib_folder = repo_root / "build" / "ribasim" / lib_or_bin
    lib_path = lib_folder / f"libribasim{extension}"
    return lib_path, lib_folder


@pytest.fixture(scope="session", autouse=True)
def load_julia(libribasim_paths) -> None:
    lib_path, lib_folder = libribasim_paths
    libribasim = RibasimApi(lib_path, lib_folder)
    libribasim.init_julia()


@pytest.fixture(scope="function")
def libribasim(libribasim_paths, request) -> RibasimApi:
    lib_path, lib_folder = libribasim_paths
    libribasim = RibasimApi(lib_path, lib_folder)

    # If initialized, call finalize() at end of use
    request.addfinalizer(libribasim.__del__)
    return libribasim


# we can't call fixtures directly, so we keep separate versions
@pytest.fixture(scope="session")
def basic() -> ribasim.Model:
    return basic_model()


@pytest.fixture(scope="session")
def basic_transient(basic) -> ribasim.Model:
    return basic_transient_model(basic)


@pytest.fixture(scope="session")
def leaky_bucket() -> ribasim.Model:
    return leaky_bucket_model()


@pytest.fixture(scope="session")
def user_demand() -> ribasim.Model:
    return user_demand_model()


@pytest.fixture(scope="session")
def two_basin() -> ribasim.Model:
    return two_basin_model()
