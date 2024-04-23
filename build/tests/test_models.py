import subprocess
from pathlib import Path

import pytest
import ribasim
import ribasim_testmodels


@pytest.mark.parametrize(
    "model_constructor",
    ribasim_testmodels.constructors.values(),
)
def test_ribasim_cli(model_constructor, tmp_path):
    model = model_constructor()
    assert isinstance(model, ribasim.Model)
    model.write(tmp_path / "ribasim.toml")

    executable = Path(__file__).parents[1] / "ribasim" / "ribasim"
    result = subprocess.run([executable, tmp_path / "ribasim.toml"])

    if model_constructor.__name__.startswith("invalid_"):
        assert result.returncode != 0
    else:
        assert result.returncode == 0
