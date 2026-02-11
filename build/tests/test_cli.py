import os
import re
import subprocess
from pathlib import Path

import pytest
import ribasim
import ribasim_testmodels
from ribasim.cli import run_ribasim

ribasim_home = Path(__file__).parents[1] / "ribasim"
executable = ribasim_home / "bin/ribasim"


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


def test_threads_default(tmp_path):
    """Test that ribasim runs without threads arg or env var."""
    model = ribasim_testmodels.basic_model()
    model.write(tmp_path / "ribasim.toml")

    # Remove JULIA_NUM_THREADS if it exists
    env = os.environ.copy()
    env.pop("JULIA_NUM_THREADS", None)

    result = subprocess.run(
        [executable, tmp_path / "ribasim.toml"],
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0


def test_threads_cli_argument(tmp_path):
    """Test ribasim --threads 2."""
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
    """Test that JULIA_NUM_THREADS environment variable is not used."""
    model = ribasim_testmodels.basic_model()
    model.write(tmp_path / "ribasim.toml")

    # Test with environment variable set
    env = os.environ.copy()
    env["JULIA_NUM_THREADS"] = "3"

    result = subprocess.run(
        [executable, tmp_path / "ribasim.toml"], env=env, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert "threads = 1" in result.stderr


def test_run_ribasim_basic(tmp_path):
    """Test run_ribasim() with a basic model using ribasim_home."""
    model = ribasim_testmodels.basic_model()
    toml_path = tmp_path / "ribasim.toml"
    model.write(toml_path)

    # Should run successfully
    run_ribasim(toml_path, ribasim_home=ribasim_home)

    # Check that results were produced
    results_path = tmp_path / "results" / "basin.nc"
    assert results_path.exists()


def test_run_ribasim_with_threads(tmp_path):
    """Test run_ribasim() with threads argument."""
    model = ribasim_testmodels.basic_model()
    toml_path = tmp_path / "ribasim.toml"
    model.write(toml_path)

    # Pass threads kwarg
    run_ribasim(toml_path, ribasim_home=ribasim_home, threads=2)

    # Check that threads were set correctly in the log
    log_path = tmp_path / "results" / "ribasim.log"
    assert log_path.exists()
    log_content = log_path.read_text()
    assert "threads = 2" in log_content


def test_run_ribasim_version(capfd):
    """Test run_ribasim() with version=True."""
    run_ribasim(version=True, ribasim_home=ribasim_home)

    # Capture the output
    captured = capfd.readouterr()

    # Check that version output was printed
    version_pattern = r"ribasim \d{4,}\.\d+\.\d+"
    assert re.search(version_pattern, captured.out)


def test_run_ribasim_no_args():
    """Test run_ribasim() raises ValueError with no arguments."""
    with pytest.raises(ValueError, match="Provide a toml_path, or set version=True"):
        run_ribasim()


def test_run_ribasim_not_on_path(tmp_path):
    """Test run_ribasim() raises FileNotFoundError when ribasim is not on PATH."""
    model = ribasim_testmodels.basic_model()
    toml_path = tmp_path / "ribasim.toml"
    model.write(toml_path)

    # Save and clear PATH and RIBASIM_HOME
    old_path = os.environ.get("PATH", "")
    old_ribasim_home = os.environ.get("RIBASIM_HOME")
    os.environ["PATH"] = ""
    if old_ribasim_home is not None:
        del os.environ["RIBASIM_HOME"]

    try:
        with pytest.raises(
            FileNotFoundError,
            match=r"Ribasim CLI executable 'ribasim' not found\.",
        ):
            run_ribasim(toml_path)
    finally:
        os.environ["PATH"] = old_path
        if old_ribasim_home is not None:
            os.environ["RIBASIM_HOME"] = old_ribasim_home


def test_run_ribasim_with_ribasim_home(tmp_path):
    """Test run_ribasim() uses RIBASIM_HOME environment variable."""
    model = ribasim_testmodels.basic_model()
    toml_path = tmp_path / "ribasim.toml"
    model.write(toml_path)

    # Save current RIBASIM_HOME and PATH
    old_ribasim_home = os.environ.get("RIBASIM_HOME")
    old_path = os.environ.get("PATH", "")

    try:
        # Set RIBASIM_HOME to the home directory and clear PATH
        os.environ["RIBASIM_HOME"] = str(ribasim_home)
        os.environ["PATH"] = ""  # Clear PATH to ensure RIBASIM_HOME is used

        # Should find executable via RIBASIM_HOME
        run_ribasim(toml_path)

        # Check that results were produced
        results_path = tmp_path / "results" / "basin.nc"
        assert results_path.exists()
    finally:
        # Restore environment
        os.environ["PATH"] = old_path
        if old_ribasim_home is not None:
            os.environ["RIBASIM_HOME"] = old_ribasim_home
        else:
            os.environ.pop("RIBASIM_HOME", None)


def test_run_ribasim_ribasim_home_invalid_path(tmp_path):
    """Test run_ribasim() raises FileNotFoundError with invalid RIBASIM_HOME."""
    model = ribasim_testmodels.basic_model()
    toml_path = tmp_path / "ribasim.toml"
    model.write(toml_path)

    # Save current RIBASIM_HOME and PATH
    old_ribasim_home = os.environ.get("RIBASIM_HOME")
    old_path = os.environ.get("PATH", "")

    try:
        # Set invalid RIBASIM_HOME
        invalid_path = tmp_path / "nonexistent"
        os.environ["RIBASIM_HOME"] = str(invalid_path)
        os.environ["PATH"] = ""  # Clear PATH to ensure RIBASIM_HOME is used

        with pytest.raises(
            FileNotFoundError,
            match=r"Ribasim CLI executable not found at RIBASIM_HOME=",
        ):
            run_ribasim(toml_path)
    finally:
        # Restore environment
        os.environ["PATH"] = old_path
        if old_ribasim_home is not None:
            os.environ["RIBASIM_HOME"] = old_ribasim_home
        else:
            os.environ.pop("RIBASIM_HOME", None)


def test_run_ribasim_invalid_model(tmp_path):
    """Test run_ribasim() raises CalledProcessError on invalid model."""
    model = ribasim_testmodels.invalid_discrete_control_model()
    toml_path = tmp_path / "ribasim.toml"
    model.write(toml_path)

    with pytest.raises(subprocess.CalledProcessError):
        run_ribasim(toml_path, ribasim_home=ribasim_home)


def test_run_ribasim_in_notebook(tmp_path, monkeypatch):
    """Test run_ribasim() in notebook mode by mocking _subprocess_handling."""
    from ribasim import cli
    from ribasim.cli import SubprocessHandling

    model = ribasim_testmodels.basic_model()
    toml_path = tmp_path / "ribasim.toml"
    model.write(toml_path)

    # Mock _subprocess_handling to return DISPLAY (notebook mode)
    monkeypatch.setattr(cli, "_subprocess_handling", lambda: SubprocessHandling.DISPLAY)

    # Should run successfully using the notebook path
    run_ribasim(toml_path, ribasim_home=ribasim_home)

    # Check that results were produced
    results_path = tmp_path / "results" / "basin.nc"
    assert results_path.exists()


def test_run_ribasim_in_spyder(tmp_path, monkeypatch):
    """Test run_ribasim() in Spyder mode by mocking _subprocess_handling."""
    from ribasim import cli
    from ribasim.cli import SubprocessHandling

    model = ribasim_testmodels.basic_model()
    toml_path = tmp_path / "ribasim.toml"
    model.write(toml_path)

    # Mock _subprocess_handling to return SPYDER
    monkeypatch.setattr(cli, "_subprocess_handling", lambda: SubprocessHandling.SPYDER)

    # Should run successfully using the Spyder path
    run_ribasim(toml_path, ribasim_home=ribasim_home)

    # Check that results were produced
    results_path = tmp_path / "results" / "basin.nc"
    assert results_path.exists()
