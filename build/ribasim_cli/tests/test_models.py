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
    model.write(tmp_path / model_name)

    executable = (
        Path(__file__).parents[2]
        / "create_binaries"
        / "ribasim_cli"
        / "bin"
        / "ribasim.exe"
    )
    config_file = str(tmp_path / "ribasim.toml")
    result = subprocess.run([executable, config_file])

    if model_name.startswith("invalid_"):
        assert result.returncode != 0
    else:
        assert result.returncode == 0
