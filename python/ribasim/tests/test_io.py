import hashlib
from datetime import datetime
from pathlib import Path
from time import sleep

import numpy as np
import pandas as pd
import pytest
import ribasim
import tomli
from pandas import DataFrame
from pandas.testing import assert_frame_equal
from pydantic import ValidationError
from ribasim import Model, Node, Solver
from ribasim.nodes import basin, flow_boundary, flow_demand, pump, user_demand
from ribasim.utils import UsedIDs
from shapely.geometry import Point


def __assert_equal(a: DataFrame, b: DataFrame) -> None:
    """Lenient version of pandas.testing.assert_frame_equal."""
    if a is None and b is None:
        return
    elif a is None or b is None:
        assert False

    a = a.reset_index(drop=True)
    b = b.reset_index(drop=True)

    assert_frame_equal(a, b)


def test_basic(basic, tmp_path):
    model_orig = basic
    toml_path = tmp_path / "basic/ribasim.toml"
    assert model_orig.filepath is None
    model_orig.write(toml_path)
    assert model_orig.filepath == toml_path
    model_loaded = Model.read(toml_path)
    assert model_loaded.filepath == toml_path

    with open(toml_path, "rb") as f:
        toml_dict = tomli.load(f)

    assert toml_dict["ribasim_version"] == ribasim.__version__

    __assert_equal(model_orig.link.df, model_loaded.link.df)
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

    __assert_equal(model_orig.link.df, model_loaded.link.df)

    time = model_loaded.basin.time
    assert model_orig.basin.time.df.time.iloc[0] == time.df.time.iloc[0]
    assert time.df.node_id.dtype == "int32"
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


def test_extra_columns():
    pump_static = pump.Static(meta_id=[-1], flow_rate=[1.2])
    assert "meta_id" in pump_static.df.columns
    assert pump_static.df.meta_id.iloc[0] == -1

    with pytest.raises(ValidationError):
        # Extra column "extra" needs "meta_" prefix
        pump.Static(extra=[-2], flow_rate=[1.2])


def test_index_tables():
    p = pump.Static(flow_rate=[1.2])
    assert p.df.index.name == "fid"
    # Index name is applied by _name_index
    df = p.df.reset_index(drop=True)
    assert df.index.name is None
    p.df = df
    assert p.df.index.name == "fid"


def test_extra_spatial_columns():
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        solver=Solver(algorithm="Tsit5"),
    )

    model.basin.add(
        Node(1, Point(0, 0), meta_id=1),
        [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[1.0])],
    )
    node = Node(2, Point(1, 0.5, 3.0), meta_id=2)
    assert not node.geometry.has_z
    model.user_demand.add(
        node,
        [
            user_demand.Static(
                demand=[1e-4], return_factor=0.9, min_level=0.9, demand_priority=1
            )
        ],
    )

    model.link.add(model.basin[1], model.user_demand[2], meta_foo=1)
    assert "meta_foo" in model.link.df.columns
    assert "meta_id" in model.node_table().df.columns

    with pytest.raises(ValidationError):
        model.basin.add(
            Node(3, Point(0, 0), foo=1),
            [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[1.0])],
        )
    with pytest.raises(ValidationError):
        model.user_demand.add(
            Node(4, Point(1, -0.5), meta_id=3),
            [
                user_demand.Static(
                    demand=[1e-4], return_factor=0.9, min_level=0.9, demand_priority=1
                )
            ],
        )
        model.link.add(model.basin[1], model.user_demand[4], foo=1)


def test_link_autoincrement(basic):
    model = basic
    model.link.df = model.link.df.iloc[0:0]  # clear the table
    model.link._used_link_ids = UsedIDs()  # and reset the counter

    model.link.add(model.basin[1], model.manning_resistance[2], link_id=20)
    assert model.link.df.index[-1] == 20

    model.link.add(model.manning_resistance[2], model.basin[3])
    assert model.link.df.index[-1] == 21

    # Can use any remaining positive integer
    model.link.add(model.basin[3], model.tabulated_rating_curve[8], link_id=1)
    assert model.link.df.index[-1] == 1

    with pytest.warns(UserWarning, match="Replacing link #1"):
        model.link.add(
            model.linear_resistance[10],
            model.level_boundary[17],
            link_id=1,
        )


def test_node_autoincrement():
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        solver=Solver(algorithm="Tsit5"),
    )

    model.basin.add(Node(20, Point(0, 0)), [basin.State(level=[1.0])])

    # When adding a node with an existing ID, it should replace the old one
    model.user_demand.add(
        Node(20, Point(1, 0.5)),
        [
            user_demand.Static(
                demand=[1e-4], return_factor=0.9, min_level=0.9, demand_priority=1
            )
        ],
    )
    # Node 20 should now be a user_demand, not a basin
    assert 20 in model.user_demand.node.df.index
    assert 20 in model.user_demand.static.df["node_id"].to_numpy()
    # Basin tables should be None since we replaced its only node
    assert model.basin.node.df is None
    assert model.basin.state.df is None

    nbasin = model.basin.add(Node(geometry=Point(0, 0)), [basin.State(level=[1.0])])
    assert nbasin.node_id == 21

    # Can use any remaining positive integer
    model.basin.add(Node(1, geometry=Point(0, 0)), [basin.State(level=[1.0])])
    nbasin = model.basin.add(Node(geometry=Point(0, 0)), [basin.State(level=[1.0])])
    assert nbasin.node_id == 22

    model.basin.add(Node(100, geometry=Point(0, 0)), [basin.State(level=[1.0])])

    nbasin = model.basin.add(Node(geometry=Point(0, 0)), [basin.State(level=[1.0])])
    assert nbasin.node_id == 101


def test_add_existing():
    """Test replacement on add and `_remove_node_id`."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    # Add multiple basins
    model.basin.add(Node(10, Point(0, 0)), [basin.State(level=[1.0])])
    model.basin.add(Node(10, Point(0, 1)), [basin.State(level=[1.1])])
    model.basin.add(Node(11, Point(1, 0)), [basin.State(level=[2.0])])

    # Check that node_id 10 has the updated Point(0, 1) and level=1.1
    assert model.basin.node.df.loc[10, "geometry"] == Point(0, 1)
    state = model.basin.state.df
    assert state.loc[state["node_id"] == 10, "level"].iloc[0] == [1.1]

    # Add a terminal
    model.terminal.add(Node(20, Point(0, 1)))

    # Test replacement warning
    with pytest.warns(UserWarning, match="Replacing node #20"):
        model.terminal.add(Node(20, Point(0.5, 1)))

    # Add user demands with static data
    model.user_demand.add(
        Node(30, Point(0, 2)),
        [
            user_demand.Static(
                demand=[1e-4], return_factor=0.9, min_level=0.9, demand_priority=1
            )
        ],
    )
    model.link.add(model.basin[10], model.user_demand[30], link_id=1)

    # Remove one Basin, not all
    model.remove_node(11)
    assert len(model.basin.node.df) == 1
    assert 10 in model.basin.node.df.index
    assert 11 not in model.basin.node.df.index
    assert (model.basin.state.df["node_id"] == 10).any()
    assert not (model.basin.state.df["node_id"] == 11).any()

    # Remove the only Terminal
    model.remove_node(20)
    assert model.terminal.node.df is None

    # Remove the only Link
    assert model.link.df is not None
    model.remove_link(1)
    assert model.link.df is None

    # Remove the only UserDemand
    model._remove_node_id(30)
    assert model.user_demand.node.df is None
    assert model.user_demand.static.df is None

    # Do nothing if the node doesn't exist
    model.remove_node(999)


def test_node_autoincrement_existing_model(basic, tmp_path):
    model = basic

    model.write(tmp_path / "ribasim.toml")
    nmodel = Model.read(tmp_path / "ribasim.toml")

    assert nmodel._used_node_ids.max_node_id == 17
    assert nmodel._used_node_ids.node_ids == set(range(1, 18))

    assert nmodel.link._used_link_ids.max_node_id == 17
    assert nmodel.link._used_link_ids.node_ids == set(range(1, 18))


def test_node_empty_geometry():
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    with pytest.raises(ValueError, match="Node geometry must be a valid Point"):
        model.user_demand.add(
            Node(),
            [
                user_demand.Static(
                    demand=[1e-4], return_factor=0.9, min_level=0.9, demand_priority=1
                )
            ],
        )
    with pytest.raises(ValueError, match="Node geometry must be a valid Point"):
        model.user_demand.add(
            Node(2),
            [
                user_demand.Static(
                    demand=[1e-4], return_factor=0.9, min_level=0.9, demand_priority=1
                )
            ],
        )


def test_sort(level_range, tmp_path):
    model = level_range
    table = model.discrete_control.condition
    link = model.link

    # apply a wrong sort, then call the sort method to restore order
    table.df.sort_values("threshold_high", ascending=False, inplace=True)
    assert table.df.iloc[0]["threshold_high"] == 15.0
    assert table._sort_keys == [
        "node_id",
        "compound_variable_id",
        "condition_id",
    ]
    table.sort()
    assert table.df.iloc[0]["threshold_high"] == 5.0

    # The link table is not sorted
    assert link.df.iloc[1]["from_node_id"] == 3

    # re-apply wrong sort, then check if it gets sorted on write
    table.df.sort_values("threshold_high", ascending=False, inplace=True)
    model.write(tmp_path / "basic/ribasim.toml")
    # write sorts the model in place
    assert table.df.iloc[0]["threshold_high"] == 5.0
    model_loaded = ribasim.Model.read(filepath=tmp_path / "basic/ribasim.toml")
    table_loaded = model_loaded.discrete_control.condition
    link_loaded = model_loaded.link
    assert table_loaded.df.iloc[0]["threshold_high"] == 5.0
    assert link.df.iloc[1]["from_node_id"] == 3
    __assert_equal(table.df, table_loaded.df)
    __assert_equal(link.df, link_loaded.df)


def test_roundtrip(trivial, tmp_path):
    model1 = trivial
    # set custom Link index
    model1.link.df.index = pd.Index([15, 12], name="link_id")
    model1dir = tmp_path / "model1"
    model2dir = tmp_path / "model2"
    # read a model and then write it to a different path
    model1.write(model1dir / "ribasim.toml")
    model2 = Model.read(model1dir / "ribasim.toml")
    model2.write(model2dir / "ribasim.toml")

    assert (model1dir / "input/database.gpkg").is_file()
    assert (model2dir / "input/database.gpkg").is_file()

    assert (model1dir / "ribasim.toml").read_text() == (
        model2dir / "ribasim.toml"
    ).read_text()

    # check if custom Link indexes are retained (sorted)
    assert (model1.link.df.index == [12, 15]).all()
    assert (model2.link.df.index == [12, 15]).all()

    # check if all tables are the same
    __assert_equal(model1.node_table().df, model2.node_table().df)
    __assert_equal(model1.link.df, model2.link.df)
    for node1, node2 in zip(model1._nodes(), model2._nodes()):
        for table1, table2 in zip(node1._tables(), node2._tables()):
            __assert_equal(table1.df, table2.df)


def test_roundtrip_netcdf(tabulated_rating_curve_control, tmp_path):
    model1 = tabulated_rating_curve_control
    # confirm NetCDF is configured for Basin / state
    assert model1.basin.state.filepath == Path("basin-state.nc")
    model1dir = tmp_path / "model1"
    # read a model and then write it to a different path
    model1.write(model1dir / "ribasim.toml")
    model2 = Model.read(model1dir / "ribasim.toml")

    assert (model1dir / "input/database.gpkg").is_file()
    assert (model1dir / "input/basin-state.nc").is_file()

    df1 = model1.basin.state.df
    df2 = model2.basin.state.df
    assert df2 is not None
    __assert_equal(df1, df2)
    assert df2.shape == (1, 2)
    assert df2["node_id"].dtype == np.int32
    assert df2["level"].dtype == float


def test_datetime_timezone():
    # Due to a pydantic issue, a time zone was added.
    # https://github.com/Deltares/Ribasim/issues/1282
    model = ribasim.Model(
        starttime="2000-01-01", endtime="2001-01-01 00:00:00", crs="EPSG:28992"
    )
    assert isinstance(model.starttime, datetime)
    assert isinstance(model.endtime, datetime)
    assert model.starttime.tzinfo is None
    assert model.endtime.tzinfo is None


def test_minimal_toml():
    # Check if the TOML used in QGIS tests is still valid.
    toml_path = Path(__file__).parents[3] / "ribasim_qgis/tests/data/simple_valid.toml"
    (toml_path.parent / "database.gpkg").touch()  # database file must exist for `read`
    model = ribasim.Model.read(toml_path)
    assert model.crs == "EPSG:28992"


def test_closed_model(basic, tmp_path):
    # Test whether we can write to a just opened model
    # implicitly testing that the database is closed after read
    toml_path = tmp_path / "basic/ribasim.toml"
    basic.write(toml_path)
    model = ribasim.Model.read(toml_path)
    model.write(toml_path)


def test_pandas_dtype():
    # Extra columns don't get coerced to schema types
    df = flow_boundary.Time(
        time=["2021-01-01 00:00:00.123", "2021-01-01 00:00:00.456"],
        flow_rate=[1, 2.2],
        meta_obj=["foo", "bar"],
        meta_str_python=pd.Series(["a", pd.NA], dtype="string[python]"),
        meta_str_pyarrow=pd.Series(["b", pd.NA], dtype="string[pyarrow]"),
    ).df

    assert (df["node_id"] == 0).all()
    assert df["node_id"].dtype == "int32"
    assert df["time"].dt.tz is None
    assert df["time"].diff().iloc[1] == pd.Timedelta("333ms")
    assert str(df["time"].dtype) == "datetime64[ns]"
    assert df["flow_rate"].dtype == np.float64
    assert df["meta_obj"].dtype == object
    assert df["meta_str_python"].dtype == "string[python]"
    assert df["meta_str_python"].isna().iloc[1]
    assert df["meta_str_pyarrow"].dtype == "string[pyarrow]"
    assert df["meta_str_pyarrow"].isna().iloc[1]

    # Check a string column that is part of the schema and a boolean column
    df = pump.Static(
        flow_rate=np.ones(2),
        control_state=["foo", pd.NA],
    ).df

    assert df["control_state"].dtype == "string[python]"

    # Optional integer column
    df = flow_demand.Static(
        demand=[1, 2.2],
        demand_priority=[1, pd.NA],
    ).df

    assert df["demand_priority"].dtype == "Int32"
    assert df["demand_priority"].isna().iloc[1]

    # Missing optional integer column
    df = flow_demand.Static(
        demand=[1, 2.2],
    ).df

    assert df["demand_priority"].dtype == "Int32"
    assert df["demand_priority"].isna().all()


def test_consistent_binary_output(basic, tmp_path):
    # Test whether regenerated file is identical to original
    # so tools like DVC can be used to track changes
    toml_path = tmp_path / "basic/ribasim.toml"
    basic.write(toml_path)

    db_path = toml_path.parent / basic.input_dir / "database.gpkg"
    with open(db_path, "rb") as f:
        res = hashlib.md5(f.read())
        original_hash = res.hexdigest()

    sleep(2)  # ensure timestamps change
    basic.write(toml_path)
    with open(db_path, "rb") as f:
        res = hashlib.md5(f.read())
        new_hash = res.hexdigest()

    assert original_hash == new_hash
