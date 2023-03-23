from pathlib import Path

import pytest

from ribasim_api import RibasimApi


@pytest.fixture(scope="session")
def libribasim_paths() -> tuple[Path, Path]:
    repo_root = Path(__file__).parents[2].resolve()
    lib_folder = repo_root / "build" / "create_binaries" / "libribasim" / "bin"
    lib_path = lib_folder / "libribasim"
    return lib_path, lib_folder


@pytest.fixture(scope="session", autouse=True)
def load_julia(libribasim_paths) -> None:
    lib_path, lib_folder = libribasim_paths
    libribasim = RibasimApi(lib_path, lib_folder)
    libribasim.init_julia()


@pytest.fixture
def ribasim_basic(libribasim_paths, request) -> tuple[RibasimApi, str]:
    lib_path, lib_folder = libribasim_paths
    libribasim = RibasimApi(lib_path, lib_folder)

    # If initialized, call finalize() at end of use
    request.addfinalizer(libribasim.__del__)

    repo_root = Path(__file__).parents[2].resolve()
    config_file = str(repo_root / "data" / "basic" / "basic.toml")

    return libribasim, config_file
