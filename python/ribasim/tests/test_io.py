import pandas as pd
import pandera as pa
import pytest
import ribasim
from numpy.testing import assert_array_equal
from pandas.testing import assert_frame_equal
from pandera.typing import DataFrame, Series
from pydantic import BaseModel, ValidationError
from ribasim import Pump


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
    static_data_proper = pd.DataFrame(
        data=dict(node_id=[1, 2, 3], flow_rate=[1.0, -1.0, 0.0])
    )

    static_data_bad_1 = pd.DataFrame(data=dict(node_id=[1, 2, 3]))

    pump_1 = Pump()


if __name__ == "__main__":
    test_pydantic()


# def test_input_mixin():
#     class Schema(pa.SchemaModel):
#         col_x: Series[int] = pa.Field(coerce=True)
#         col_y: Series[float]

#     class Dummy(ribasim.input_base.InputMixin, BaseModel):
#         myfield_a: int
#         myfield_b: float
#         myfield_c: DataFrame[Schema]

#     proper_c = pd.DataFrame(data={"col_x": [1], "col_y": [1.0]})
#     bad_c = pd.DataFrame(data={"col_y": [1.0]})

#     dummy_1 = Dummy(myfield_a=1, myfield_b=1, myfield_c=proper_c)

#     # Type cast if possible is allowed (myfield_b int -> float)
#     assert (
#         repr(dummy_1)
#         == "<ribasim.Dummy>\n   myfield_a: 1\n   myfield_b: 1.0\n   myfield_c: DataFrame(rows=1) (col_x, col_y)"
#     )

#     with pytest.raises(ValidationError) as exc_info:
#         Dummy(myfield_a=1, myfield_b=1, myfield_c=bad_c)

#     assert exc_info.value.errors()[0]["loc"] == ("myfield_c",)


# if __name__ == "__main__":
#     test_input_mixin()
