import subprocess
from pathlib import Path

import pytest
import ribasim
import ribasim_testmodels


@pytest.mark.parametrize(
    "model_constructor",
    map(ribasim_testmodels.__dict__.get, ribasim_testmodels.__all__),
)
def test_ribasim_cli(model_constructor, tmp_path):
    model = model_constructor()
    assert isinstance(model, ribasim.Model)
    model.write(tmp_path)

    executable = (
        Path(__file__).parents[2]
        / "create_binaries"
        / "ribasim_cli"
        / "bin"
        / "ribasim.exe"
    )
    config_file = str(tmp_path / f"{model.modelname}.toml")
    result = subprocess.run([executable, config_file], check=True)

    if model.modelname.startswith("invalid"):
        assert result.returncode != 0
    else:
        assert result.returncode == 0
