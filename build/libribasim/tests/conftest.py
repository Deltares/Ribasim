from ctypes import byref, c_int, create_string_buffer
from pathlib import Path

import pytest
from xmipy import XmiWrapper


@pytest.fixture(scope="session")
def libribasim_paths() -> tuple[Path, Path]:
    test_dir = Path(__file__).parent.resolve()
    lib_folder = test_dir.parent.parent / "create_binaries" / "libribasim" / "bin"
    lib_path = lib_folder / "libribasim"
    return lib_path, lib_folder


@pytest.fixture(scope="session", autouse=True)
def load_julia(libribasim_paths) -> None:
    lib_path, lib_folder = libribasim_paths
    libribasim = XmiWrapper(lib_path, lib_folder)
    argument = create_string_buffer(0)
    libribasim.lib.init_julia(c_int(0), byref(argument))


@pytest.fixture
def ribasim_basic(libribasim_paths, request) -> tuple[XmiWrapper, str]:
    lib_path, lib_folder = libribasim_paths
    libribasim = XmiWrapper(lib_path, lib_folder)

    # If initialized, call finalize() at end of use
    request.addfinalizer(libribasim.__del__)

    repo_root = Path(__file__).parent.parent.parent.parent.resolve()
    config_file = str(repo_root / "data" / "basic" / "basic.toml")

    return libribasim, config_file
