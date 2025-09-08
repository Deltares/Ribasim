import os
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

    if model.experimental.allocation:
        pytest.skip("Model uses allocation which is not stable.")

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


def test_threads_cli_argument(tmp_path):
    """Test that the --threads CLI argument is properly handled."""
    # Create a minimal test model
    model = ribasim_testmodels.basic_model()
    model.write(tmp_path / "ribasim.toml")

    # Test with specific thread count
    result = subprocess.run(
        [executable, "--threads", "2", tmp_path / "ribasim.toml"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "threads = 2" in result.stderr


def test_threads_env_var(tmp_path):
    """Test that JULIA_NUM_THREADS environment variable is respected."""
    model = ribasim_testmodels.basic_model()
    model.write(tmp_path / "ribasim.toml")

    # Test with environment variable set
    env = os.environ.copy()
    env["JULIA_NUM_THREADS"] = "3"

    result = subprocess.run(
        [executable, tmp_path / "ribasim.toml"], env=env, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert "threads = 3" in result.stderr


def test_threads_cli_overrides_env(tmp_path):
    """Test that CLI --threads argument overrides JULIA_NUM_THREADS env var."""
    model = ribasim_testmodels.basic_model()
    model.write(tmp_path / "ribasim.toml")

    # Set environment variable to one value
    env = os.environ.copy()
    env["JULIA_NUM_THREADS"] = "3"

    # But use CLI argument with different value
    result = subprocess.run(
        [executable, "-t", "2", tmp_path / "ribasim.toml"],
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    # Should use CLI value (2), not env var value (3)
    assert "threads = 2" in result.stderr
