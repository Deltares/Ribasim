import ribasim
from pandas.testing import assert_frame_equal


def assert_equal(a, b, geometry=True):
    "pandas.testing.assert_frame_equal, but ignoring the index"
    a = a.reset_index(drop=True)
    b = b.reset_index(drop=True)

    # Currently nonspatial tables are read into GeoDataFrames with a geometry column
    # filled with None, leading to inequalities. Allow ignoring these.
    # TODO load only node and edge tables to a GeoDataFrame
    # TODO support assert basic == model, ignoring the index for all but node
    if not geometry:
        a = a.drop(columns="geometry", errors="ignore")
        b = b.drop(columns="geometry", errors="ignore")

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
    assert_frame_equal(basic.node.static, model.node.static)
    assert_equal(basic.edge.static, model.edge.static)
    assert model.basin.forcing is None


def test_basic_transient(basic_transient, tmp_path):
    model = basic_transient
    model.write(tmp_path / "basic-transient")
    model = ribasim.Model.from_toml(tmp_path / "basic-transient/basic-transient.toml")

    assert model.modelname == "basic-transient"
    assert_frame_equal(basic_transient.node.static, model.node.static)
    assert_equal(basic_transient.edge.static, model.edge.static)

    forcing = model.basin.forcing
    assert_equal(basic_transient.basin.forcing, forcing, geometry=False)
    assert forcing.shape == (1468, 8)
