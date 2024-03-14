import pytest
import ribasim
import tomli
from pandas import DataFrame
from pandas.testing import assert_frame_equal
from pydantic import ValidationError
from ribasim.nodes import pump, terminal


def __assert_equal(a: DataFrame, b: DataFrame, is_network=False) -> None:
    """Like pandas.testing.assert_frame_equal, but ignoring the index."""
    if a is None and b is None:
        return True

    if is_network:
        # We set this on write, needed for GeoPackage.
        a.index.name = "fid"
        a.index.name = "fid"

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
    toml_path = tmp_path / "basic/ribasim.toml"
    model_orig.write(toml_path)
    model_loaded = ribasim.Model(filepath=toml_path)

    with open(toml_path, "rb") as f:
        toml_dict = tomli.load(f)

    assert toml_dict["ribasim_version"] == ribasim.__version__

    __assert_equal(model_orig.edge.df, model_loaded.edge.df, is_network=True)
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

    __assert_equal(model_orig.edge.df, model_loaded.edge.df, is_network=True)

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

    # re-apply wrong sort, then check if it gets sorted on write
    table.df.sort_values("greater_than", ascending=False, inplace=True)
    model.write(tmp_path / "basic/ribasim.toml")
    # write sorts the model in place
    assert table.df.iloc[0]["greater_than"] == 5.0
    model_loaded = ribasim.Model(filepath=tmp_path / "basic/ribasim.toml")
    table_loaded = model_loaded.discrete_control.condition
    assert table_loaded.df.iloc[0]["greater_than"] == 5.0
    __assert_equal(table.df, table_loaded.df)


@pytest.mark.xfail(reason="Needs Model read implementation")
def test_roundtrip(trivial, tmp_path):
    model1 = trivial
    model1dir = tmp_path / "model1"
    model2dir = tmp_path / "model2"
    # read a model and then write it to a different path
    model1.write(model1dir / "ribasim.toml")
    model2 = ribasim.Model(filepath=model1dir / "ribasim.toml")
    model2.write(model2dir / "ribasim.toml")

    assert (model1dir / "database.gpkg").is_file()
    assert (model2dir / "database.gpkg").is_file()

    assert (model1dir / "ribasim.toml").read_text() == (
        model2dir / "ribasim.toml"
    ).read_text()

    # check if all tables are the same
    __assert_equal(model1.network.node.df, model2.network.node.df, is_network=True)
    __assert_equal(model1.network.edge.df, model2.network.edge.df, is_network=True)
    for node1, node2 in zip(model1.nodes().values(), model2.nodes().values()):
        for table1, table2 in zip(node1.tables(), node2.tables()):
            __assert_equal(table1.df, table2.df)
