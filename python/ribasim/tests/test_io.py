import ribasim
from numpy.testing import assert_array_equal
from pandas.testing import assert_frame_equal


def assert_equal(a, b):
    "pandas.testing.assert_frame_equal, but ignoring the index"
    # TODO support assert basic == model, ignoring the index for all but node
    a = a.reset_index(drop=True)
    b = b.reset_index(drop=True)

    # avoid comparing datetime64[ns] with datetime64[ms]
    if "time" in a:
        a["time"] = a.time.astype("datetime64[ns]")
        b["time"] = b.time.astype("datetime64[ns]")

    return assert_frame_equal(a, b)


def test_basic(basic, tmp_path):
    model = basic
    model.write(tmp_path / "basic")
    model = ribasim.Model.from_toml(tmp_path / "basic/basic.toml")

    assert model.modelname == "basic"
    index_a = basic.node.static.index.to_numpy(int)
    index_b = model.node.static.index.to_numpy(int)
    assert_array_equal(index_a, index_b)
    assert_equal(basic.node.static, model.node.static)
    assert_equal(basic.edge.static, model.edge.static)
    assert model.basin.forcing is None


def test_basic_transient(basic_transient, tmp_path):
    model = basic_transient
    model.write(tmp_path / "basic-transient")
    model = ribasim.Model.from_toml(tmp_path / "basic-transient/basic-transient.toml")

    assert model.modelname == "basic-transient"
    assert_equal(basic_transient.node.static, model.node.static)
    assert_equal(basic_transient.edge.static, model.edge.static)

    forcing = model.basin.forcing
    assert_equal(basic_transient.basin.forcing, forcing)
    assert forcing.shape == (1468, 7)
