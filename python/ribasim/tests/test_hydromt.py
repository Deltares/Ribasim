from pathlib import Path

from ribasim.model import Model

# HydroMT needs to be able to read and write partial Ribasim models.
# That means, only reading the toml, only reading the geopackage, or only reading the netcdf forcing data.
# The same applies for writing.

# File reading is done recursively through the pydantic model structure.


def test_basic_components(basic_arrow, tmp_path):
    """Tests for hydromt input/output functionality.

    Ensures that we can write individual components of a Ribasim model.
    """
    # A model with the profile table as external arrow file
    model = basic_arrow

    toml_path = tmp_path / "ribasim.toml"
    db_path = tmp_path / "input" / "database.gpkg"
    arrow_path = tmp_path / "input" / "profile.arrow"
    assert model.basin.profile.filepath == Path(arrow_path.name)

    # Saves only the toml file
    model.write(toml_path, toml=True, internal=False, external=False)
    assert toml_path.exists()
    assert not db_path.exists()
    assert not arrow_path.exists()
    toml_path.unlink()

    # Saves only geopackage files without time time series data
    model.write(toml_path, toml=False, external=False)
    assert db_path.exists()
    assert not toml_path.exists()
    assert not arrow_path.exists()
    db_path.unlink()

    # Saves only forcing files with time series data
    model.write(toml_path, toml=False, internal=False)
    assert not db_path.exists()
    assert not toml_path.exists()
    assert arrow_path.exists()
    arrow_path.unlink()

    # Saves individual forcing table (arrow, netcdf, etc.)
    model.basin.profile.write()
    assert not toml_path.exists()
    assert not db_path.exists()
    assert arrow_path.exists()
    arrow_path.unlink()

    # Saves individual non-forcing table (gpkg)
    model.basin.static.write()
    assert not toml_path.exists()
    assert db_path.exists()
    assert not arrow_path.exists()
    db_path.unlink()


def test_basic_lazy_read(basic, tmp_path):
    # Setup
    toml_path = tmp_path / "ribasim.toml"
    basic.write(toml_path)

    # Lazy model read yields only a config
    # with empty spatial (node/link tables) and no other tables
    model = Model.read(toml_path, internal=False, external=False)

    assert len(model.node_table().df) == 0
    assert len(model.link.df) == 0  # Link Table is always initialized
    assert model.basin.static.df is None
    assert model.basin.static.lazy

    assert model.starttime == basic.starttime
    assert model.basin.time.df is None
    assert model.basin.time.lazy

    # Writing this lazy model is possible and yields the same
    model.write(toml_path)
    new_model = Model.read(toml_path)
    assert new_model.basin.static.df is None
    assert len(new_model.node_table().df) == 0
    assert len(new_model.link.df) == 0

    # We can read individual tables from the lazy model
    basic.write(toml_path)
    model = Model.read(toml_path, internal=False, external=False)
    # The directory path is retrieved from the model
    assert model.basin.root == model
    assert model.basin.static.root == model
    model.basin.static.read()
    assert model.basin.static.df is not None
    assert not model.basin.static.lazy
