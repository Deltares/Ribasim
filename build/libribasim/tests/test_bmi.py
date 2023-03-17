from ctypes import CDLL, byref, c_char_p, c_int, create_string_buffer
from pathlib import Path

from xmipy import XmiWrapper


def test_dummy():
    test_dir = Path(__file__).parent.resolve()
    lib_folder = test_dir.parent.parent / "create_binaries" / "libribasim" / "bin"
    lib_path = lib_folder / "libribasim"
    libribasim = XmiWrapper(lib_path, lib_folder)  # winmode for Windows

    argument = create_string_buffer(0)
    libribasim.lib.init_julia(c_int(0), byref(argument))

    config_file = str(
        (
            test_dir.parent.parent.parent.parent / "data" / "basic" / "basic.toml"
        ).resolve()
    )

    libribasim.initialize(str(config_file))

    libribasim.update()
