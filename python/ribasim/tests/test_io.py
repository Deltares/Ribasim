import pandas as pd
import pytest
import ribasim
from numpy.testing import assert_array_equal
from pandas.testing import assert_frame_equal
from pydantic import ValidationError
from ribasim import Pump


def assert_equal(a, b):
    """Like pandas.testing.assert_frame_equal, but ignoring the index."""

    # TODO support assert basic == model, ignoring the index for all but node
    a = a.reset_index(drop=True)
    b = b.reset_index(drop=True)

    # avoid comparing datetime64[ns] with datetime64[ms]
    if "time" in a:
        a["time"] = a.time.astype("datetime64[ns]")
        b["time"] = b.time.astype("datetime64[ns]")

    return assert_frame_equal(a, b)


def test_basic(basic, tmp_path):
    model_orig = basic
    model_orig.write(tmp_path / "basic")
    model_loaded = ribasim.Model.from_toml(tmp_path / "basic/basic.toml")

    assert model_orig.modelname == model_loaded.modelname
    index_a = model_orig.node.static.index.to_numpy(int)
    index_b = model_loaded.node.static.index.to_numpy(int)
    assert_array_equal(index_a, index_b)
    assert_equal(model_orig.node.static, model_loaded.node.static)
    assert_equal(model_orig.edge.static, model_loaded.edge.static)
    assert model_loaded.basin.forcing is None


def test_basic_transient(basic_transient, tmp_path):
    model_orig = basic_transient
    model_orig.write(tmp_path / "basic-transient")
    model_loaded = ribasim.Model.from_toml(
        tmp_path / "basic-transient/basic-transient.toml"
    )

    assert model_orig.modelname == model_loaded.modelname
    assert_equal(model_orig.node.static, model_loaded.node.static)
    assert_equal(model_orig.edge.static, model_loaded.edge.static)

    forcing = model_loaded.basin.forcing
    assert_equal(model_orig.basin.forcing, forcing)
    assert forcing.shape == (1468, 8)


def test_pydantic():
    static_data_bad = pd.DataFrame(data={"node_id": [1, 2, 3]})

    with pytest.raises(ValidationError):
        Pump(static=static_data_bad)


def test_repr():
    static_data_proper = pd.DataFrame(
        data={"node_id": [1, 2, 3], "flow_rate": [1.0, -1.0, 0.0]}
    )

    pump_1 = Pump(static=static_data_proper)

    assert (
        repr(pump_1)
        == "<ribasim.Pump>\n   static: DataFrame(rows=3) (remarks, flow_rate, node_id, control_state)"
    )
