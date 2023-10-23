import subprocess
from pathlib import Path

import pytest
import ribasim
import ribasim_testmodels


@pytest.mark.parametrize(
    "model_name,model_constructor",
    ribasim_testmodels.constructors.items(),
)
def test_ribasim_cli(model_name, model_constructor, tmp_path):
    model = model_constructor()
    assert isinstance(model, ribasim.Model)
    model_path = tmp_path / model_name
    model.write(model_path)

    executable = (
        Path(__file__).parents[2]
        / "create_binaries"
        / "ribasim_cli"
        / "bin"
        / "ribasim.exe"
    )
    result = subprocess.run([executable, model_path / "ribasim.toml"])

    if model_name.startswith("invalid_"):
        assert result.returncode != 0
    else:
        assert result.returncode == 0
