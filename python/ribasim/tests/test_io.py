from datetime import datetime

import pytest
import ribasim
import tomli
from pandas import DataFrame
from pandas.testing import assert_frame_equal
from pydantic import ValidationError
from ribasim import Model
from ribasim.nodes import pump, terminal


def __assert_equal(a: DataFrame, b: DataFrame) -> None:
    """Lenient version of pandas.testing.assert_frame_equal."""
    if a is None and b is None:
        return
    elif a is None or b is None:
        assert False

    a = a.reset_index(drop=True)
    b = b.reset_index(drop=True)
    a.drop(columns=["fid"], inplace=True, errors="ignore")
    b.drop(columns=["fid"], inplace=True, errors="ignore")

    assert_frame_equal(a, b)


def test_basic(basic, tmp_path):
    model_orig = basic
    toml_path = tmp_path / "basic/ribasim.toml"
    model_orig.write(toml_path)
    model_loaded = Model.read(toml_path)

    with open(toml_path, "rb") as f:
        toml_dict = tomli.load(f)

    assert toml_dict["ribasim_version"] == ribasim.__version__

    __assert_equal(model_orig.edge.df, model_loaded.edge.df)
    __assert_equal(model_orig.node_table().df, model_loaded.node_table().df)
    assert model_loaded.basin.time.df is None


def test_basic_arrow(basic_arrow, tmp_path):
    model_orig = basic_arrow
    model_orig.write(tmp_path / "basic_arrow/ribasim.toml")
    model_loaded = Model.read(tmp_path / "basic_arrow/ribasim.toml")

    __assert_equal(model_orig.basin.profile.df, model_loaded.basin.profile.df)


def test_basic_transient(basic_transient, tmp_path):
    model_orig = basic_transient
    model_orig.write(tmp_path / "basic_transient/ribasim.toml")
    model_loaded = Model.read(tmp_path / "basic_transient/ribasim.toml")

    __assert_equal(model_orig.edge.df, model_loaded.edge.df)

    time = model_loaded.basin.time
    assert model_orig.basin.time.df.time[0] == time.df.time[0]
    __assert_equal(model_orig.basin.time.df, time.df)
    assert time.df.shape == (1468, 7)


@pytest.mark.xfail(reason="Needs implementation")
def test_pydantic():
    pass
    # static_data_bad = pd.DataFrame(data={"node_id": [1, 2, 3]})
    # test that it throws on missing flow_rate


def test_repr():
    pump_static = pump.Static(flow_rate=[1.0, -1.0, 0.0])

    assert repr(pump_static).startswith("Pump / static")
    # Ensure _repr_html doesn't error
    assert isinstance(pump_static._repr_html_(), str)


def test_extra_columns(basic_transient):
    terminal_static = terminal.Static(meta_id=[-1, -2, -3])
    assert "meta_id" in terminal_static.df.columns
    assert (terminal_static.df.meta_id == [-1, -2, -3]).all()

    with pytest.raises(ValidationError):
        # Extra column "extra" needs "meta_" prefix
        terminal.Static(meta_id=[-1, -2, -3], extra=[-1, -2, -3])


def test_sort(level_setpoint_with_minmax, tmp_path):
    model = level_setpoint_with_minmax
    table = model.discrete_control.condition
    edge = model.edge

    # apply a wrong sort, then call the sort method to restore order
    table.df.sort_values("greater_than", ascending=False, inplace=True)
    assert table.df.iloc[0]["greater_than"] == 15.0
    assert table._sort_keys == [
        "node_id",
        "listen_node_id",
        "variable",
        "greater_than",
    ]
    table.sort()
    assert table.df.iloc[0]["greater_than"] == 5.0

    edge.df.sort_values("from_node_type", ascending=False, inplace=True)
    assert edge.df.iloc[0]["from_node_type"] != "Basin"
    edge.sort()
    assert edge.df.iloc[0]["from_node_type"] == "Basin"

    # re-apply wrong sort, then check if it gets sorted on write
    table.df.sort_values("greater_than", ascending=False, inplace=True)
    edge.df.sort_values("from_node_type", ascending=False, inplace=True)
    model.write(tmp_path / "basic/ribasim.toml")
    # write sorts the model in place
    assert table.df.iloc[0]["greater_than"] == 5.0
    model_loaded = ribasim.Model(filepath=tmp_path / "basic/ribasim.toml")
    table_loaded = model_loaded.discrete_control.condition
    edge_loaded = model_loaded.edge
    assert table_loaded.df.iloc[0]["greater_than"] == 5.0
    assert edge.df.iloc[0]["from_node_type"] == "Basin"
    __assert_equal(table.df, table_loaded.df)
    __assert_equal(edge.df, edge_loaded.df)


def test_roundtrip(trivial, tmp_path):
    model1 = trivial
    model1dir = tmp_path / "model1"
    model2dir = tmp_path / "model2"
    # read a model and then write it to a different path
    model1.write(model1dir / "ribasim.toml")
    model2 = Model.read(model1dir / "ribasim.toml")
    model2.write(model2dir / "ribasim.toml")

    assert (model1dir / "database.gpkg").is_file()
    assert (model2dir / "database.gpkg").is_file()

    assert (model1dir / "ribasim.toml").read_text() == (
        model2dir / "ribasim.toml"
    ).read_text()

    # check if all tables are the same
    __assert_equal(model1.node_table().df, model2.node_table().df)
    __assert_equal(model1.edge.df, model2.edge.df)
    for node1, node2 in zip(model1._nodes(), model2._nodes()):
        for table1, table2 in zip(node1._tables(), node2._tables()):
            __assert_equal(table1.df, table2.df)


def test_datetime_timezone():
    # Due to a pydantic issue, a time zone was added.
    # https://github.com/Deltares/Ribasim/issues/1282
    model = ribasim.Model(starttime="2000-01-01", endtime="2001-01-01 00:00:00")
    assert isinstance(model.starttime, datetime)
    assert isinstance(model.endtime, datetime)
    assert model.starttime.tzinfo is None
    assert model.endtime.tzinfo is None
