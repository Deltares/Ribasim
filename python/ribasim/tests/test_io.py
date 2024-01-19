import pandas as pd
import pytest
import ribasim
from numpy.testing import assert_array_equal
from pandas import DataFrame
from pandas.testing import assert_frame_equal
from pydantic import ValidationError
from ribasim import Node, Pump


def __assert_equal(a: DataFrame, b: DataFrame) -> None:
    """Like pandas.testing.assert_frame_equal, but ignoring the index."""
    if a is None and b is None:
        return True

    # TODO support assert basic == model, ignoring the index for all but node
    a = a.reset_index(drop=True)
    b = b.reset_index(drop=True)

    # avoid comparing datetime64[ns] with datetime64[ms]
    if "time" in a:
        a["time"] = a.time.astype("datetime64[ns]")
        b["time"] = b.time.astype("datetime64[ns]")

    if "fid" in a:
        a.drop(columns=["fid"], inplace=True)
    if "fid" in b:
        b.drop(columns=["fid"], inplace=True)

    return assert_frame_equal(a, b)


def test_basic(basic, tmp_path):
    model_orig = basic
    model_orig.write(tmp_path / "basic/ribasim.toml")
    model_loaded = ribasim.Model(filepath=tmp_path / "basic/ribasim.toml")

    index_a = model_orig.network.node.df.index.to_numpy(int)
    index_b = model_loaded.network.node.df.index.to_numpy(int)
    assert_array_equal(index_a, index_b)
    __assert_equal(model_orig.network.node.df, model_loaded.network.node.df)
    __assert_equal(model_orig.network.edge.df, model_loaded.network.edge.df)
    assert model_loaded.basin.time.df is None


def test_basic_arrow(basic_arrow, tmp_path):
    model_orig = basic_arrow
    model_orig.write(tmp_path / "basic_arrow/ribasim.toml")
    model_loaded = ribasim.Model(filepath=tmp_path / "basic_arrow/ribasim.toml")

    __assert_equal(model_orig.basin.profile.df, model_loaded.basin.profile.df)


def test_basic_transient(basic_transient, tmp_path):
    model_orig = basic_transient
    model_orig.write(tmp_path / "basic_transient/ribasim.toml")
    model_loaded = ribasim.Model(filepath=tmp_path / "basic_transient/ribasim.toml")

    __assert_equal(model_orig.network.node.df, model_loaded.network.node.df)
    __assert_equal(model_orig.network.edge.df, model_loaded.network.edge.df)

    time = model_loaded.basin.time
    assert model_orig.basin.time.df.time[0] == time.df.time[0]
    __assert_equal(model_orig.basin.time.df, time.df)
    assert time.df.shape == (1468, 9)


def test_pydantic():
    static_data_bad = pd.DataFrame(data={"node_id": [1, 2, 3]})

    with pytest.raises(ValidationError):
        Pump(static=static_data_bad)


def test_repr():
    static_data = pd.DataFrame(
        data={"node_id": [1, 2, 3], "flow_rate": [1.0, -1.0, 0.0]}
    )

    pump_1 = Pump(static=static_data)
    pump_2 = Pump()

    assert repr(pump_1) == "Pump(static)"
    assert repr(pump_2) == "Pump()"
    # Ensure _repr_html doesn't error
    assert isinstance(pump_1.static._repr_html_(), str)
    assert isinstance(pump_2.static._repr_html_(), str)


def test_extra_columns(basic_transient):
    static_data = pd.DataFrame(
        data={"node_id": [1, 2, 3], "flow_rate": [1.0, -1.0, 0.0], "id": [-1, -2, -3]}
    )

    pump_1 = Pump(static=static_data)

    assert "meta_id" in pump_1.static.df.columns

    model_orig = basic_transient
    df = model_orig.network.node.df.copy()
    df["node_id"] = df.index
    node = Node(df=df)

    assert "meta_node_id" in node.df.columns


def test_sort(level_setpoint_with_minmax, tmp_path):
    model = level_setpoint_with_minmax
    table = model.discrete_control.condition

    # apply a wrong sort, then call the sort method to restore order
    table.df.sort_values("greater_than", ascending=False, inplace=True)
    assert table.df.iloc[0]["greater_than"] == 15.0
    assert table._sort_keys == [
        "node_id",
        "listen_feature_id",
        "variable",
        "greater_than",
    ]
    table.sort()
    assert table.df.iloc[0]["greater_than"] == 5.0

    # re-apply wrong sort, then check if it gets sorted on write
    table.df.sort_values("greater_than", ascending=False, inplace=True)
    model.write(tmp_path / "basic/ribasim.toml")
    # write sorts the model in place
    assert table.df.iloc[0]["greater_than"] == 5.0
    model_loaded = ribasim.Model(filepath=tmp_path / "basic/ribasim.toml")
    table_loaded = model_loaded.discrete_control.condition
    assert table_loaded.df.iloc[0]["greater_than"] == 5.0
    __assert_equal(table.df, table_loaded.df)
