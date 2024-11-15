import re
import subprocess
from pathlib import Path

import pytest
import ribasim
import ribasim_testmodels

executable = Path(__file__).parents[1] / "ribasim" / "ribasim"


@pytest.mark.parametrize(
    "model_constructor",
    ribasim_testmodels.constructors.values(),
)
def test_models(model_constructor, tmp_path):
    model = model_constructor()
    assert isinstance(model, ribasim.Model)
    model.write(tmp_path / "ribasim.toml")

    result = subprocess.run([executable, tmp_path / "ribasim.toml"])

    if model_constructor.__name__.startswith("invalid_"):
        assert result.returncode != 0
    else:
        assert result.returncode == 0


def test_version():
    result = subprocess.run(
        [executable, "--version"], check=True, capture_output=True, text=True
    )

    # ribasim --version is based on the git tag so can be different from
    # ribasim.__version__ during development
    version_pattern = r"ribasim \d{4,}\.\d+\.\d+"
    assert re.match(version_pattern, result.stdout)


def test_help():
    subprocess.run([executable, "--help"], check=True)


def test_missing_toml():
    result = subprocess.run([executable, "/there/is/no/toml"])
    assert result.returncode != 0
