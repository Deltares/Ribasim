import geopandas as gpd
import pytest
import shapely.geometry as sg
from pydantic import ValidationError
from ribasim.geometry.link import LinkTable, NodeData, _infer_link_type


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

    with pytest.raises(ValidationError):
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
    model = discrete_control_of_pid_control
    model.link.add(model.basin[3], model.pid_control[6])
    assert model.link.df is not None
    added_link = model.link.df.iloc[-1]
    assert added_link["from_node_id"] == 3
    assert added_link["to_node_id"] == 6
    assert added_link["link_type"] == "listen"


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


def test_listen_link_allows_reverse_control(discrete_control_of_pid_control):
    """A listen link should be allowed even when a control link exists in the opposite direction."""
    model = discrete_control_of_pid_control
    # pid_control[6] already has a control link *to* its controlled node;
    # adding a listen link from basin to pid_control should not trigger the
    # "opposite link already exists" error.
    model.link.add(model.basin[3], model.pid_control[6])
    assert model.link.df is not None
    listen_links = model.link.df.loc[model.link.df["link_type"] == "listen"]
    assert not listen_links.empty
