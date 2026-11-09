import geopandas as gpd
import pytest
import shapely.geometry as sg
from pandera.errors import SchemaErrors
from pydantic import ValidationError
from ribasim import Model, Node
from ribasim.geometry.link import LinkTable, NodeData, _infer_link_type
from ribasim.nodes import basin, junction, pump, user_demand


@pytest.fixture(scope="session")
def link() -> LinkTable:
    a = (0.0, 0.0)
    b = (0.0, 1.0)
    c = (0.2, 0.5)
    d = (1.0, 1.0)
    geometry = [sg.LineString([a, b, c]), sg.LineString([a, d])]
    df = gpd.GeoDataFrame(
        data={"link_id": [0, 1], "from_node_id": [1, 1], "to_node_id": [2, 3]},
        geometry=geometry,
    )
    df.set_index("link_id", inplace=True)
    link = LinkTable(df=df)
    return link


def test_validation(link):
    assert isinstance(link, LinkTable)

    with pytest.raises((ValidationError, SchemaErrors)):
        df = gpd.GeoDataFrame(
            data={
                "link_id": [0, 1],
                "from_node_id": [1, 1],
                "to_node_id": ["foo", 3],
            },  # None is coerced to 0 without errors
            geometry=[None, None],
        )
        df.set_index("link_id", inplace=True)
        LinkTable(df=df)


def test_link_plot(link):
    link.plot()


def test_link_indexing(link):
    with pytest.raises(NotImplementedError):
        link[1]


def test_invalid_retour_link(basic):
    with pytest.raises(ValueError, match="opposite link already exists"):
        basic.link.add(basic.manning_resistance[2], basic.basin[1])


def test_node_data():
    node = NodeData(node_id=5, node_type="Pump", geometry=sg.Point(0, 0))
    assert repr(node) == "Pump #5"


def test_listen_link_type_inference(discrete_control_of_pid_control):
    """Listen links are auto-added when a control link is created."""
    model = discrete_control_of_pid_control
    listen_links = model.link.df.loc[model.link.df["link_type"] == "listen"]
    # Basin(3)->PidControl(6) was auto-added when PidControl(6)->Outlet(2) control link was created
    basin_to_pid = listen_links.loc[
        (listen_links["from_node_id"] == 3) & (listen_links["to_node_id"] == 6)
    ]
    assert len(basin_to_pid) == 1
    assert basin_to_pid.iloc[0]["link_type"] == "listen"


@pytest.mark.parametrize(
    ("from_type", "to_type", "expected"),
    [
        ("Basin", "LinearResistance", "flow"),
        ("Pump", "Basin", "flow"),
        ("DiscreteControl", "Pump", "control"),
        ("PidControl", "Outlet", "control"),
        ("FlowDemand", "Pump", "control"),
        ("LevelDemand", "Basin", "control"),
        ("Basin", "PidControl", "listen"),
        ("Basin", "DiscreteControl", "listen"),
        ("LinearResistance", "ContinuousControl", "listen"),
        ("Observation", "Basin", "observation"),
        ("Observation", "Pump", "observation"),
    ],
)
def test_infer_link_type(from_type: str, to_type: str, expected: str):
    assert _infer_link_type(from_type, to_type) == expected


def test_validate_link_rejects_excess_inneighbors(basic):
    """Adding a second flow inneighbor to a node with max 1 should raise."""
    model = basic
    with pytest.raises(ValueError, match="at most 1 flow link inneighbor"):
        # LinearResistance allows at most 1 flow inneighbor; it already has one
        model.link.add(model.basin[1], model.linear_resistance[10])


@pytest.mark.parametrize(
    "upstream",
    [("basin", "junction"), ("junction", "basin"), ("junction", "junction")],
)
def test_validate_link_user_demand_junction_inflow(upstream: tuple[str, str]):
    """A UserDemand has either Basin inflow(s) or exactly one inflow from a Junction with rows."""
    model = Model(starttime="2020-01-01", endtime="2021-01-01", crs="EPSG:28992")
    nodes = {
        "basin": [
            model.basin.add(
                Node(1, sg.Point(0, 0)),
                [
                    basin.State(level=[1.0]),
                    basin.Profile(level=[0.0, 2.0], area=[100.0, 200.0]),
                ],
            )
        ],
        "junction": [
            model.junction.add(
                Node(node_id, sg.Point(0, node_id)),
                [junction.Static(to_node_id=[5], fraction=[1.0])],
            )
            for node_id in (2, 3)
        ],
    }
    ud = model.user_demand.add(
        Node(4, sg.Point(1, 0)),
        [
            user_demand.Static(
                demand_priority=[1], demand=[1e-4], return_factor=0.5, min_level=[0.0]
            )
        ],
    )
    first, second = (nodes[upstream[0]].pop(), nodes[upstream[1]].pop())
    model.link.add(first, ud)
    with pytest.raises(ValueError, match="exactly one inflow link from a Junction"):
        model.link.add(second, ud)


def test_validate_link_connector_cannot_split_into_junctions():
    """A connector node cannot flow into multiple Junctions, a Junction with fractions divides its flow."""
    model = Model(starttime="2020-01-01", endtime="2021-01-01", crs="EPSG:28992")
    pmp = model.pump.add(Node(1, sg.Point(0, 0)), [pump.Static(flow_rate=[1e-3])])
    jct1 = model.junction.add(Node(2, sg.Point(1, 1)))
    jct2 = model.junction.add(Node(3, sg.Point(1, -1)))
    model.link.add(pmp, jct1)
    with pytest.raises(ValueError, match="at most 1 flow link outneighbor"):
        model.link.add(pmp, jct2)


def test_validate_link_junction_can_split_into_junctions():
    """A Junction with fractions can flow into multiple Junctions, with or without rows."""
    model = Model(starttime="2020-01-01", endtime="2021-01-01", crs="EPSG:28992")
    jct = model.junction.add(
        Node(1, sg.Point(0, 0)),
        [junction.Static(to_node_id=[2, 3], fraction=[0.5, 0.5])],
    )
    jct1 = model.junction.add(
        Node(2, sg.Point(1, 1)), [junction.Static(to_node_id=[4], fraction=[1.0])]
    )
    jct2 = model.junction.add(Node(3, sg.Point(1, -1)))
    model.link.add(jct, jct1)
    model.link.add(jct, jct2)


def test_listen_link_allows_reverse_control(discrete_control_of_pid_control):
    """A listen link is auto-added even when a control link exists in the opposite direction."""
    model = discrete_control_of_pid_control
    # pid_control #6 has a control link *to* outlet #2;
    # the listen link from basin #3 to pid_control #6 was auto-added
    # without triggering the "opposite link already exists" error.
    listen_links = model.link.df.loc[model.link.df["link_type"] == "listen"]
    assert not listen_links.empty
